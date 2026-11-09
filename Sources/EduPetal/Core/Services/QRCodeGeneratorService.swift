import Foundation
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// Dịch vụ tạo mã QR trực tiếp trên thiết bị (On-Device CoreImage QR Generator)
/// Hoạt động 100% offline, không phụ thuộc mạng
public final class QRCodeGeneratorService: @unchecked Sendable {
    public static let shared = QRCodeGeneratorService()

    private let filterContext = CIContext()

    public init() {}

    #if canImport(UIKit)
    /// Tạo UIImage mã QR từ chuỗi văn bản với độ sắc nét cao (scale up chống vỡ pixel)
    public func generateQRCode(from string: String, size: CGFloat = 280) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // M = 15% error correction

        guard let outputImage = filter.outputImage else { return nil }

        // Scale lên kích thước mong muốn để QR nét căng, không bị nhòe pixel
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = filterContext.createCGImage(transformedImage, from: transformedImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
    #endif
}

