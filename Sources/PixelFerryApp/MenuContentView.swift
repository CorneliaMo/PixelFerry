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
                HStack(spacing: 7) {
                    Image(systemName: "display.and.arrow.down").frame(width: 18, height: 18)
                    Text("app.name", bundle: .pixelFerryAppResources).font(.headline)
                }
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
            TextField(l("field.display_name"), text: settings.binding(\.name))
            HStack {
                numberField(l("field.width"), value: settings.binding(\.width))
                Text("×").foregroundStyle(.secondary)
                numberField(l("field.height"), value: settings.binding(\.height))
            }
            HStack {
                numberField(l("field.display_hz"), value: settings.binding(\.refreshRate))
                numberField(l("field.stream_fps"), value: settings.binding(\.fps))
            }
            HStack {
                numberField(l("field.bitrate_mbps"), value: settings.binding(\.bitrateMbps))
                numberField(l("field.port"), value: settings.binding(\.port))
            }
            HStack {
                Toggle(l("field.hidpi"), isOn: settings.binding(\.hiDPI))
                Toggle(l("field.show_cursor"), isOn: settings.binding(\.showCursor))
            }
            Button {
                Task { await model.start(settings: settings.value) }
            } label: {
                Label(String(localized: "action.start", bundle: .pixelFerryAppResources), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state == .starting || model.state == .stopping)
            Text("warning.trusted_lan", bundle: .pixelFerryAppResources)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                metric(l("metric.display"), model.health.map { "\($0.width)×\($0.height) @ \($0.fps)" } ?? "—")
                Spacer()
                metric(l("metric.viewer"), model.health?.viewerConnected == true ? l("status.connected") : l("status.waiting"))
                Spacer()
                metric(l("metric.host"), hostStatus)
            }
            if let url = model.viewerURLs.first {
                HStack(alignment: .center, spacing: 14) {
                    QRCodeView(value: url.absoluteString)
                        .frame(width: 112, height: 112)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("viewer.open", bundle: .pixelFerryAppResources).font(.caption).foregroundStyle(.secondary)
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button(String(localized: "action.copy", bundle: .pixelFerryAppResources)) { model.copy(url) }
                    }
                }
            } else {
                Label(l("error.no_lan_address"), systemImage: "network.slash")
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
                Label(String(localized: "action.stop", bundle: .pixelFerryAppResources), systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(l("permission.title"), systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.subheadline.weight(.medium))
            Text(l("permission.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(l("permission.open_settings")) { model.openScreenRecordingSettings() }
                .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Text(l("settings.autosave"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(l("action.quit")) {
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
        guard model.healthReachable else { return l("status.unavailable") }
        return model.health?.hostReady == true ? l("status.ready") : l("status.starting")
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

    private func l(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .pixelFerryAppResources)
    }
}
