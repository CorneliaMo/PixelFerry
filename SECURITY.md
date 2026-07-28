# Security Policy

## Supported version

PixelFerry 0.1.x is the currently supported development line.

## Network model

PixelFerry assumes a trusted LAN. Its HTTP viewer and Socket.IO signaling have no TLS, authentication, or authorization. WebRTC media is encrypted by the protocol, but signaling metadata and viewer assets are not. Never forward the PixelFerry port to the internet.

## Reporting

Report vulnerabilities privately to the repository owner rather than opening a public issue. Do not include credentials, private IP inventories, or captured screen content in a report.

Private-API compatibility failures and crashes are bugs, but are not automatically security vulnerabilities.
