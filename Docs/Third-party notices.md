# Third-party components and distribution follow-up

This source archive contains original application code and license texts. The upstream runtime JavaScript/WASM assets are **not included**; the build script fetches pinned versions on the build Mac. No font files or commercial sound samples are included.

## Verovio 6.2.0

Purpose: local music engraving from generated MEI to SVG. Verovio is licensed under LGPL v3; upstream retains its copyright notices and component licenses. Consult the source and exact release for all terms, embedded dependencies, and engraving-resource notices.

- Project/source: https://github.com/rism-digital/verovio
- Release index (select the exact 6.2.0 source): https://github.com/rism-digital/verovio/releases
- Release documentation: https://book.verovio.org/installing-or-building-from-sources/javascript-and-webassembly.html
- Runtime download: https://www.verovio.org/javascript/6.2.0/verovio-toolkit-wasm.js

The source release reference must be verified against the exact upstream release before any binary redistribution. It is a reference, not a complete corresponding-source distribution or written source offer.

## lamejs 1.2.1

Purpose: local MP3 encoding through JavaScriptCore. Package metadata identifies the license as LGPL-3.0. The encoder derives from the LAME project; preserve upstream headers and notices.

- Project/source: https://github.com/zhuker/lamejs
- Package source: https://www.npmjs.com/package/lamejs/v/1.2.1
- Runtime download: https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.all.js

## Included license texts

`LGPL-3.0.txt` and `GPL-3.0.txt` provide the relevant GNU license texts. The build copies them and this notice into the application resources. The original app source is under the separate MIT license at the project root. Apple system frameworks remain governed by Apple's terms and are not redistributed as framework binaries here.

The original-study MP3s in the downloadable source archive were encoded by a development-environment FFmpeg installation. FFmpeg binaries are not distributed and are not dependencies of the native app. No external sound set was used.

## Before distributing app binaries

This is not a completed license-compliance audit. Review the exact fetched artifacts, their original copyright notices and embedded component notices; provide corresponding source and required build/replacement information; retain the applicable license texts; and ensure all license obligations are met for the intended form of distribution. Merely including links should not be assumed sufficient.

Pinned HTTPS URLs and first-download local hash recording do not independently authenticate the publisher's artifact. A production release needs reviewed, reproducible dependency artifacts and an appropriate supply-chain process.
