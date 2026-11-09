import SwiftUI

/// Hệ thống Semantic Color Tokens chuẩn phong cách "Soft Pink Education"
/// Hỗ trợ mượt mà cả Light Mode và Dark Mode.
public enum AppColors {
    // MARK: - Brand & Accent
    /// Hồng chủ đạo (Primary Pink): Nút CTA chính, tab được chọn, nhận diện thương hiệu
    public static let primaryPink = Color.dynamic(light: "#D9668A", dark: "#E88FA8")

    /// Chữ/icon đặt trên nền hồng đậm (nút CTA)
    public static let onPrimary = Color.dynamic(light: "#FFFFFF", dark: "#2A1820")

    /// Hồng thứ cấp (Secondary Pink): Nền thẻ highlight, badge mềm, thanh tiến trình
    public static let secondaryPink = Color.dynamic(light: "#F8DCE5", dark: "#3D2630")

    /// Hồng điểm nhấn (Accent Rose): Icon nổi bật, tiêu đề phụ, border nhấn
    public static let accentRose = Color.dynamic(light: "#A63D63", dark: "#E58BAA")

    // MARK: - Backgrounds & Surfaces
    /// Nền chính toàn ứng dụng (Background)
    public static let background = Color.dynamic(light: "#FFF6F9", dark: "#171215")

    /// Nền thẻ/bề mặt nội dung (Surface Card)
    public static let surfaceCard = Color.dynamic(light: "#FFFFFF", dark: "#251D21")

    /// Nền bề mặt phụ/ô nhập liệu (Surface Subtle)
    public static let surfaceSubtle = Color.dynamic(light: "#FBEDF2", dark: "#2F262B")

    /// Đường phân cách mềm (Divider / Border)
    public static let divider = Color.dynamic(light: "#EBD3DC", dark: "#41363C")

    // MARK: - Typography Colors
    /// Chữ chính (Primary Text): Tiêu đề, văn bản quan trọng nhất
    public static let primaryText = Color.dynamic(light: "#2B2025", dark: "#F7F0F3")

    /// Chữ phụ (Secondary Text): Phụ đề, mô tả ngắn, metadata
    public static let secondaryText = Color.dynamic(light: "#66565D", dark: "#BDAFB5")

    /// Chữ mờ / Placeholder (Tertiary Text)
    public static let tertiaryText = Color.dynamic(light: "#85757C", dark: "#9A8C92")

    // MARK: - Semantic Status Colors
    /// Thành công: Điểm danh có mặt, đã thu học phí, hoàn thành bài tập
    public static let success = Color.dynamic(light: "#0E8A67", dark: "#3CCB9F")
    public static let successBackground = Color.dynamic(light: "#EAF8F3", dark: "#143328")

    /// Cảnh báo: Chờ điểm danh, sắp đến hạn nộp, còn nợ học phí
    public static let warning = Color.dynamic(light: "#9A6700", dark: "#F0B429")
    public static let warningBackground = Color.dynamic(light: "#FEF7E6", dark: "#38290B")

    /// Lỗi / Cảnh báo nghiêm trọng: Điểm danh vắng, quá hạn nộp, hủy buổi dạy
    public static let error = Color.dynamic(light: "#C0392B", dark: "#F0716C")
    public static let errorBackground = Color.dynamic(light: "#FCEBEA", dark: "#3A1B1A")

    /// Thông tin bổ sung
    public static let info = Color.dynamic(light: "#2F6FBF", dark: "#6FAAF0")
    public static let infoBackground = Color.dynamic(light: "#EDF5FC", dark: "#182838")
}

