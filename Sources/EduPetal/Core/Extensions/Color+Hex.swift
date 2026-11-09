import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

public extension Color {
    /// Phân tích chuỗi Hex thành bộ 4 giá trị (r, g, b, a) trong khoảng [0.0, 1.0]
    private static func parseHexRGBA(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RGBA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return (
            r: CGFloat(r) / 255.0,
            g: CGFloat(g) / 255.0,
            b: CGFloat(b) / 255.0,
            a: CGFloat(a) / 255.0
        )
    }

    /// Khởi tạo Color từ chuỗi Hex (hỗ trợ định dạng `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`)
    init(hex: String) {
        let rgba = Self.parseHexRGBA(hex)
        self.init(
            .sRGB,
            red: Double(rgba.r),
            green: Double(rgba.g),
            blue: Double(rgba.b),
            opacity: Double(rgba.a)
        )
    }

    /// Khởi tạo Dynamic Color tự động thích ứng tức thì giữa Light Mode và Dark Mode
    static func dynamic(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        let lightRGBA = parseHexRGBA(light)
        let darkRGBA = parseHexRGBA(dark)
        let uiColor = UIColor { traitCollection in
            let rgba = (traitCollection.userInterfaceStyle == .dark) ? darkRGBA : lightRGBA
            return UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        }
        return Color(uiColor: uiColor)
        #elseif canImport(AppKit)
        let lightRGBA = parseHexRGBA(light)
        let darkRGBA = parseHexRGBA(dark)
        let nsColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgba = isDark ? darkRGBA : lightRGBA
            return NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        }
        return Color(nsColor: nsColor)
        #else
        return Color(hex: light)
        #endif
    }
}

