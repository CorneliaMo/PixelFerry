import CoreGraphics
import Darwin
import Foundation

@MainActor
public final class PixelFerryStreamCoordinator {
    private let display = VirtualDisplaySession()
    private var process: Process?
    private var logHandle: FileHandle?
    private var logURL: URL?

    public init() {}

    public func start(_ configuration: StreamConfiguration) async throws -> HealthSnapshot {
        let displayID = try await display.start(configuration: configuration)
        let width = Int(CGDisplayPixelsWide(displayID)); let height = Int(CGDisplayPixelsHigh(displayID))
        guard width > 0, height > 0 else { display.stop(); throw StreamError.captureCreationFailed }
        do {
            let child = Process()
            let launch = try resolveLaunch(configuration.streamerDevelopmentDirectory)
            child.executableURL = launch.executable
            child.arguments = launch.prefixArguments + [
                "--display-id", String(displayID), "--port", String(configuration.port),
                "--width", String(width), "--height", String(height),
                "--fps", String(configuration.fps), "--bitrate", String(configuration.bitrate),
            ]
            child.currentDirectoryURL = launch.workingDirectory
            let (logURL, logHandle) = try prepareLog()
            self.logURL = logURL
            self.logHandle = logHandle
            child.standardOutput = logHandle
            child.standardError = logHandle
            try child.run(); process = child
            try await waitUntilHealthy(port: configuration.port, child: child)
            return .init(displayID: displayID, width: width, height: height, fps: configuration.fps, viewerConnected: false)
        } catch { await stop(); throw error }
    }

    public func stop() async {
        if let process, process.isRunning {
            process.terminate()
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while process.isRunning, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
        display.stop()
    }

    private struct Launch {
        let executable: URL
        let prefixArguments: [String]
        let workingDirectory: URL?
    }

    private func resolveLaunch(_ developmentPath: String?) throws -> Launch {
        let files = FileManager.default
        if let developmentPath {
            let base = URL(
                fileURLWithPath: developmentPath,
                relativeTo: URL(fileURLWithPath: files.currentDirectoryPath)
            ).standardizedFileURL
            let manifest = base.appendingPathComponent("package.json")
            let electronCLI = base.appendingPathComponent("node_modules/electron/cli.js")
            let viewerBundle = base.appendingPathComponent("dist/viewer.js")
            guard files.fileExists(atPath: manifest.path) else {
                throw StreamError.streamerHelper("package.json was not found at \(manifest.path)")
            }
            guard files.isExecutableFile(atPath: electronCLI.path) || files.fileExists(atPath: electronCLI.path) else {
                throw StreamError.streamerHelper("Electron is missing. Run `npm install` in \(base.path).")
            }
            guard files.fileExists(atPath: viewerBundle.path) else {
                throw StreamError.streamerHelper("Web bundles are missing. Run `npm run build` in \(base.path).")
            }
            return Launch(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                prefixArguments: ["node", electronCLI.path, base.path],
                workingDirectory: base
            )
        }

        let helperName = "PixelFerry Streamer.app"
        let candidates = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(helperName),
            Bundle.main.sharedSupportURL?.appendingPathComponent(helperName),
            Bundle.main.resourceURL?.appendingPathComponent(helperName),
        ].compactMap { $0 }
        for appURL in candidates {
            let executable = appURL.appendingPathComponent("Contents/MacOS/PixelFerry Streamer")
            if files.isExecutableFile(atPath: executable.path) {
                return Launch(executable: executable, prefixArguments: [], workingDirectory: appURL.deletingLastPathComponent())
            }
        }
        throw StreamError.streamerHelper(
            "The embedded PixelFerry Streamer app is missing. Reinstall PixelFerry, or pass --streamer-directory <path> when developing from source."
        )
    }

    private func waitUntilHealthy(port: UInt16, child: Process) async throws {
        struct HelperHealth: Decodable { let hostReady: Bool }
        guard let url = URL(string: "http://127.0.0.1:\(port)/healthz") else {
            throw StreamError.streamerHelper("invalid health-check port \(port)")
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(12))
        var lastFailure = "no response"
        while clock.now < deadline {
            guard child.isRunning else {
                let status = child.terminationStatus
                process = nil
                throw StreamError.streamerHelper(
                    "helper exited during startup with status \(status); inspect \(logURL?.path ?? "the PixelFerry log")"
                )
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   (try? JSONDecoder().decode(HelperHealth.self, from: data).hostReady) == true {
                    return
                }
                lastFailure = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            } catch {
                lastFailure = error.localizedDescription
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw StreamError.streamerHelper(
            "helper did not become healthy at \(url.absoluteString) within 12 seconds (\(lastFailure)); verify the port is free and Screen Recording is allowed, then inspect \(logURL?.path ?? "the PixelFerry log")"
        )
    }

    private func prepareLog() throws -> (URL, FileHandle) {
        let files = FileManager.default
        guard let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw StreamError.streamerHelper("the user Library directory is unavailable")
        }
        let directory = library.appendingPathComponent("Logs/PixelFerry", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("streamer.log")
        if !files.fileExists(atPath: url.path) {
            guard files.createFile(atPath: url.path, contents: nil) else {
                throw StreamError.streamerHelper("could not create \(url.path)")
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        return (url, handle)
    }
}
