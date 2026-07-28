import AppKit
import SwiftUI

@main
struct PixelFerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = StreamAppModel()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model, settings: settings)
                .onAppear {
                    appDelegate.prepareForTermination = {
                        await model.stop()
                    }
                }
        } label: {
            Label("PixelFerry", systemImage: model.isRunning ? "display.and.arrow.down" : "display")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var prepareForTermination: (@MainActor () async -> Void)?
    private var terminationPrepared = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPrepared, let prepareForTermination else { return .terminateNow }
        terminationPrepared = true
        Task { @MainActor in
            await prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
