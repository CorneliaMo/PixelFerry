# PixelFerry

PixelFerry creates a configurable virtual display on macOS and ferries its pixels to a browser on the local network with low-latency WebRTC. The menu-bar app is the primary product; the `pixelferry` command remains available for development and automation.

> PixelFerry uses private `CGVirtualDisplay` APIs. It targets macOS 15, is distributed outside the Mac App Store, and may require updates when macOS changes.

## Requirements

- macOS 15 or newer on Apple silicon or Intel
- Xcode 16 or newer
- Node.js 22 and npm for source builds
- Screen Recording permission
- A modern browser on the same trusted LAN

## Development

```bash
cd PixelFerryStreamer
npm ci
npm run build
npm test
cd ..

swift build
swift test
swift run pixelferry --streamer-directory PixelFerryStreamer
```

Open the URL printed by the command on another device. The default streamer uses Electron/Chromium capture and WebRTC. `--backend native` keeps the experimental ScreenCaptureKit/libwebrtc implementation available.

Build the complete Universal 2 app, embedded streamer, ad-hoc signature, and ZIP on macOS:

```bash
bash scripts/build-release.sh
```

Artifacts are written to `dist/PixelFerry.app` and `dist/PixelFerry-0.1.0-macOS-universal.zip`. The CLI remains available from SwiftPM development builds.

## Security boundary

PixelFerry is for trusted local networks only. HTTP and Socket.IO signaling are plaintext and unauthenticated. WebRTC encrypts media in transit, but anyone who can reach the listener can attempt to connect. Do not expose the port to the internet or an untrusted Wi-Fi network.

## Documentation

- [Architecture](Documentation/ARCHITECTURE.md)
- [Building and packaging](Documentation/BUILDING.md)
- [Troubleshooting](Documentation/TROUBLESHOOTING.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Chinese README / 中文说明](README.zh-CN.md)
- [Historical implementation research](docs/IMPLEMENTATION_RESEARCH.md)

## License

PixelFerry is MIT licensed. DeskPad and VirtualDisplayKit informed the private API declarations and lifecycle; Deskreen was consulted only as historical architectural research. See [NOTICE](NOTICE).
