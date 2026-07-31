import Foundation

extension Bundle {
    static var pixelFerryCoreResources: Bundle {
        packagedResourceBundle(named: "PixelFerry_PixelFerryCore.bundle") ?? .module
    }

    private static func packagedResourceBundle(named name: String) -> Bundle? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true) else {
            return nil
        }
        return Bundle(url: url)
    }
}
