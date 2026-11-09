import Foundation
import CoreGraphics

/// Hệ thống Spacing Scale chuẩn cho EduPetal
public enum AppSpacing {
    /// 4pt - Khoảng cách siêu nhỏ (giữa icon và nhãn nhỏ)
    public static let xxs: CGFloat = 4

    /// 8pt - Khoảng cách nhỏ (padding nội bộ của badge, khoảng cách giữa các dòng phụ)
    public static let xs: CGFloat = 8

    /// 12pt - Khoảng cách vừa nhỏ (khoảng cách giữa các ô input, card compact)
    public static let sm: CGFloat = 12

    /// 16pt - Khoảng cách tiêu chuẩn (padding viền màn hình, margin giữa các card)
    public static let md: CGFloat = 16

    /// 20pt - Khoảng cách mở rộng
    public static let lg: CGFloat = 20

    /// 24pt - Khoảng cách phân đoạn lớn
    public static let xl: CGFloat = 24

    /// 32pt - Khoảng cách giữa các section lớn
    public static let xxl: CGFloat = 32

    /// 48pt - Khoảng cách đỉnh trang hoặc chân modal
    public static let xxxl: CGFloat = 48
}

