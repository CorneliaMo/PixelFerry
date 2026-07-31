import AppKit
import CoreGraphics
import CVirtualDisplayPrivate

@MainActor
public final class VirtualDisplaySession {
    private var display: CGVirtualDisplay?
    public private(set) var wasTerminated = false

    public init() {}

    public func start(configuration: StreamConfiguration) async throws -> CGDirectDisplayID {
        guard display == nil else { return display!.displayID }
        try verifyPrivateAPI()
        guard let modePlan = DisplayModePlan.make(
            width: configuration.width,
            height: configuration.height,
            hiDPI: configuration.hiDPI
        ) else {
            throw StreamError.displaySettingsFailed
        }
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = configuration.name
        descriptor.maxPixelsWide = UInt32(modePlan.maximumPixelWidth)
        descriptor.maxPixelsHigh = UInt32(modePlan.maximumPixelHeight)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        // Version the identity when mode semantics change so macOS does not
        // restore the old one-pixel-per-point mode cached for serial 1.
        descriptor.vendorID = 0x3456; descriptor.productID = 0x1234; descriptor.serialNum = 2
        descriptor.terminationHandler = { [weak self] _, _ in
            Task { @MainActor in self?.wasTerminated = true; self?.display = nil }
        }
        let created = CGVirtualDisplay(descriptor: descriptor)
        guard created.displayID != 0 else { throw StreamError.displayCreationFailed }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = configuration.hiDPI ? 1 : 0
        settings.modes = modePlan.modes.map {
            CGVirtualDisplayMode(
                width: UInt($0.pixelWidth),
                height: UInt($0.pixelHeight),
                refreshRate: configuration.refreshRate
            )
        }
        guard created.apply(settings) else { throw StreamError.displaySettingsFailed }
        display = created
        let id = created.displayID
        let deadline = ContinuousClock.now + .seconds(5)
        while NSScreen.screens.allSatisfy({
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value != id
        }) {
            if ContinuousClock.now >= deadline { stop(); throw StreamError.displayRegistrationTimedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        DisplayModeDiagnostics.record(displayID: id, requestedPlan: modePlan)
        return id
    }

    public func stop() { display = nil }

    private func verifyPrivateAPI() throws {
        let names = ["CGVirtualDisplayDescriptor", "CGVirtualDisplay", "CGVirtualDisplaySettings", "CGVirtualDisplayMode"]
        for name in names where NSClassFromString(name) == nil { throw StreamError.privateAPIUnavailable(name) }
        guard CGVirtualDisplay.instancesRespond(to: NSSelectorFromString("initWithDescriptor:")),
              CGVirtualDisplay.instancesRespond(to: NSSelectorFromString("applySettings:")),
              CGVirtualDisplayDescriptor.instancesRespond(to: NSSelectorFromString("setDispatchQueue:")),
              CGVirtualDisplayMode.instancesRespond(to: NSSelectorFromString("initWithWidth:height:refreshRate:")) else {
            throw StreamError.privateAPIUnavailable("required selector")
        }
    }
}
