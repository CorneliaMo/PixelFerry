# Troubleshooting

## Streamer is missing

Installed apps expect `PixelFerry Streamer.app` under `Contents/PlugIns`. Rebuild with `bash scripts/build-release.sh`. During development pass `--streamer-directory PixelFerryStreamer`.

## Startup health check times out

Confirm the selected port is free and run `npm run build` in `PixelFerryStreamer` when developing from source. Packaged and development launches write helper output to `~/Library/Logs/PixelFerry/streamer.log`. PixelFerry polls `http://127.0.0.1:<port>/healthz` for 12 seconds before cleaning up.

## Browser cannot connect

Use devices on the same LAN, allow incoming connections in the macOS firewall, and avoid guest Wi-Fi/client isolation. PixelFerry 0.1.0 has no STUN/TURN relay.

## Empty or frozen video

For the packaged app, grant Screen Recording permission to **PixelFerry Streamer**, quit PixelFerry completely, and launch it again. During source/CLI development macOS may list Electron or the terminal instead. Verify the virtual display appears in System Settings.

## App is damaged or cannot be opened

Development artifacts are ad-hoc signed, not notarized. Rebuild locally and verify with `codesign --verify --deep --strict dist/PixelFerry.app`. Production distribution requires Developer ID signing and notarization.
