import SwiftUI

/// Nút bấm chính (Call to Action) chuẩn Soft Pink Design System
public struct PrimaryButton: View {
    public let title: String
    public let icon: String?
    public let isLoading: Bool
    public let isEnabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            if isEnabled && !isLoading {
                action()
            }
        }) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(LocalizationManager.translate(title))
                    .font(AppTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isEnabled ? AppColors.primaryPink : AppColors.primaryPink.opacity(0.4))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

