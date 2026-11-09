import SwiftUI

/// Màn hình trạng thái rỗng (EmptyStateView) thân thiện, tinh tế
public struct EmptyStateView: View {
    public let icon: String
    public let title: String
    public let message: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        icon: String = "tray.fill",
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryPink.opacity(0.7))
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(AppColors.accentRose)
            }
            .padding(.bottom, 4)

            Text(LocalizationManager.translate(title))
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizationManager.translate(message))
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.sm)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(LocalizationManager.translate(actionTitle))
                    }
                    .font(AppTypography.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.primaryPink)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.sm)
        .frame(maxWidth: .infinity)
    }
}

