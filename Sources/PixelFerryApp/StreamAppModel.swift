import AppKit
import Combine
import Foundation
import PixelFerryCore

@MainActor
final class StreamAppModel: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case failed(String)

        var label: String {
            switch self {
            case .stopped: String(localized: "state.stopped", bundle: .module)
            case .starting: String(localized: "state.starting", bundle: .module)
            case .running: String(localized: "state.running", bundle: .module)
            case .stopping: String(localized: "state.stopping", bundle: .module)
            case .failed: String(localized: "state.error", bundle: .module)
            }
        }
    }

    struct HelperHealth: Decodable {
        var backend: String
        var displayID: UInt32
        var width: Int
        var height: Int
        var fps: Int
        var viewerConnected: Bool
        var hostReady: Bool
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var health: HelperHealth?
    @Published private(set) var healthReachable = false
    @Published private(set) var viewerURLs: [URL] = []

    private var coordinator: StreamCoordinator?
    private var healthTask: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var errorMessage: String? {
        if case .failed(let message) = state { message } else { nil }
    }

    func start(settings: AppSettings) async {
        guard state == .stopped || errorMessage != nil else { return }
        do {
            let configuration = try configuration(from: settings)
            state = .starting
            let coordinator = StreamCoordinator()
            let initial = try await coordinator.start(configuration)
            self.coordinator = coordinator
            health = HelperHealth(
                backend: configuration.backend.rawValue,
                displayID: initial.displayID,
                width: initial.width,
                height: initial.height,
                fps: initial.fps,
                viewerConnected: false,
                hostReady: false
            )
            viewerURLs = NetworkAddresses.localIPv4().compactMap {
                URL(string: "http://\($0):\(configuration.port)/")
            }
            state = .running
            healthReachable = false
            beginHealthPolling(port: configuration.port)
        } catch {
            coordinator = nil
            state = .failed(localizedMessage(for: error))
        }
    }

    func stop() async {
        guard coordinator != nil else {
            state = .stopped
            return
        }
        state = .stopping
        healthTask?.cancel()
        healthTask = nil
        await coordinator?.stop()
        coordinator = nil
        health = nil
        healthReachable = false
        viewerURLs = []
        state = .stopped
    }

    func openScreenRecordingSettings() {
        let value = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }

    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func configuration(from settings: AppSettings) throws -> StreamConfiguration {
        guard settings.width > 0, settings.width <= Int(UInt32.max), settings.width.isMultiple(of: 2),
              settings.height > 0, settings.height <= Int(UInt32.max), settings.height.isMultiple(of: 2) else {
            throw ValidationError(String(localized: "validation.dimensions", bundle: .module))
        }
        guard (1...240).contains(settings.fps) else {
            throw ValidationError(String(localized: "validation.fps", bundle: .module))
        }
        guard (1...65_535).contains(settings.port) else {
            throw ValidationError(String(localized: "validation.port", bundle: .module))
        }
        guard (1...1_000).contains(settings.bitrateMbps) else {
            throw ValidationError(String(localized: "validation.bitrate", bundle: .module))
        }
        guard settings.refreshRate.isFinite, settings.refreshRate > 0 else {
            throw ValidationError(String(localized: "validation.refresh_rate", bundle: .module))
        }
        guard !settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError(String(localized: "validation.name", bundle: .module))
        }
        var value = StreamConfiguration()
        value.name = settings.name
        value.width = settings.width
        value.height = settings.height
        value.refreshRate = settings.refreshRate
        value.hiDPI = settings.hiDPI
        value.fps = settings.fps
        value.bitrate = settings.bitrateMbps * 1_000_000
        value.port = UInt16(settings.port)
        value.showCursor = settings.showCursor
        value.backend = .streamer
        value.streamerDevelopmentDirectory = ProcessInfo.processInfo.environment["PIXELFERRY_STREAMER_DIRECTORY"]
        return value
    }

    private func beginHealthPolling(port: UInt16) {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHealth(port: port)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshHealth(port: UInt16) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/healthz") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                healthReachable = false
                return
            }
            health = try JSONDecoder().decode(HelperHealth.self, from: data)
            healthReachable = true
        } catch {
            healthReachable = false
        }
    }

    private func localizedMessage(for error: Error) -> String {
        guard let error = error as? StreamError else { return error.localizedDescription }
        let key: String.LocalizationValue
        let detail: String?
        switch error {
        case .privateAPIUnavailable(let value): key = "error.private_api"; detail = value
        case .displayCreationFailed: key = "error.display_creation"; detail = nil
        case .displaySettingsFailed: key = "error.display_settings"; detail = nil
        case .displayRegistrationTimedOut: key = "error.display_timeout"; detail = nil
        case .screenCapturePermissionDenied: key = "error.screen_capture"; detail = nil
        case .captureCreationFailed: key = "error.capture_creation"; detail = nil
        case .captureStopped(let value): key = "error.capture_stopped"; detail = value
        case .webRTC(let value): key = "error.webrtc"; detail = value
        case .listener(let value): key = "error.listener"; detail = value
        case .signaling(let value): key = "error.signaling"; detail = value
        case .streamerHelper(let value): key = "error.streamer"; detail = value
        }
        let format = String(localized: key, bundle: .module)
        return detail.map { String(format: format, locale: .current, $0) } ?? format
    }
}

private struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
