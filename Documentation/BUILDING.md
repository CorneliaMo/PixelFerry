# Building and packaging

Install Xcode 16+, Node.js 22, and npm. Build the streamer first:

The active developer directory must point at the full Xcode installation rather than Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

```bash
cd PixelFerryStreamer
npm ci
npm run check
npm run package:mac
```

`npm run package:mac` creates arm64 and x64 Electron apps and merges them into `PixelFerryStreamer/out/universal/PixelFerry Streamer.app`.

For a complete release:

```bash
bash scripts/build-release.sh
```

The script builds Swift twice, merges the application executable with `lipo`, embeds the helper, WebRTC framework, and SwiftPM resource bundles, generates `PixelFerry.icns` from `Branding/PixelFerryIcon-master.png`, adds product metadata, ad-hoc signs nested code and the app, validates architectures, rpaths, resources, and signatures, then creates a ZIP. The `pixelferry` CLI remains a development product built by SwiftPM rather than a standalone release artifact.

The master icon is source artwork and is never modified. Release signing/notarization may replace the final ad-hoc signing step, but identifiers must remain `cn.corneliamo.PixelFerry` and `cn.corneliamo.PixelFerry.Streamer`.

To run the menu-bar app directly from SwiftPM during development, set
`PIXELFERRY_STREAMER_DIRECTORY` to the absolute `PixelFerryStreamer` path.
