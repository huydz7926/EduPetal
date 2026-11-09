import SwiftUI

/// Hệ thống đổ bóng mềm mại (Soft Shadow Tokens) chuẩn iOS Native
public enum AppShadows {
    /// Bóng siêu nhẹ dành cho card phẳng
    public static func subtle<T: View>(_ content: T) -> some View {
        content.shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    /// Bóng tiêu chuẩn cho Card nội dung
    public static func card<T: View>(_ content: T) -> some View {
        content.shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }

    /// Bóng nổi bật cho Floating Action Button hoặc Quick Action Sheet
    public static func floating<T: View>(_ content: T) -> some View {
        content.shadow(color: AppColors.primaryPink.opacity(0.25), radius: 14, x: 0, y: 6)
    }
}

public extension View {
    func appSubtleShadow() -> some View {
        AppShadows.subtle(self)
    }

    func appCardShadow() -> some View {
        AppShadows.card(self)
    }

    func appFloatingShadow() -> some View {
        AppShadows.floating(self)
    }
}

