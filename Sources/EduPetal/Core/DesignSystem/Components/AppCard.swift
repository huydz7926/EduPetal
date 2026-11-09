import SwiftUI

/// Thẻ nội dung chuẩn (AppCard) với bo góc mềm mại và đổ bóng tự nhiên
public struct AppCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let content: Content

    public init(
        cornerRadius: CGFloat = AppRadius.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.6), lineWidth: 0.8)
            )
            .appCardShadow()
    }
}

