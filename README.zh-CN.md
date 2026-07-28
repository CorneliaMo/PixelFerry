# PixelFerry

PixelFerry 在 macOS 上创建可配置的虚拟显示器，并通过低延迟 WebRTC 将画面传送到局域网浏览器。菜单栏应用是主要产品，`pixelferry` 命令行工具保留用于开发和自动化。

> PixelFerry 使用私有 `CGVirtualDisplay` API，目标系统为 macOS 15，不适合通过 Mac App Store 分发，并可能需要随 macOS 更新。

## 环境要求

- Apple Silicon 或 Intel Mac，macOS 15 或更高版本
- Xcode 16 或更高版本
- 源码构建需要 Node.js 22.12 或更高版本及 npm
- 屏幕录制权限
- 同一可信局域网中的现代浏览器

## 开发运行

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

在另一台设备上打开命令输出的地址。默认 streamer 使用 Electron/Chromium 捕获及 WebRTC；实验性的原生 ScreenCaptureKit/libwebrtc 后端可通过 `--backend native` 启用。

在 macOS 上构建 Universal 2 应用、内嵌 streamer、ad-hoc 签名及 ZIP：

```bash
bash scripts/build-release.sh
```

产物位于 `dist/PixelFerry.app`、`dist/PixelFerry-0.1.0-macOS-universal.zip` 和 `dist/build-manifest.txt`。CLI 仍可从 SwiftPM 开发构建中使用。
运行 `bash scripts/build-release.sh --help` 可查看测试、依赖、输出目录和签名选项。

## 安全边界

PixelFerry 仅适用于可信局域网。HTTP 和 Socket.IO 信令是明文且无身份验证的。WebRTC 会加密媒体，但任何能够访问监听端口的人都可以尝试连接。请勿将端口暴露到互联网或不可信 Wi-Fi。

更多信息请参阅英文 [README](README.md)、[构建说明](Documentation/BUILDING.md) 和 [故障排除](Documentation/TROUBLESHOOTING.md)。
