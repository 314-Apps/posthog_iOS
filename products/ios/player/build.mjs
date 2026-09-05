import { build } from 'esbuild'
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const sharedPackage = resolve(repoRoot, 'common/replay-shared')

/**
 * `@posthog/replay-shared` is a workspace package, and neither npm's workspace
 * protocol nor its `catalog:` dependencies resolve from this directory. Link it
 * by hand so a plain `npm install` plus `npm run build` is the whole recipe.
 */
function linkSharedPackage() {
    const scope = resolve(here, 'node_modules/@posthog')
    const target = resolve(scope, 'replay-shared')

    mkdirSync(scope, { recursive: true })

    if (existsSync(target) || lstatSync(target, { throwIfNoEntry: false })) {
        const link = lstatSync(target)
        if (link.isSymbolicLink() && resolve(scope, readlinkSync(target)) === sharedPackage) {
            return
        }
        throw new Error(`${target} exists and is not the expected link to ${sharedPackage}`)
    }

    symlinkSync(relative(scope, sharedPackage), target, 'dir')
}

linkSharedPackage()

if (process.argv.includes('--link-only')) {
    process.exit(0)
}

/**
 * `HLSPlayerPlugin` is a module-level `createHLSPlayerPlugin()` call in the shared package,
 * so esbuild keeps it — and the ~380 KB of hls.js behind its dynamic import — even though
 * nothing here installs it. Marking that one call pure lets both fall out of the artifact.
 *
 * The plugin hands a URL read off a recorded `<video hls-src>` straight to hls.js, which
 * then fetches the manifest and every segment. This page must not carry that code at all,
 * not merely leave it unreached.
 */
const dropHlsPlayerPlugin = {
    name: 'drop-hls-player-plugin',
    setup(build) {
        build.onLoad({ filter: /replay-shared\/src\/rrweb-plugins\/index\.ts$/ }, (args) => {
            const source = readFileSync(args.path, 'utf-8')
            const declaration = 'export const HLSPlayerPlugin: ReplayPlugin = createHLSPlayerPlugin()'
            if (!source.includes(declaration)) {
                throw new Error(`${args.path} no longer declares HLSPlayerPlugin the way this build expects`)
            }
            return {
                contents: source.replace(declaration, declaration.replace('= create', '= /* @__PURE__ */ create')),
                loader: 'ts',
            }
        })
    },
}

const result = await build({
    entryPoints: [resolve(here, 'src/ios-player.ts')],
    bundle: true,
    write: false,
    // The linked shared package resolves to its real path under common/, where a
    // walk up the tree finds no node_modules. Point its imports back here, so the
    // whole bundle is built against this directory's single pinned posthog-js.
    nodePaths: [resolve(here, 'node_modules')],
    format: 'iife',
    platform: 'browser',
    target: 'es2020',
    minify: true,
    sourcemap: false,
    legalComments: 'none',
    plugins: [dropHlsPlayerPlugin],
    define: {
        'process.env.NODE_ENV': '"production"',
        'process.env.LANG': '""',
        'process.env': '{}',
    },
})

const js = result.outputFiles[0].text
const shell = readFileSync(resolve(here, 'src/index.html'), 'utf-8')
// A replacer function, so `$&` and friends inside the bundle are not read as
// replacement patterns.
const html = shell.replace('<!-- INLINE_JS -->', () => `<script>${js}</script>`)

if (html.includes('<!-- INLINE_JS -->')) {
    throw new Error('src/index.html no longer carries the <!-- INLINE_JS --> placeholder')
}

/**
 * The policy is the only thing stopping the replayed DOM from fetching whatever hosts the
 * recording names, so an artifact without it must never reach the app bundle.
 */
if (!/<meta\s+http-equiv="Content-Security-Policy"/i.test(html)) {
    throw new Error('src/index.html no longer carries the Content-Security-Policy meta tag')
}

// A plugin that walks recorded URLs must not come back by accident. The proxy host is
// CorsPlugin's, and the attribute is the one HLSPlayerPlugin reads off a recorded <video>.
for (const [needle, why] of [
    ['replay.ph-proxy.com', 'CorsPlugin rewrites recorded asset URLs through a public proxy'],
    ['hls-src', 'HLSPlayerPlugin loads a recorded URL through hls.js'],
]) {
    if (html.includes(needle)) {
        throw new Error(`The bundle contains ${needle}: ${why}`)
    }
}

const bytes = Buffer.byteLength(html)
const sha256 = createHash('sha256').update(html).digest('hex')

// Written straight into the app bundle as well as dist/. A separate copy step can leave the
// shipped page a build behind, and two builds of this page are the same length either way,
// so nothing about the file would show it.
const targets = [
    resolve(here, 'dist/player.html'),
    resolve(repoRoot, 'products/ios/Packages/PostHogKit/Sources/FeatureReplay/Resources/player.html'),
]

for (const target of targets) {
    mkdirSync(dirname(target), { recursive: true })
    writeFileSync(target, html)
    process.stdout.write(`${relative(here, target)}  ${bytes} bytes  sha256:${sha256}\n`)
}
