import SwiftUI
import SwiftData

public struct EduPetalApp: App {
    @State private var themeManager = ThemeManager.shared

    public init() {
        LocalNotificationService.shared.configureDelegateIfNeeded()
    }

    public var body: some Scene {
        WindowGroup {
            EduPetalRootView()
                .preferredColorScheme(themeManager.colorScheme)
        }
        .modelContainer(for: EduPetalSchemaV1.models)
    }
}

/// Màn hình Catalog trình diễn toàn bộ Design System Soft Pink Education (Sprint 1)
public struct DesignSystemCatalogView: View {
    @State private var sampleMoney: Int64 = 250000
    @State private var isButtonLoading: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Header Card
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("EduPetal Design System")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)

                            Text("Where Teaching Blossoms — Soft Pink Education Palette")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Status Badges Section
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Huy hiệu trạng thái (Status Badges)")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)

                            HStack {
                                StatusBadge.attendancePresent()
                                StatusBadge.attendanceAbsent()
                                StatusBadge.attendanceExcused()
                            }

                            HStack {
                                StatusBadge.tuitionPaid()
                                StatusBadge.tuitionPartiallyPaid()
                                StatusBadge.tuitionUnpaid()
                            }

                            HStack {
                                StatusBadge.assignmentGraded()
                                StatusBadge.assignmentSubmitted()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Currency Input Card
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Đơn vị tiền tệ (Currency Input)")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)

                            CurrencyTextField("Đơn giá buổi học", placeholder: "0", value: $sampleMoney)

                            HStack {
                                Text("Số tiền đã parse:")
                                    .font(AppTypography.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text(sampleMoney.formattedVND)
                                    .font(AppTypography.currencyRegular)
                                    .foregroundColor(AppColors.accentRose)
                            }
                        }
                    }

                    // Action Buttons Card
                    AppCard {
                        VStack(spacing: AppSpacing.sm) {
                            PrimaryButton(
                                isButtonLoading ? "Đang xử lý..." : "Nút hành động chính",
                                icon: "sparkles",
                                isLoading: isButtonLoading
                            ) {
                                isButtonLoading = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isButtonLoading = false
                                }
                            }

                            SecondaryButton("Nút hành động phụ", icon: "doc.text") {
                                // Action demo
                            }

                            SecondaryButton("Nút cảnh báo xóa", icon: "trash", isDestructive: true) {
                                // Destructive demo
                            }
                        }
                    }

                    // Empty State Demo
                    AppCard {
                        EmptyStateView(
                            icon: "person.2.slash",
                            title: "Chưa có học sinh",
                            message: "Bắt đầu thêm học sinh để quản lý điểm danh và học phí",
                            actionTitle: "Thêm học sinh mới"
                        ) {
                            // Demo action
                        }
                        .frame(height: 260)
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Design System")
        }
    }
}
