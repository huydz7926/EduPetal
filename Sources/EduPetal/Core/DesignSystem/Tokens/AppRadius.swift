import Foundation
import CoreGraphics

/// Quy chuẩn bo góc (Corner Radii) tạo sự mềm mại, thân thiện
public enum AppRadius {
    /// 4pt - Góc siêu nhỏ
    public static let xs: CGFloat = 4

    /// 8pt - Tag, Badge, Small indicator
    public static let sm: CGFloat = 8

    /// 12pt - Button tiêu chuẩn, Input text field
    public static let md: CGFloat = 12

    /// 16pt - Card tiêu chuẩn, Dialog modal
    public static let lg: CGFloat = 16

    /// 24pt - Bottom sheet, Modal container
    public static let xl: CGFloat = 24

    /// 999pt - Bo tròn hoàn toàn (Capsule / Pill Badge)
    public static let full: CGFloat = 999
}

