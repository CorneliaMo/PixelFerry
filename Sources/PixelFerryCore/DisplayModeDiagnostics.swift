import AppKit
import CoreGraphics
import Darwin
import OSLog

enum DisplayModeDiagnostics {
    private static let logger = Logger(
        subsystem: "cn.corneliamo.PixelFerry",
        category: "DisplayMode"
    )

    @MainActor
    static func record(displayID: CGDirectDisplayID, requestedPlan: DisplayModePlan) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        let active = CGDisplayCopyDisplayMode(displayID)
        let available = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] ?? []
        let logicalSize = screen?.frame.size ?? .zero
        let backingScale = screen?.backingScaleFactor ?? 0

        var lines = [
            "PixelFerry display-mode diagnostics",
            "displayID=\(displayID)",
            "requestedLogical=\(requestedPlan.modes[0].logicalWidth)x\(requestedPlan.modes[0].logicalHeight)",
            "requestedScale=\(requestedPlan.scale)x",
            "descriptorMaximumPixels=\(requestedPlan.maximumPixelWidth)x\(requestedPlan.maximumPixelHeight)",
            "screenLogical=\(dimension(logicalSize.width))x\(dimension(logicalSize.height))",
            "screenBackingScale=\(backingScale)",
            "cgDisplayPixels=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))",
            "activeMode=\(describe(active))",
            "availableModes(\(available.count)):",
        ]
        lines.append(contentsOf: available.enumerated().map { "  [\($0.offset)] \(describe($0.element))" })
        let report = lines.joined(separator: "\n")
        logger.info("\(report, privacy: .public)")
        fputs("\(report)\n", stderr)
        persist(report)
    }

    private static func describe(_ mode: CGDisplayMode?) -> String {
        guard let mode else { return "unavailable" }
        return "logical=\(mode.width)x\(mode.height) pixels=\(mode.pixelWidth)x\(mode.pixelHeight) refresh=\(mode.refreshRate)"
    }

    private static func dimension(_ value: CGFloat) -> Int {
        Int(value.rounded())
    }

    private static func persist(_ report: String) {
        do {
            let files = FileManager.default
            guard let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
            let directory = library.appendingPathComponent("Logs/PixelFerry", isDirectory: true)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("display-mode.log")
            try Data("\(report)\n".utf8).write(to: url, options: .atomic)
            logger.info("Display-mode report written to \(url.path, privacy: .public)")
        } catch {
            logger.error("Could not persist display-mode report: \(error.localizedDescription, privacy: .public)")
        }
    }
}
