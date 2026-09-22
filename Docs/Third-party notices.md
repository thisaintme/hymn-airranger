# Third-party components and source access

The application source is MIT-licensed (LICENSE at the repository root). A prebuilt application also contains the separate, unmodified JavaScript/WebAssembly libraries below. Their upstream notices and licenses continue to apply. No standalone font files, commercial sound samples, or Apple framework binaries are bundled.

## Verovio 6.2.0 — LGPL v3

Local music engraving from MEI to SVG; copyright belongs to the Verovio contributors and embedded component authors. This app uses the unmodified toolkit from:

https://www.verovio.org/javascript/6.2.0/verovio-toolkit-wasm.js

The corresponding upstream version, including C++ sources, bundled dependencies, data, build scripts and notices, is available without charge:

- Source tree: https://github.com/rism-digital/verovio/tree/version-6.2.0
- Source archive: https://github.com/rism-digital/verovio/archive/refs/tags/version-6.2.0.tar.gz
- Upstream release: https://github.com/rism-digital/verovio/releases/tag/version-6.2.0
- JavaScript build instructions: https://book.verovio.org/installing-or-building-from-sources/javascript-and-webassembly.html

Retain the individual notices in that source distribution when modifying or redistributing its components. Engraving glyph resources are part of the upstream toolkit; no separate font installer is supplied.

## lamejs 1.2.1 — LGPL v3

Local MP3 encoding through JavaScriptCore; upstream package author Alex Zhukov, based on LAME. This app uses the unmodified, readable JavaScript toolkit:

https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.all.js

The exact published npm package includes the source, build material and upstream notices:

- Package source archive: https://registry.npmjs.org/lamejs/-/lamejs-1.2.1.tgz
- Project: https://github.com/zhuker/lamejs
- Version metadata: https://www.npmjs.com/package/lamejs/v/1.2.1

## Library replacement and rebuilding

The app loads these as separate files, not as statically linked parts of the original Swift executable. They are in:

`Hymn AIrranger.app/Contents/Resources/HymnAIrranger_HymnAIrranger.bundle/Web/Vendor/`

You may modify these libraries, replace them with compatible builds, and reverse-engineer the combined application to debug your modifications under the applicable license terms. No application EULA restricts those rights.

For a rebuild, obtain this application's source at the release tag and the upstream source archives above. Follow upstream build instructions to generate API-compatible replacements. Put the resulting JavaScript toolkit files in `Sources/HymnAIrranger/Resources/Web/Vendor/`. Regenerate that folder's `SHA256SUMS` with `shasum -a 256 verovio-toolkit-wasm.js lame.all.js > SHA256SUMS`, then run `Build App.command`. No private signing key is required: the build applies a local ad-hoc signature. Modifying an already signed app invalidates that signature, so rebuilding is the supported replacement route.

Copies of **LGPL-3.0.txt**, **GPL-3.0.txt**, and this notice are supplied in the Vendor folder, including inside each prebuilt app. MIT LICENSE.txt is also in Contents/Resources. The release page gives source access alongside the binary download. The upstream source downloads are served at no charge by the named upstream providers rather than copied into the app ZIP. If a source link becomes unavailable or a component's build information is incomplete, report it to the application repository so the corresponding-source access can be restored.

## Build provenance and limitations

Vendor/SHA256SUMS records the dependency bytes used; BUILD-INFO.txt records the application version, source commit, and toolchain. Fixed-version HTTPS URLs and first-download hash recording do not independently authenticate the publisher or prove reproducibility. No binary reproducibility, full license audit, or Apple notarization is claimed.

The demo melody, lyrics and synthesizer are original development material. FFmpeg was used only for early example MP3s in the initial source archive; no FFmpeg executable is shipped or used by the native app.
