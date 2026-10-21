import pLimit from 'p-limit'
import { Replayer } from 'posthog-js/rrweb'

import {
    AudioMuteReplayerPlugin,
    CanvasReplayerPlugin,
    COMMON_REPLAYER_CONFIG,
    createSegments,
    createWindowIdRegistry,
    keyForSource,
    mapSnapshotsToWindowId,
    mergeInactiveSegments,
    noOpTelemetry,
    parseJsonSnapshots,
    processAllSnapshots,
    SnapshotSourceType,
    transformToWeb,
    type ProcessingCache,
    type RecordingSegment,
    type RecordingSnapshot,
    type RegisterWindowIdCallback,
    type SessionRecordingSnapshotSource,
    type SessionRecordingSnapshotSourceResponse,
    type SourceKey,
} from '@posthog/replay-shared'

import {
    BLOCK_URL_PREFIX,
    describeError,
    installCommandSurface,
    NativeBridge,
    readConfig,
    type IosPlayerConfig,
    type PlayerCommands,
} from './bridge'

const TIME_TICK_MS = 250
const MAX_CONCURRENT_FETCHES = 6
/** A block comes off local storage, so anything this slow is a scheme handler that is stuck. */
const BLOCK_DEADLINE_MS = 30_000
/** The backstop for every other way the load path can stop making progress. */
const LOAD_STALL_MS = 45_000

// The shared pipeline keys its telemetry throttling by recording id. Nothing here reports
// telemetry, so any stable string does.
const SESSION_ID = 'ios-bundled-player'

interface LoadedBlocks {
    sources: SessionRecordingSnapshotSource[]
    snapshotsBySource: Record<SourceKey, SessionRecordingSnapshotSourceResponse>
}

/** Thrown to unwind the load once the page has already been stopped. */
class PlayerStopped extends Error {
    constructor() {
        super('The player was stopped by a terminal error')
        this.name = 'PlayerStopped'
    }
}

/**
 * Keeps the contract's "exactly one `ready` or one `error`" promise from both sides.
 *
 * A stall window makes sure something terminal is always posted, and the abort signal
 * makes sure a posted `error` really is the end: without it the load runs on behind the
 * app's back and hands it a live player for a session it was told had failed.
 */
class LoadGuard {
    private timer: number | undefined
    private readonly controller = new AbortController()

    /** Assigned once `fail` exists, so a stall is reported the way any other failure is. */
    onStall: (reason: string) => void = () => {}

    constructor(private readonly stallMs: number) {}

    get signal(): AbortSignal {
        return this.controller.signal
    }

    get stopped(): boolean {
        return this.controller.signal.aborted
    }

    /** Restart the stall window. `stage` says what the page is waiting for. */
    poke(stage: string): void {
        this.clear()
        this.timer = window.setTimeout(() => this.onStall(`Gave up ${stage}`), this.stallMs)
    }

    /** A terminal message went out; nothing is owed any more. */
    done(): void {
        this.clear()
    }

    /** Cancel work in flight and make every checkpoint downstream bail out. */
    stop(): void {
        this.clear()
        this.controller.abort()
    }

    private clear(): void {
        if (this.timer !== undefined) {
            window.clearTimeout(this.timer)
            this.timer = undefined
        }
    }
}

function checkpoint(guard: LoadGuard): void {
    if (guard.stopped) {
        throw new PlayerStopped()
    }
}

/**
 * `AbortSignal` only helps when the other side honors it, and a `WKURLSchemeHandler` that
 * returns without calling back honors nothing. Race the work as well, so the page settles
 * either way.
 */
function withDeadline<T>(work: Promise<T>, ms: number, message: string, onExpire: () => void): Promise<T> {
    return new Promise<T>((resolve, reject) => {
        const timer = window.setTimeout(() => {
            onExpire()
            reject(new Error(message))
        }, ms)
        work.then(
            (value) => {
                window.clearTimeout(timer)
                resolve(value)
            },
            (error) => {
                window.clearTimeout(timer)
                reject(error)
            }
        )
    })
}

async function fetchBlock(index: number, guard: LoadGuard): Promise<string> {
    const controller = new AbortController()
    const stop = (): void => controller.abort()
    guard.signal.addEventListener('abort', stop)

    try {
        const request = (async (): Promise<string> => {
            const response = await fetch(`${BLOCK_URL_PREFIX}${index}`, { signal: controller.signal })
            if (!response.ok) {
                throw new Error(`Block ${index} returned ${response.status} ${response.statusText}`)
            }
            return response.text()
        })()

        return await withDeadline(
            request,
            BLOCK_DEADLINE_MS,
            `Block ${index} did not arrive within ${BLOCK_DEADLINE_MS / 1000}s`,
            stop
        )
    } finally {
        guard.signal.removeEventListener('abort', stop)
    }
}

/**
 * `parseJsonSnapshots` drops a line it cannot read and reports the count only through
 * telemetry, which this page discards. One line at a time makes the loss countable, so a
 * truncated block fails loudly instead of replaying as a short recording.
 */
