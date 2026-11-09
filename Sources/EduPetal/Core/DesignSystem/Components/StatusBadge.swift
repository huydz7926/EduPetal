import SwiftUI

/// Huy hiệu trạng thái (StatusBadge) dạng Pill bo tròn chuẩn
public struct StatusBadge: View {
    public let title: String
    public let icon: String?
    public let textColor: Color
    public let backgroundColor: Color

    public init(
        title: String,
        icon: String? = nil,
        textColor: Color,
        backgroundColor: Color
    ) {
        self.title = title
        self.icon = icon
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(LocalizationManager.translate(title))
                .font(AppTypography.caption1)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs + 1)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .foregroundColor(textColor)
    }

    // MARK: - Pre-configured Factory Badges

    /// Điểm danh: Có mặt
    public static func attendancePresent() -> StatusBadge {
        StatusBadge(
            title: "Có mặt",
            icon: "checkmark.circle.fill",
            textColor: AppColors.success,
            backgroundColor: AppColors.successBackground
        )
    }

    /// Điểm danh: Vắng mặt
    public static func attendanceAbsent() -> StatusBadge {
        StatusBadge(
            title: "Vắng",
            icon: "xmark.circle.fill",
            textColor: AppColors.error,
            backgroundColor: AppColors.errorBackground
        )
    }

    /// Điểm danh: Có phép
    public static func attendanceExcused() -> StatusBadge {
        StatusBadge(
            title: "Có phép",
            icon: "info.circle.fill",
            textColor: AppColors.warning,
            backgroundColor: AppColors.warningBackground
        )
    }

    /// Điểm danh: Chưa điểm danh
    public static func attendancePending() -> StatusBadge {
        StatusBadge(
            title: "Chưa điểm danh",
            icon: "clock.fill",
            textColor: AppColors.secondaryText,
            backgroundColor: AppColors.surfaceSubtle
        )
    }

    /// Học phí: Đã thanh toán
    public static func tuitionPaid() -> StatusBadge {
        StatusBadge(
            title: "Đã thu",
            icon: "checkmark.seal.fill",
            textColor: AppColors.success,
            backgroundColor: AppColors.successBackground
        )
    }

    /// Học phí: Đã thanh toán một phần
    public static func tuitionPartiallyPaid() -> StatusBadge {
        StatusBadge(
            title: "Thu một phần",
            icon: "dollarsign.circle.fill",
            textColor: AppColors.warning,
            backgroundColor: AppColors.warningBackground
        )
    }

    /// Học phí: Còn nợ
    public static func tuitionUnpaid() -> StatusBadge {
        StatusBadge(
            title: "Chưa thu",
            icon: "exclamationmark.triangle.fill",
            textColor: AppColors.error,
            backgroundColor: AppColors.errorBackground
        )
    }

    /// Bài tập: Đã chấm
    public static func assignmentGraded() -> StatusBadge {
        StatusBadge(
            title: "Đã chấm",
            icon: "star.fill",
            textColor: AppColors.success,
            backgroundColor: AppColors.successBackground
        )
    }

    /// Bài tập: Đã nộp
    public static func assignmentSubmitted() -> StatusBadge {
        StatusBadge(
            title: "Đã nộp",
            icon: "arrow.up.doc.fill",
            textColor: AppColors.warning,
            backgroundColor: AppColors.warningBackground
        )
    }

    // MARK: - Teaching Session Status Badges

    /// Buổi dạy: Hoàn thành
    public static func sessionCompleted() -> StatusBadge {
        StatusBadge(
            title: "Đã xong",
            icon: "checkmark.circle.fill",
            textColor: AppColors.success,
            backgroundColor: AppColors.successBackground
        )
    }

    /// Buổi dạy: Đã lên lịch
    public static func sessionScheduled() -> StatusBadge {
        StatusBadge(
            title: "Đã lên lịch",
            icon: "clock",
            textColor: AppColors.info,
            backgroundColor: AppColors.infoBackground
        )
    }

    /// Buổi dạy: Đã hủy
    public static func sessionCancelled() -> StatusBadge {
        StatusBadge(
            title: "Đã hủy",
            icon: "xmark.circle",
            textColor: AppColors.error,
            backgroundColor: AppColors.errorBackground
        )
    }
}

