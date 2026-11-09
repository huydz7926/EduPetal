import SwiftUI

/// Ô nhập tiền tệ (VND) tự động phân cách hàng nghìn và liên kết trực tiếp với kiểu `Int64`
public struct CurrencyTextField: View {
    public let title: String
    public let placeholder: String
    @Binding public var value: Int64

    @State private var text: String = ""

    public init(
        _ title: String = "Số tiền",
        placeholder: String = "0",
        value: Binding<Int64>
    ) {
        self.title = title
        self.placeholder = placeholder
        self._value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.secondaryText)

            HStack(spacing: AppSpacing.xs) {
                TextField(placeholder, text: $text)
                    .font(AppTypography.currencyRegular)
                    .foregroundColor(AppColors.primaryText)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: text) { _, newText in
                        let parsed = Int64.parseVND(from: newText)
                        if parsed != value {
                            value = parsed
                        }
                        let formatted = parsed == 0 && newText.isEmpty ? "" : parsed.formattedGrouped
                        if text != formatted {
                            text = formatted
                        }
                    }

                Text("₫")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.accentRose)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            )
        }
        .onAppear {
            if value > 0 {
                text = value.formattedGrouped
            }
        }
        .onChange(of: value) { _, newValue in
            let formatted = newValue == 0 ? "" : newValue.formattedGrouped
            if text != formatted && !text.isEmpty {
                text = formatted
            }
        }
    }
}