function parseBlock(index: number, lines: string[], registerWindowId: RegisterWindowIdCallback): RecordingSnapshot[] {
    const snapshots: RecordingSnapshot[] = []
    let unreadable = 0
    let undated = 0

    for (const line of lines) {
        const parsed = parseJsonSnapshots([line], SESSION_ID, noOpTelemetry, registerWindowId)
        if (!parsed.length) {
            unreadable += 1
            continue
        }
        for (const snapshot of parsed) {
            // A line can be valid JSON and still not be an event. Sorting, segmenting and
            // the duration all do arithmetic on `timestamp`, and NaN travels from here
            // into the `ready` message the app reads as an Int.
            if (Number.isFinite(snapshot.timestamp)) {
                snapshots.push(snapshot)
            } else {
                undated += 1
            }
        }
    }

    const damage: string[] = []
    if (unreadable) {
        damage.push(`${unreadable} line(s) could not be read`)
    }
    if (undated) {
        damage.push(`${undated} event(s) carried no usable timestamp`)
    }
    if (damage.length) {
        throw new Error(`Block ${index} is damaged: ${damage.join(' and ')}, out of ${lines.length} line(s)`)
    }

    return snapshots
}

async function loadBlocks(config: IosPlayerConfig, bridge: NativeBridge, guard: LoadGuard): Promise<LoadedBlocks> {
    const { blockCount } = config
    bridge.postProgress(0, blockCount)

    if (blockCount === 0) {
        return { sources: [], snapshotsBySource: {} }
    }

    const registerWindowId = createWindowIdRegistry()
    const limit = pLimit(MAX_CONCURRENT_FETCHES)
    let loaded = 0

    guard.poke(`waiting for ${blockCount} recording block(s)`)

    const results = await Promise.all(
        Array.from({ length: blockCount }, (_, index) =>
            limit(async () => {
                const text = await fetchBlock(index, guard)
                const snapshots = parseBlock(index, text.split('\n').filter(Boolean), registerWindowId)
                loaded += 1
                bridge.postProgress(loaded, blockCount)
                guard.poke(`waiting for ${blockCount - loaded} more recording block(s)`)
                return { index, snapshots }
            })
        )
    )

    const sources: SessionRecordingSnapshotSource[] = []
    const snapshotsBySource: Record<SourceKey, SessionRecordingSnapshotSourceResponse> = {}

    for (const { index, snapshots } of results) {
        const source: SessionRecordingSnapshotSource = {
            source: SnapshotSourceType.blob_v2,
            blob_key: String(index),
        }
        sources.push(source)
        snapshotsBySource[keyForSource(source)] = { snapshots, sourceLoaded: true }
    }

    return { sources, snapshotsBySource }
}

/**
 * `parseJsonSnapshots` already converts each event, so this is a second pass over
 * anything that reached us in a shape the per-event conversion could not match.
 */
function applyMobileTransform(snapshots: RecordingSnapshot[]): RecordingSnapshot[] {
    const web = transformToWeb(snapshots, noOpTelemetry)
    // The transform is one event in, one event out, but a transformer may return a fresh
    // object — `makeMetaEvent` does — which drops the windowId the segmenter keys on.
    return web.map((event, index) => ({ ...event, windowId: snapshots[index].windowId }))
}

/** Fits the recording's native resolution inside the web view, centered. */
class ViewportScaler {
    private recWidth = 0
    private recHeight = 0

    constructor(private contentEl: HTMLElement) {
        window.addEventListener('resize', () => this.apply(this.recWidth, this.recHeight))
    }

