# Architecture

PixelFerry has three runtime layers:

1. `PixelFerryApp` is the menu-bar product. It validates settings, starts and stops a stream, polls health, and presents viewer URLs.
2. `PixelFerryCore` owns the private `CGVirtualDisplay` lifecycle. The default `PixelFerryStreamCoordinator` launches the embedded helper; the experimental native coordinator uses ScreenCaptureKit and libwebrtc directly.
3. `PixelFerry Streamer` is a headless Electron app. Chromium captures the selected virtual display, a hidden renderer creates the WebRTC sender, and Express/Socket.IO serves and signals one browser viewer.

The packaged app embeds the helper at `Contents/PlugIns/PixelFerry Streamer.app`. Development builds may explicitly pass `--streamer-directory PixelFerryStreamer`, which launches Electron's supported CLI entry point from that source tree.

Startup is transactional: create display, launch helper, poll `/healthz` for at most 12 seconds, then publish URLs. Any failure terminates the helper and releases the display. Shutdown reverses that order.

No authentication, persistence server, audio, remote input, STUN, or TURN is included in 0.1.0.
