# Building and packaging

Install Xcode 16+, Node.js 22.12 or newer, and npm. Build the streamer first:

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

For a complete local release:

```bash
bash scripts/build-release.sh
```

The script performs environment checks, installs the locked npm dependency tree,
runs the Node and Swift test suites, packages the Universal 2 Electron helper,
builds Swift for arm64 and x86_64, embeds frameworks and resource bundles,
generates the application icon and bilingual permission descriptions, signs code
from the inside out, validates bundle identifiers, architectures, rpaths,
resources and signatures, then creates a ZIP and build manifest.

Useful options:

```bash
# Reuse an existing node_modules directory
bash scripts/build-release.sh --skip-npm-ci

# Faster packaging iteration
bash scripts/build-release.sh --skip-tests --skip-npm-ci

# Write artifacts elsewhere
bash scripts/build-release.sh --output /path/to/artifacts

# Use an installed signing identity (notarization is still a separate step)
bash scripts/build-release.sh --sign-identity "Developer ID Application: Example"
```

Run `bash scripts/build-release.sh --help` for the complete interface. The
`pixelferry` CLI remains a development product built by SwiftPM rather than a
standalone release artifact.

The master icon is source artwork and is never modified. Release signing/notarization may replace the final ad-hoc signing step, but identifiers must remain `cn.corneliamo.PixelFerry` and `cn.corneliamo.PixelFerry.Streamer`.

To run the menu-bar app directly from SwiftPM during development, set
`PIXELFERRY_STREAMER_DIRECTORY` to the absolute `PixelFerryStreamer` path.
