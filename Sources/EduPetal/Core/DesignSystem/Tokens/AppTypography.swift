import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Hệ thống Typography chuẩn iOS Native (Apple Human Interface Guidelines):
/// - Sử dụng `SF Pro Rounded` cho tiêu đề và con số giúp giao diện thân thiện, hiện đại, rõ nét.
/// - Sử dụng `SF Pro Text` / `SF Pro` mặc định của iOS cho nội dung, nhãn và danh sách giúp tối ưu độ đọc tiếng Việt và co giãn Dynamic Type.
public enum AppTypography {
    public static let customFontPostScriptName = ".AppleSystemUIFontRounded"
    public static let customFontFamilyName = "SF Pro Rounded"

    nonisolated(unsafe) private static var didConfigureAppearance = false

    /// Cấu hình phông chữ chuẩn iOS Native cho UINavigationBar, UITabBarItem và UISegmentedControl
    public static func registerCustomFontIfNeeded() {
        guard !didConfigureAppearance else { return }
        didConfigureAppearance = true

        #if canImport(UIKit)
        let baseLarge = UIFont.systemFont(ofSize: 32, weight: .bold)
        let navLargeFont = UIFont(
            descriptor: baseLarge.fontDescriptor.withDesign(.rounded) ?? baseLarge.fontDescriptor,
            size: 32
        )
        let baseInline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let navInlineFont = UIFont(
            descriptor: baseInline.fontDescriptor.withDesign(.rounded) ?? baseInline.fontDescriptor,
            size: 17
        )
        let tabNormalFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        let tabSelectedFont = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        let segmentNormalFont = UIFont.systemFont(ofSize: 13, weight: .medium)
        let segmentSelectedFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

        UINavigationBar.appearance().largeTitleTextAttributes = [.font: navLargeFont]
        UINavigationBar.appearance().titleTextAttributes = [.font: navInlineFont]
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabNormalFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabSelectedFont], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentNormalFont], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentSelectedFont], for: .selected)
        #endif
    }

    /// Tạo Font hệ thống iOS (`SF Pro` / `SF Pro Rounded`) theo kích thước và độ đậm chuẩn
    public static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        return .system(size: size, weight: weight, design: design)
    }

    /// 34pt: Tiêu đề màn hình chính (Dashboard, Screen Title lớn — SF Pro Rounded Bold)
    public static let largeTitle: Font = .system(.largeTitle, design: .rounded).weight(.bold)

    /// 28pt: Tiêu đề Section hoặc thẻ lớn (SF Pro Rounded Bold)
    public static let title1: Font = .system(.title, design: .rounded).weight(.bold)

    /// 22pt: Tiêu đề nhóm nội dung (SF Pro Rounded Bold)
    public static let title2: Font = .system(.title2, design: .rounded).weight(.bold)

    /// 20pt: Tiêu đề Card, Sheet Title (SF Pro Rounded Semibold)
    public static let title3: Font = .system(.title3, design: .rounded).weight(.semibold)

    /// 17pt: Tên học sinh, tên buổi học, nút chính (SF Pro Semibold)
    public static let headline: Font = .system(.headline, design: .default).weight(.semibold)

    /// 17pt: Đoạn văn bản mô tả, ghi chú chi tiết (SF Pro Regular)
    public static let body: Font = .system(.body, design: .default)

    /// 16pt: Nội dung form, danh sách (SF Pro Regular)
    public static let callout: Font = .system(.callout, design: .default)

    /// 15pt: Dòng phụ đề, thông tin phụ trong list item (SF Pro Regular)
    public static let subheadline: Font = .system(.subheadline, design: .default)

    /// 13pt: Timestamp, nhãn nhỏ (SF Pro Regular)
    public static let footnote: Font = .system(.footnote, design: .default)

    /// 12pt: Status Badge, tag môn học (SF Pro Medium)
    public static let caption1: Font = .system(.caption, design: .default).weight(.medium)

    /// 11pt: Chú thích nhỏ nhất (SF Pro Medium)
    public static let caption2: Font = .system(.caption2, design: .default).weight(.medium)

    // MARK: - Numeric Styles (Số tiền, Thời gian — SF Pro Rounded Monospaced Digits)
    /// Số tiền lớn trên Dashboard (28pt)
    public static let currencyLarge: Font = .system(size: 28, weight: .bold, design: .rounded).monospacedDigit()

    /// Số tiền trong danh sách (17pt)
    public static let currencyRegular: Font = .system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
}


