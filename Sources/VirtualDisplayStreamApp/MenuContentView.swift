import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: StreamAppModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if model.isRunning {
                runningContent
            } else {
                configurationContent
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            permissionContent
            footer
        }
        .padding(16)
        .frame(width: 430)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Virtual Display Stream").font(.headline)
                Text(model.state.label).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            if model.state == .starting || model.state == .stopping {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(statusColor).frame(width: 8, height: 8)
            }
        }
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Display name", text: settings.binding(\.name))
            HStack {
                numberField("Width", value: settings.binding(\.width))
                Text("×").foregroundStyle(.secondary)
                numberField("Height", value: settings.binding(\.height))
            }
            HStack {
                numberField("Display Hz", value: settings.binding(\.refreshRate))
                numberField("Stream FPS", value: settings.binding(\.fps))
            }
            HStack {
                numberField("Bitrate Mbps", value: settings.binding(\.bitrateMbps))
                numberField("Port", value: settings.binding(\.port))
            }
            HStack {
                Toggle("HiDPI", isOn: settings.binding(\.hiDPI))
                Toggle("Show cursor", isOn: settings.binding(\.showCursor))
            }
            Text("Advanced").font(.caption).foregroundStyle(.secondary)
            TextField("Chromium helper directory", text: settings.binding(\.chromiumDirectory))
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await model.start(settings: settings.value) }
            } label: {
                Label("Start Streaming", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state == .starting || model.state == .stopping)
        }
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                metric("DISPLAY", model.health.map { "\($0.width)×\($0.height) @ \($0.fps)" } ?? "—")
                Spacer()
                metric("VIEWER", model.health?.viewerConnected == true ? "Connected" : "Waiting")
                Spacer()
                metric("HOST", hostStatus)
            }
            if let url = model.viewerURLs.first {
                HStack(alignment: .center, spacing: 14) {
                    QRCodeView(value: url.absoluteString)
                        .frame(width: 112, height: 112)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open on another device").font(.caption).foregroundStyle(.secondary)
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy Address") { model.copy(url) }
                    }
                }
            } else {
                Label("No active LAN IPv4 address was found.", systemImage: "network.slash")
                    .font(.caption)
            }
            if model.viewerURLs.count > 1 {
                ForEach(model.viewerURLs.dropFirst(), id: \.self) { url in
                    Button(url.absoluteString) { model.copy(url) }
                        .buttonStyle(.plain)
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            Button(role: .destructive) {
                Task { await model.stop() }
            } label: {
                Label("Stop Streaming", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Screen Recording Permission", systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.subheadline.weight(.medium))
            Text("The Electron helper performs capture. If video is blank, allow Electron in Privacy & Security, then restart streaming.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Screen Recording Settings") { model.openScreenRecordingSettings() }
                .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Text("Settings are saved automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var hostStatus: String {
        guard model.healthReachable else { return "Unavailable" }
        return model.health?.hostReady == true ? "Ready" : "Starting"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
    }
}
