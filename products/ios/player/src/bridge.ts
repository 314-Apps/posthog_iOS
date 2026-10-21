/**
 * The native/JS contract, in one place.
 *
 * Swift registers a `WKURLSchemeHandler` for `posthog-replay` and a
 * `WKScriptMessageHandler` named `posthogPlayer`. Everything this page
 * says to the app goes through `postMessage`, and everything the app
 * says to this page arrives on `window.posthogPlayer`.
 */

export const BLOCK_URL_PREFIX = 'posthog-replay://player/__blocks/'

export const CONFIG_KEY = '__posthog_player_config__'

export interface IosPlayerConfig {
    blockCount: number
    isMobile: boolean
    playbackSpeed: number
}

export type PageMessage =
    | { type: 'progress'; loaded: number; total: number }
    | { type: 'ready'; duration: number }
    | { type: 'time'; current: number }
    | { type: 'ended' }
    | { type: 'error'; message: string }

/** Commands the app may call once `ready` has been posted. */
export interface PlayerCommands {
    play: () => void
    pause: () => void
    seek: (ms: number) => void
    setSpeed: (speed: number) => void
}

interface WebKitMessageHandler {
    postMessage: (body: unknown) => void
}

declare global {
    interface Window {
        [CONFIG_KEY]?: Partial<IosPlayerConfig>
        posthogPlayer?: PlayerCommands
        webkit?: {
            messageHandlers?: {
                posthogPlayer?: WebKitMessageHandler
            }
        }
    }
}

export function readConfig(): IosPlayerConfig {
    const raw = window[CONFIG_KEY]
    if (!raw || typeof raw !== 'object') {
        throw new Error(`window.${CONFIG_KEY} was not injected before the page ran`)
    }
    const blockCount = Number(raw.blockCount)
    if (!Number.isFinite(blockCount) || blockCount < 0) {
        throw new Error(`config.blockCount must be a non-negative number, got ${String(raw.blockCount)}`)
    }
    const playbackSpeed = Number(raw.playbackSpeed)
    return {
        blockCount: Math.floor(blockCount),
        isMobile: raw.isMobile === true,
        playbackSpeed: Number.isFinite(playbackSpeed) && playbackSpeed > 0 ? playbackSpeed : 1,
    }
}

/**
 * Swift reads these as numbers and converts them to `Int`. `Math.max(0, NaN)` is NaN,
 * so a clamp alone is not enough to keep a non-numeric timestamp out of the contract.
 */
function millis(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0
}

export class NativeBridge {
    /** Set once `ready` or `error` has been posted; the contract allows exactly one of them. */
    private settled = false
    /** `error` is terminal: nothing may follow it. */
    private dead = false

    private send(message: PageMessage): void {
        const handler = window.webkit?.messageHandlers?.posthogPlayer
        if (!handler) {
            return
        }
        try {
            handler.postMessage(message)
        } catch {
            // A dropped message must never take playback down with it.
        }
    }

    get isSettled(): boolean {
        return this.settled
    }

    postProgress(loaded: number, total: number): void {
        if (this.dead) {
            return
        }
        this.send({ type: 'progress', loaded, total })
    }

    postReady(duration: number): void {
        if (this.settled) {
            return
        }
        this.settled = true
        this.send({ type: 'ready', duration: millis(duration) })
    }

    postTime(current: number): void {
        if (this.dead) {
            return
        }
        this.send({ type: 'time', current: millis(current) })
    }

    postEnded(): void {
        if (this.dead) {
            return
        }
        this.send({ type: 'ended' })
    }

    postError(message: string): void {
        if (this.settled) {
            return
        }
        this.settled = true
        this.dead = true
        this.send({ type: 'error', message })
    }
}

/**
 * Publish `window.posthogPlayer` immediately, so a command that arrives
 * before the replayer exists is a no-op rather than a TypeError in the
 * app's `evaluateJavaScript` callback.
 */
export function installCommandSurface(): (commands: PlayerCommands) => void {
    let live: PlayerCommands | null = null

    window.posthogPlayer = {
        play: () => live?.play(),
        pause: () => live?.pause(),
        seek: (ms: number) => live?.seek(Number(ms)),
        setSpeed: (speed: number) => live?.setSpeed(Number(speed)),
    }

    return (commands: PlayerCommands) => {
        live = commands
    }
}

export function describeError(err: unknown): string {
    if (err instanceof Error) {
        return err.name && err.name !== 'Error' ? `${err.name}: ${err.message}` : err.message
    }
    if (typeof err === 'string') {
        return err
    }
    try {
        const encoded = JSON.stringify(err)
        return encoded && encoded !== '{}' ? encoded : String(err)
    } catch {
        return String(err)
    }
}
