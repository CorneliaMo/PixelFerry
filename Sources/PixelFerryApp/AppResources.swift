import Foundation

extension Bundle {
    static var pixelFerryAppResources: Bundle {
        packagedResourceBundle(named: "PixelFerry_PixelFerryApp.bundle") ?? .module
    }

    private static func packagedResourceBundle(named name: String) -> Bundle? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true) else {
            return nil
        }
        return Bundle(url: url)
    }
}
