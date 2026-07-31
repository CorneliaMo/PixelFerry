// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelFerry",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PixelFerryCore", targets: ["PixelFerryCore"]),
        .executable(name: "pixelferry", targets: ["PixelFerryCLI"]),
        // Keep this SwiftPM product name distinct from `pixelferry` on the
        // default case-insensitive macOS filesystem. The release script still
        // packages the resulting executable as PixelFerry.app/…/PixelFerry.
        .executable(name: "PixelFerryApp", targets: ["PixelFerryApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "150.0.0"),
        .package(
            url: "https://github.com/httpswift/swifter.git",
            revision: "1e4f51c92d7ca486242d8bf0722b99de2c3531aa"
        ),
    ],
    targets: [
        .target(name: "CVirtualDisplayPrivate", publicHeadersPath: "include"),
        .target(
            name: "PixelFerryCore",
            dependencies: [
                "CVirtualDisplayPrivate",
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "Swifter", package: "swifter"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(name: "PixelFerryCLI", dependencies: ["PixelFerryCore"]),
        .executableTarget(
            name: "PixelFerryApp",
            dependencies: ["PixelFerryCore"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"), .linkedFramework("SwiftUI"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(name: "PixelFerryCoreTests", dependencies: ["PixelFerryCore"]),
    ]
)
