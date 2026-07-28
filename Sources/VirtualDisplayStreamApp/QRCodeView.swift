import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let value: String
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code for \(value)")
        } else {
            Image(systemName: "qrcode")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var image: NSImage? {
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: .init(width: cgImage.width, height: cgImage.height))
    }
}