    apply(recWidth: number, recHeight: number): void {
        const availW = window.innerWidth
        const availH = window.innerHeight
        if (recWidth <= 0 || recHeight <= 0 || availW <= 0 || availH <= 0) {
            return
        }
        this.recWidth = recWidth
        this.recHeight = recHeight

        const scale = Math.min(availW / recWidth, availH / recHeight)
        const offsetX = (availW - recWidth * scale) / 2
        const offsetY = (availH - recHeight * scale) / 2

        // Clip the content element to the recording's native size, then scale it down
        // and center it within the available space.
        this.contentEl.style.width = `${recWidth}px`
        this.contentEl.style.height = `${recHeight}px`
        this.contentEl.style.overflow = 'hidden'
        this.contentEl.style.transformOrigin = 'top left'
        this.contentEl.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`
    }

    attachToReplayer(replayer: Replayer): void {
        const iframeWidth = Number.parseFloat(replayer.iframe.width)
        const iframeHeight = Number.parseFloat(replayer.iframe.height)
        if (iframeWidth > 0 && iframeHeight > 0) {
            this.apply(iframeWidth, iframeHeight)
        }

        replayer.on('resize', (dimension: { width: number; height: number }) => {
            this.apply(dimension.width, dimension.height)
        })
    }
}

function durationOf(segments: RecordingSegment[], snapshots: RecordingSnapshot[], firstTimestamp: number): number {
    const lastSegment = segments[segments.length - 1]
    const lastTimestamp = lastSegment ? lastSegment.endTimestamp : snapshots[snapshots.length - 1].timestamp
    if (!Number.isFinite(lastTimestamp) || !Number.isFinite(firstTimestamp)) {
        return Number.NaN
    }
    return Math.max(0, lastTimestamp - firstTimestamp)
}

async function start(
    config: IosPlayerConfig,
    bridge: NativeBridge,
    guard: LoadGuard,
    publish: (c: PlayerCommands) => void
): Promise<void> {
    const contentEl = document.querySelector<HTMLElement>('.PlayerFrame__content')
    if (!contentEl) {
        throw new Error('Player shell is missing its .PlayerFrame__content element')
    }

    const { sources, snapshotsBySource } = await loadBlocks(config, bridge, guard)
    checkpoint(guard)

    const processingCache: ProcessingCache = { snapshots: {} }
    guard.poke('processing the recording')
    // Nothing outside the snapshots themselves knows the viewport here: the app sends
    // blocks, not the events the web player mines for resolution.
    const processed = await processAllSnapshots(
        sources,
        snapshotsBySource,
        processingCache,
        () => undefined,
        SESSION_ID,
        noOpTelemetry
    )
    checkpoint(guard)

    const snapshots = config.isMobile ? applyMobileTransform(processed) : processed
    if (!snapshots.length) {
        throw new Error(`No playable snapshots in ${config.blockCount} block(s)`)
    }

    const firstTimestamp = snapshots[0].timestamp
    const snapshotsByWindowId = mapSnapshotsToWindowId(snapshots)
    const segments = mergeInactiveSegments(
        createSegments(
            snapshots,
            firstTimestamp,
            snapshots[snapshots.length - 1].timestamp,
            null,
            snapshotsByWindowId
        )
    )

    const duration = durationOf(segments, snapshots, firstTimestamp)
    if (!Number.isFinite(duration)) {
        throw new Error('The recording has no usable duration')
    }

    const events = [...snapshots]
    const replayer = new Replayer(events, {
        root: contentEl,
        ...COMMON_REPLAYER_CONFIG,
        // Recorded content must stay scriptless: replaying canvas the unsafe way adds
        // `allow-scripts` to the replay iframe's sandbox, which is also what stops the
        // page's Content-Security-Policy from being the only thing between a recorded
        // <script> and execution.
        UNSAFE_replayCanvas: false,
        useVirtualDom: false,
        // A mobile recording has no pointer to trail.
        mouseTail: !config.isMobile,
        // Neither of these two reaches the network: the mute plugin sets `muted`, and the
        // canvas plugin replays recorded draw commands. HLSPlayerPlugin is left out because
        // it hands a recorded `hls-src` to hls.js from this frame, and CorsPlugin because it
        // rewrites recorded asset URLs through a public proxy. Leaving them out is not what
        // keeps the recording off the network, though — the page's CSP is.
        plugins: [AudioMuteReplayerPlugin(true), CanvasReplayerPlugin(events)],
        speed: config.playbackSpeed,
    })

    const scaler = new ViewportScaler(contentEl)
    scaler.attachToReplayer(replayer)

    let ticker: number | undefined
    const stopTicker = (): void => {
        if (ticker !== undefined) {
            window.clearInterval(ticker)
            ticker = undefined
        }
    }
    const startTicker = (): void => {
        if (ticker !== undefined) {
            return
        }
        ticker = window.setInterval(() => bridge.postTime(replayer.getCurrentTime()), TIME_TICK_MS)
    }

    let playing = false
    replayer.on('finish', () => {
        playing = false
        stopTicker()
        bridge.postEnded()
    })

    // Render the first frame so the app has a picture before anyone presses play.
    replayer.pause(0)

    guard.done()
    bridge.postReady(duration)

    // Only now, so a command that arrives before `ready` really is a no-op.
    publish({
        play: () => {
            // rrweb's play() with no argument restarts from zero; pass the position to resume.
            replayer.play(replayer.getCurrentTime())
            playing = true
            startTicker()
        },
        pause: () => {
            replayer.pause()
            playing = false
            stopTicker()
        },
        seek: (ms: number) => {
            const target = Math.min(Math.max(0, Number.isFinite(ms) ? ms : 0), duration)
            if (playing) {
                replayer.play(target)
                startTicker()
            } else {
                replayer.pause(target)
            }
            bridge.postTime(target)
        },
        setSpeed: (speed: number) => {
            if (Number.isFinite(speed) && speed > 0) {
                replayer.setConfig({ speed })
            }
        },
    })
}

const bridge = new NativeBridge()
const publish = installCommandSurface()
const guard = new LoadGuard(LOAD_STALL_MS)

const fail = (err: unknown): void => {
    if (bridge.isSettled) {
        return
    }
    bridge.postError(describeError(err))
    guard.stop()
}

guard.onStall = (reason: string) => fail(new Error(reason))

window.addEventListener('error', (event: ErrorEvent) => fail(event.error ?? event.message))
window.addEventListener('unhandledrejection', (event: PromiseRejectionEvent) => fail(event.reason))

try {
    start(readConfig(), bridge, guard, publish).catch(fail)
} catch (err) {
    fail(err)
}
