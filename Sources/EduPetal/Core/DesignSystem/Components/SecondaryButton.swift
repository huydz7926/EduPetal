import SwiftUI

/// Nút bấm phụ (Secondary / Outline / Subtle CTA)
public struct SecondaryButton: View {
    public let title: String
    public let icon: String?
    public let isDestructive: Bool
    public let isEnabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            if isEnabled {
                action()
            }
        }) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                }
                Text(LocalizationManager.translate(title))
                    .font(AppTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isDestructive ? AppColors.errorBackground : AppColors.secondaryPink)
            )
            .foregroundColor(isDestructive ? AppColors.error : AppColors.accentRose)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isDestructive ? AppColors.error.opacity(0.3) : AppColors.primaryPink.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

