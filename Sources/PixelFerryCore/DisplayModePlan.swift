import Foundation

struct DisplayModePlan: Equatable, Sendable {
    struct Mode: Equatable, Sendable {
        let logicalWidth: Int
        let logicalHeight: Int
        let pixelWidth: Int
        let pixelHeight: Int
    }

    let scale: Int
    let maximumPixelWidth: Int
    let maximumPixelHeight: Int
    let modes: [Mode]

    static func make(width: Int, height: Int, hiDPI: Bool) -> DisplayModePlan? {
        guard width > 0, height > 0 else { return nil }
        let scale = hiDPI ? 2 : 1
        let (pixelWidth, widthOverflow) = width.multipliedReportingOverflow(by: scale)
        let (pixelHeight, heightOverflow) = height.multipliedReportingOverflow(by: scale)
        guard !widthOverflow, !heightOverflow,
              pixelWidth <= Int(UInt32.max), pixelHeight <= Int(UInt32.max) else {
            return nil
        }

        // CGVirtualDisplaySettings applies HiDPI to the complete mode list. Mode
        // dimensions therefore describe framebuffer pixels; macOS exposes half
        // those dimensions as logical points when HiDPI is enabled.
        let requested = Mode(
            logicalWidth: width,
            logicalHeight: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        return DisplayModePlan(
            scale: scale,
            maximumPixelWidth: pixelWidth,
            maximumPixelHeight: pixelHeight,
            modes: [requested]
        )
    }
}
