import SwiftUI

/// Màn hình Trang chủ (Tab 1 của EduPetal) — Chỉ hiển thị 4 nhóm thông tin tổng quan gọn gàng:
/// A. Tài chính (Biểu đồ tròn trực quan ở trung tâm: Đã thu vs Còn nợ trên tổng Học phí phát sinh, kèm nhãn kỳ thống kê)
/// B. Học sinh (Tổng số học sinh đang hoạt động)
/// C. Lớp học (Tổng số lớp đang hoạt động)
/// D. Lịch dạy (Các buổi hôm nay hoặc sắp tới)
public struct HomeView: View {
    @State public var viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // MARK: - Header: Trang chủ, Ngày hiện tại & Nút Cài đặt
                    headerBar

                    // MARK: - B & C. Tổng số Học sinh đang hoạt động & Lớp học đang hoạt động (2 thẻ gọn song song)
                    studentsAndClassesRow

                    // MARK: - A. Tài chính: Biểu đồ tròn (Donut Chart) nổi bật ở giữa + 3 chỉ số Phát sinh / Đã thu / Còn nợ
                    financeDonutChartCard

                    // MARK: - D. Lịch dạy (Hôm nay hoặc Sắp tới)
                    scheduleCompactSection
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.lg)
            }
            .background(AppColors.background.ignoresSafeArea())
            #if canImport(UIKit)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $viewModel.isShowingSettings) {
                SettingsView(
                    activeStudentsCount: viewModel.metrics.activeStudentsCount,
                    activeClassesCount: viewModel.metrics.activeClassesCount,
                    totalSessionsCount: viewModel.sessions.count,
                    upcomingSessions: viewModel.sessions
                )
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
            .task {
                await viewModel.loadDashboard()
            }
        }
    }

    // MARK: - Bảng màu phân tách rõ ràng cho Trang chủ & Biểu đồ tròn (Không trùng tông)

    /// Màu vòng nền khi chưa phát sinh (Xám xanh dịu, tách biệt hoàn toàn với nền hồng)
    private var chartTrackColor: Color {
        Color.dynamic(light: "#E2E8F0", dark: "#2D3340")
    }

    /// 1. Học phí phát sinh — Xanh Indigo (Royal Blue / Indigo)
    private var accruedColor: Color {
        Color.dynamic(light: "#4F46E5", dark: "#818CF8")
    }

    private var accruedTileBg: Color {
        Color.dynamic(light: "#EEF2FF", dark: "#1E2238")
    }

    /// 2. Đã thu — Xanh Ngọc Lục Bảo (Emerald Green)
    private var collectedStartColor: Color {
        Color.dynamic(light: "#34D399", dark: "#34D399")
    }

    private var collectedEndColor: Color {
        Color.dynamic(light: "#059669", dark: "#10B981")
    }

    private var collectedTileBg: Color {
        Color.dynamic(light: "#ECFDF5", dark: "#132E25")
    }

    /// 3. Còn nợ — Cam Hổ Phách (Amber / Warm Orange)
    private var outstandingStartColor: Color {
        Color.dynamic(light: "#FBBF24", dark: "#FBBF24")
    }

    private var outstandingEndColor: Color {
        Color.dynamic(light: "#EA580C", dark: "#F97316")
    }

    private var outstandingTileBg: Color {
        Color.dynamic(light: "#FFF7ED", dark: "#332414")
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Trang chủ", "Home"))
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.primaryText)

                Text(viewModel.formattedDate)
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Button {
                viewModel.isShowingSettings = true
            } label: {
                AvatarView(
                    avatarPath: AvatarStorageService.shared.teacherAvatarPath,
                    initials: "EP",
                    size: 40,
                    showBorder: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Cài đặt & Hồ sơ", "Settings & Profile"))
        }
    }

    // MARK: - B & C. Học sinh & Lớp học (2 ô ngang gọn gàng, 2 màu phân biệt rõ)

    private var studentsAndClassesRow: some View {
        HStack(spacing: AppSpacing.sm) {
            // B. Học sinh đang hoạt động (Hồng chủ đạo)
            Button {
                AppNavigationState.shared.selectedTabRaw = AppTab.students.rawValue
            } label: {
                compactCounterPill(
                    icon: "person.2.fill",
                    iconColor: Color.dynamic(light: "#D94676", dark: "#F4729B"),
                    iconBg: Color.dynamic(light: "#FCEBF1", dark: "#38242C"),
                    title: L("Học sinh", "Students"),
                    count: viewModel.metrics.activeStudentsCount,
                    subtitle: L("Đang hoạt động", "Active")
                )
            }
            .buttonStyle(.plain)

            // C. Lớp học đang hoạt động (Xanh Indigo phân biệt rõ với Học sinh)
            Button {
                AppNavigationState.shared.selectedTabRaw = AppTab.classes.rawValue
            } label: {
                compactCounterPill(
                    icon: "graduationcap.fill",
                    iconColor: accruedColor,
                    iconBg: accruedTileBg,
                    title: L("Lớp học", "Classes"),
                    count: viewModel.metrics.activeClassesCount,
                    subtitle: L("Đang hoạt động", "Active")
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func compactCounterPill(
        icon: String,
        iconColor: Color,
        iconBg: Color,
        title: String,
        count: Int,
        subtitle: String
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(count)")
                        .font(AppTypography.font(size: 20, weight: .bold, design: .rounded, relativeTo: .title3))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()

                    Text(title)
                        .font(AppTypography.font(size: 14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                }

                Text(subtitle)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.divider.opacity(0.65), lineWidth: 0.8)
        )
    }

    // MARK: - A. Tài chính: Biểu đồ tròn ở giữa (3 tông màu tách biệt: Xanh Indigo - Xanh Ngọc - Cam Hổ Phách)

    private var collectedRatio: Double {
        let accrued = viewModel.metrics.financeSummary.accruedTuition
        let collected = viewModel.metrics.financeSummary.collectedTuition
        guard accrued > 0 else { return 0 }
        return min(1.0, max(0.0, Double(collected) / Double(accrued)))
    }

    private var collectedPercentInt: Int {
        let accrued = viewModel.metrics.financeSummary.accruedTuition
        guard accrued > 0 else { return 0 }
        return Int((collectedRatio * 100.0).rounded())
    }

    private var outstandingPercentInt: Int {
        let accrued = viewModel.metrics.financeSummary.accruedTuition
        guard accrued > 0 else { return 0 }
        return max(0, 100 - collectedPercentInt)
    }

    private var financeDonutChartCard: some View {
        let summary = viewModel.metrics.financeSummary
        let hasAccrued = summary.accruedTuition > 0
        let hasOutstanding = summary.outstandingBalance > 0
        let isPartial = hasAccrued && collectedRatio > 0.0 && collectedRatio < 1.0
        let gap: CGFloat = isPartial ? 0.025 : 0.0

        return Button {
            AppNavigationState.shared.selectedTabRaw = AppTab.finance.rawValue
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Hàng tiêu đề + Nhãn kỳ thống kê
                HStack(alignment: .center) {
                    Text(L("Tài chính học phí", "Tuition Overview"))
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    Spacer()

                    Text(L("Kỳ: Tất cả thời gian", "Period: All Time"))
                        .font(AppTypography.caption2)
                        .foregroundColor(accruedColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(accruedTileBg)
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                }

                // Biểu đồ tròn ở trung tâm + Chú giải 2 màu tương phản rõ ràng (Xanh Ngọc vs Cam)
                VStack(spacing: 12) {
                    ZStack {
                        // Đĩa nền bên trong lòng biểu đồ
                        Circle()
                            .fill(Color.dynamic(light: "#F8FAFC", dark: "#1F242D"))
                            .frame(width: 116, height: 116)

                        // Vòng nền (Track)
                        Circle()
                            .stroke(
                                chartTrackColor,
                                style: StrokeStyle(lineWidth: 20, lineCap: .round)
                            )

                        // Khi chưa có học phí phát sinh (0 ₫), hiển thị 2 nửa vòng mẫu (Xanh Ngọc & Cam) độ đậm vừa phải để phân biệt rõ 2 nhóm trên biểu đồ
                        if !hasAccrued {
                            Circle()
                                .trim(from: 0.025, to: 0.475)
                                .stroke(
                                    LinearGradient(
                                        colors: [collectedStartColor.opacity(0.55), collectedEndColor.opacity(0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))

                            Circle()
                                .trim(from: 0.525, to: 0.975)
                                .stroke(
                                    LinearGradient(
                                        colors: [outstandingStartColor.opacity(0.55), outstandingEndColor.opacity(0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                        }

                        // Cung tròn Phần Còn nợ (Cam Hổ Phách — tách biệt hoàn toàn với Xanh Ngọc)
                        if hasAccrued && hasOutstanding {
                            let startTrim = isPartial ? min(0.96, CGFloat(collectedRatio) + gap) : 0.0
                            let endTrim: CGFloat = isPartial ? (1.0 - gap) : 1.0
                            if endTrim > startTrim {
                                Circle()
                                    .trim(from: startTrim, to: endTrim)
                                    .stroke(
                                        LinearGradient(
                                            colors: [outstandingStartColor, outstandingEndColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                            }
                        }

                        // Cung tròn Phần Đã thu (Xanh Ngọc Lục Bảo — nổi bật, dễ nhận biết ngay)
                        if hasAccrued && collectedRatio > 0 {
                            let startTrim: CGFloat = isPartial ? gap : 0.0
                            let endTrim = isPartial ? max(startTrim + 0.02, CGFloat(collectedRatio) - gap) : 1.0
                            Circle()
                                .trim(from: startTrim, to: endTrim)
                                .stroke(
                                    LinearGradient(
                                        colors: [collectedStartColor, collectedEndColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                        }

                        // Tâm biểu đồ tròn: Tỷ lệ đã thu & Tổng phát sinh
                        VStack(spacing: 2) {
                            Text(L("Đã thu", "Collected"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)

                            Text("\(collectedPercentInt)%")
                                .font(AppTypography.font(size: 28, weight: .bold, design: .rounded, relativeTo: .title))
                                .foregroundColor(hasAccrued ? collectedEndColor : AppColors.primaryText)
                                .monospacedDigit()

                            Text(summary.accruedTuition.formattedVND)
                                .font(AppTypography.font(size: 11, weight: .semibold, design: .rounded, relativeTo: .caption2))
                                .foregroundColor(accruedColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(accruedTileBg)
                                )
                                .padding(.top, 2)
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(width: 160, height: 160)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

                    // Chú giải 2 cung của biểu đồ tròn (Xanh Ngọc vs Cam Hổ Phách)
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(collectedEndColor)
                                .frame(width: 9, height: 9)
                            Text("\(L("Đã thu", "Collected")): \(collectedPercentInt)%")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.primaryText)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(collectedTileBg))

                        HStack(spacing: 6) {
                            Circle()
                                .fill(outstandingEndColor)
                                .frame(width: 9, height: 9)
                            Text("\(L("Còn nợ", "Outstanding")): \(outstandingPercentInt)%")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.primaryText)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(outstandingTileBg))
                    }

                    // 3 Ô số liệu 3 màu hoàn toàn khác nhau: Xanh Indigo (Phát sinh) | Xanh Ngọc (Đã thu) | Cam (Còn nợ)
                    HStack(spacing: 8) {
                        financeMetricTile(
                            dotColor: accruedColor,
                            tileBg: accruedTileBg,
                            title: L("Học phí phát sinh", "Accrued"),
                            amount: summary.accruedTuition,
                            valueColor: accruedColor
                        )

                        financeMetricTile(
                            dotColor: collectedEndColor,
                            tileBg: collectedTileBg,
                            title: L("Đã thu", "Collected"),
                            amount: summary.collectedTuition,
                            valueColor: collectedEndColor
                        )

                        financeMetricTile(
                            dotColor: outstandingEndColor,
                            tileBg: outstandingTileBg,
                            title: L("Còn nợ", "Outstanding"),
                            amount: summary.outstandingBalance,
                            valueColor: outstandingEndColor
                        )
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func financeMetricTile(
        dotColor: Color,
        tileBg: Color,
        title: String,
        amount: Int64,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(amount.formattedVND)
                .font(AppTypography.font(size: 14, weight: .bold, design: .rounded, relativeTo: .subheadline))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(tileBg)
        )
    }

    // MARK: - D. Lịch dạy (Gọn trong 1 khung duy nhất, tối đa 3 buổi gần nhất)

    private var scheduleCompactSection: some View {
        let allDisplaySessions = viewModel.metrics.displaySessions
        let visibleSessions = Array(allDisplaySessions.prefix(3))
        let isUpcoming = viewModel.metrics.isShowingUpcomingSessions

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Button {
                AppNavigationState.shared.selectedTabRaw = AppTab.schedule.rawValue
            } label: {
                HStack(alignment: .center) {
                    Text(
                        isUpcoming
                            ? L("Lịch dạy sắp tới", "Upcoming Schedule")
                            : L("Lịch dạy hôm nay", "Today's Schedule")
                    )
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                    Spacer()

                    if !allDisplaySessions.isEmpty {
                        Text(L("\(allDisplaySessions.count) buổi", "\(allDisplaySessions.count) sessions"))
                            .font(AppTypography.caption2)
                            .foregroundColor(accruedColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(accruedTileBg)
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                if visibleSessions.isEmpty {
                    Button {
                        AppNavigationState.shared.selectedTabRaw = AppTab.schedule.rawValue
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(accruedTileBg)
                                    .frame(width: 34, height: 34)

                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accruedColor)
                            }

                            Text(L("Chưa có buổi dạy hôm nay hoặc sắp tới.", "No sessions today or upcoming."))
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.secondaryText)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.tertiaryText)
                        }
                        .padding(AppSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            AppNavigationState.shared.navigateToSession(
                                sessionId: session.id,
                                sessionDate: session.startTime
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: viewModel.classColorHex(for: session.classId)))
                                    .frame(width: 9, height: 9)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.className(for: session.classId))
                                        .font(AppTypography.font(size: 15, weight: .semibold, relativeTo: .subheadline))
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)

                                    Text(formattedSessionTime(session, includeDate: isUpcoming))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                        .monospacedDigit()
                                }

                                Spacer()

                                Text(statusText(for: session.status))
                                    .font(AppTypography.caption2)
                                    .foregroundColor(statusColor(for: session.status))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(statusColor(for: session.status).opacity(0.12))
                                    )

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.tertiaryText)
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < visibleSessions.count - 1 {
                            Divider()
                                .background(AppColors.divider.opacity(0.6))
                                .padding(.leading, 35)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 0.8)
            )
        }
    }

    private func formattedSessionTime(_ session: TeachingSessionEntity, includeDate: Bool) -> String {
        let start = session.startTime.formatted(date: .omitted, time: .shortened)
        let end = session.endTime.formatted(date: .omitted, time: .shortened)
        if includeDate {
            let dayStr = session.startTime.formatted(.dateTime.day().month())
            return "\(dayStr) • \(start) – \(end)"
        }
        return "\(start) – \(end)"
    }

    private func statusText(for status: SessionStatus) -> String {
        switch status {
        case .scheduled:
            return L("Sắp dạy", "Scheduled")
        case .completed:
            return L("Hoàn thành", "Completed")
        case .cancelled:
            return L("Đã hủy", "Cancelled")
        }
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .scheduled:
            return accruedColor
        case .completed:
            return collectedEndColor
        case .cancelled:
            return AppColors.error
        }
    }
}




