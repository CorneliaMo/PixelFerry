import Combine
import Foundation
import SwiftUI

struct AppSettings: Codable, Equatable {
    var name = "PixelFerry Display"
    var width = 1920
    var height = 1080
    var refreshRate = 60.0
    var hiDPI = false
    var fps = 60
    var bitrateMbps = 500
    var port = 8080
    var showCursor = true
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "cn.corneliamo.PixelFerry.settings.v1"
    private let legacyKey = "virtualDisplayStream.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else if let data = defaults.data(forKey: legacyKey),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
            if let encoded = try? JSONEncoder().encode(decoded) {
                defaults.set(encoded, forKey: key)
                defaults.removeObject(forKey: legacyKey)
            }
        } else {
            value = AppSettings()
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.value[keyPath: keyPath] },
            set: { self.value[keyPath: keyPath] = $0 }
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
