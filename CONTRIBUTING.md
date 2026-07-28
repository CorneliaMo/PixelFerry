# Contributing

Use macOS 15 and Xcode 16 or newer. Keep the Swift CLI operational, avoid copying AGPL Deskreen source, and treat the private CoreGraphics API boundary as isolated implementation detail.

Before proposing a change:

```bash
swift test
cd PixelFerryStreamer
npm run check
```

For packaging changes, also run `bash scripts/build-release.sh` and verify both architectures with `lipo -archs`. Do not commit `node_modules`, `.build`, `dist`, credentials, signing identities, or generated Electron output.

Changes should include focused tests, an entry in `CHANGELOG.md` when user-visible, and matching English/Chinese copy for user-facing product text.
