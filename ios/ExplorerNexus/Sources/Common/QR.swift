import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QR {
    /// A crisp QR code image (nil when the text is too long for one code).
    static func image(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "L"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
