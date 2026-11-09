import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Quản lý Tài chính & Học phí toàn ứng dụng (Tab 5 của EduPetal)
public struct FinanceDashboardView: View {
    public enum FinanceSectionTab: String, CaseIterable, Identifiable {
        case students = "Học phí học sinh"
        case receipts = "Phiếu thu đã lập"
        public var id: String { rawValue }

        public var localizedTitle: String {
            switch self {
            case .students: return L("Học phí học sinh", "Student Tuition")
            case .receipts: return L("Phiếu thu đã lập", "Payment Receipts")
            }
        }
    }

    @State public var viewModel: FinanceViewModel
    @State private var activeSectionTab: FinanceSectionTab = .students
    @State private var isShowingRecordPaymentSheet: Bool = false
    @State private var selectedStudentForPayment: StudentEntity? = nil
    @State private var selectedPaymentForReceipt: PaymentEntity? = nil
    @State private var selectedStudentForDetail: StudentEntity? = nil
    @State private var searchText: String = ""
    @State private var paymentToCancel: PaymentEntity? = nil
    @State private var isShowingCancelPaymentDialog: Bool = false
    @State private var didEnsureDefaultAllTime: Bool = false

    public init(viewModel: FinanceViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    private var displayedStudentItems: [StudentFinanceItem] {
        viewModel.buildStudentFinanceItems(searchQuery: searchText)
    }

    private func computeDisplayedPayments(using currentStudentItems: [StudentFinanceItem]) -> [PaymentEntity] {
        let allowedStudentIds = viewModel.selectedClassFilterId != nil ? Set(currentStudentItems.map { $0.student.id }) : nil

        let filtered = viewModel.payments
            .filter { p in
                guard viewModel.isDateInSelectedPeriod(p.paidAt) else { return false }
                if let allowed = allowedStudentIds {
                    return allowed.contains(p.studentId)
                }
                return true
            }
            .sorted { $0.paidAt > $1.paidAt }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filtered }
        let query = trimmed.lowercased()

        return filtered.filter { p in
            let name = viewModel.studentName(for: p.studentId).lowercased()
            let code = "#rec-\(p.id.uuidString.prefix(8).lowercased())"
            let note = p.note.lowercased()
            let method = p.paymentMethod.lowercased()
            return name.contains(query) || code.contains(query) || note.contains(query) || method.contains(query)
        }
    }

    public var body: some View {
        let studentItems = displayedStudentItems
        let paymentItems = computeDisplayedPayments(using: studentItems)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    // 1. Bộ lọc Kỳ ("Tất cả" mặc định đầu tiên)
                    periodAndClassFilterBar

                    // 2. 2 Thẻ Tổng quan gọn gàng (Đã thu & Còn nợ)
                    summaryCardsRow(studentItems: studentItems)

                    // 3. Chuyển đổi gọn gàng giữa Học phí học sinh & Phiếu thu
                    sectionTabSwitcher(studentCount: studentItems.count, paymentCount: paymentItems.count)

                    if activeSectionTab == .students {
                        studentTuitionListSection(studentItems: studentItems)
                    } else {
                        paymentReceiptsSection(paymentItems: paymentItems)
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Học phí", "Tuition"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    classFilterMenu
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedStudentForPayment = nil
                        isShowingRecordPaymentSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L("Thu tiền", "Collect"))
                        }
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
            .sheet(isPresented: $isShowingRecordPaymentSheet) {
                RecordPaymentSheet(
                    students: viewModel.students.filter { !$0.isArchived },
                    preselectedStudentId: selectedStudentForPayment?.id,
                    getOutstandingBalance: { studentId in
                        viewModel.outstandingBalance(for: studentId)
                    },
                    getUnpaidSessionItems: { studentId in
                        viewModel.unpaidChargeSessionDetails(for: studentId)
                    },
                    onSave: { studentId, amount, paidAt, method, note in
                        let savedPayment = try await viewModel.recordPayment(
                            studentId: studentId,
                            amount: amount,
                            paidAt: paidAt,
                            paymentMethod: method,
                            note: note
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedPaymentForReceipt = savedPayment
                        }
                    },
                    onSaveWithSelection: { studentId, amount, paidAt, method, note, selectedChargeIds in
                        let savedPayment = try await viewModel.recordPayment(
                            studentId: studentId,
                            amount: amount,
                            paidAt: paidAt,
                            paymentMethod: method,
                            note: note,
                            selectedChargeIds: selectedChargeIds
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedPaymentForReceipt = savedPayment
                        }
                    }
                )
            }
            .sheet(item: $selectedPaymentForReceipt) { payment in
                PaymentReceiptSheet(payment: payment, viewModel: viewModel)
            }
            .sheet(item: $selectedStudentForDetail) { student in
                StudentTuitionDetailSheet(
                    studentId: student.id,
                    viewModel: viewModel,
                    onTapRecordPayment: { targetStudent in
                        selectedStudentForPayment = targetStudent
                        isShowingRecordPaymentSheet = true
                    },
                    onTapPaymentReceipt: { payment in
                        selectedPaymentForReceipt = payment
                    }
                )
            }
            .searchable(text: $searchText, prompt: Text(L("Tìm học sinh, lớp, mã phiếu thu...", "Search student, class, receipt code...")))
            .confirmationDialog(
                "Hủy phiếu thu #REC-\(paymentToCancel?.id.uuidString.prefix(8).uppercased() ?? "")?",
                isPresented: $isShowingCancelPaymentDialog,
                titleVisibility: .visible
            ) {
                Button("Hủy phiếu thu", role: .destructive) {
                    if let p = paymentToCancel {
                        Task {
                            try? await viewModel.cancelPayment(paymentId: p.id)
                        }
                    }
                }
                Button("Đóng", role: .cancel) {}
            } message: {
                Text("Xóa phiếu thu này và hoàn lại công nợ \(paymentToCancel?.amount.formattedVND ?? "") cho học sinh.")
            }
            .refreshable {
                await viewModel.loadData()
            }
            .onAppear {
                if !didEnsureDefaultAllTime {
                    viewModel.selectedTimeFilter = .allTime
                    didEnsureDefaultAllTime = true
                }
            }
            .task {
                await viewModel.loadData()
            }
        }
    }

    // MARK: - 1. Period & Class Filter Bar

    private var periodAndClassFilterBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Picker(L("Kỳ học phí", "Period"), selection: $viewModel.selectedTimeFilter) {
                ForEach(FinanceTimeFilter.allCases) { filter in
                    Text(filter.localizedTitle).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            // Chỉ hiện bộ chọn tháng khi chọn "Chọn tháng" để không lặp lại thông tin kỳ xem
            if viewModel.selectedTimeFilter == .customMonth {
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        viewModel.shiftCustomMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .padding(6)
                            .background(Circle().fill(AppColors.secondaryPink))
                            .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)

                    Text(viewModel.periodDisplayLabel)
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.primaryText)

                    Button {
                        viewModel.shiftCustomMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .padding(6)
                            .background(Circle().fill(AppColors.secondaryPink))
                            .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private var classFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedClassFilterId = nil
            } label: {
                HStack {
                    Text(L("Tất cả các lớp", "All Classes"))
                    if viewModel.selectedClassFilterId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(viewModel.classes.filter { !$0.isArchived }) { cls in
                Button {
                    viewModel.selectedClassFilterId = cls.id
                } label: {
                    HStack {
                        Text(cls.name)
                        if viewModel.selectedClassFilterId == cls.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 11))
                Text(selectedClassFilterTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(AppTypography.caption1)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppColors.secondaryPink))
            .foregroundColor(AppColors.accentRose)
        }
    }

    private var selectedClassFilterTitle: String {
        guard let classId = viewModel.selectedClassFilterId else {
            return L("Tất cả lớp", "All Classes")
        }
        return viewModel.className(for: classId)
    }

    // MARK: - 2. 2-Card Summary Row (SnapSpend Style: Đã thu & Còn nợ)

    private func summaryCardsRow(studentItems: [StudentFinanceItem]) -> some View {
        let isAllTime = viewModel.selectedTimeFilter == .allTime
        let outstandingCount = studentItems.filter { $0.outstanding > 0 }.count

        return HStack(spacing: 12) {
            // Thẻ 1: Đã thu
            Button {
                activeSectionTab = .receipts
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColors.success.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.down.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.success)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isAllTime ? L("Đã thu", "Collected") : L("Đã thu trong kỳ", "Collected in Period"))
                            .font(AppTypography.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)

                        Text(viewModel.periodCollectedTuition.formattedVND)
                            .font(AppTypography.font(size: 17))
                            .foregroundColor(AppColors.success)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.surfaceCard)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)

            // Thẻ 2: Còn nợ
            Button {
                activeSectionTab = .students
                if viewModel.selectedStatusFilter == .hasOutstanding {
                    viewModel.selectedStatusFilter = .all
                    viewModel.showOnlyOutstanding = false
                } else {
                    viewModel.selectedStatusFilter = .hasOutstanding
                    viewModel.showOnlyOutstanding = true
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill((viewModel.totalOutstandingToDate > 0 ? AppColors.warning : AppColors.secondaryText).opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(viewModel.totalOutstandingToDate > 0 ? AppColors.warning : AppColors.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(L("Còn nợ", "Outstanding"))
                                .font(AppTypography.caption1)
                                .fontWeight(.medium)
                                .foregroundColor(AppColors.secondaryText)
                            if outstandingCount > 0 {
                                Text("(\(outstandingCount))")
                                    .font(AppTypography.font(size: 10))
                                    .foregroundColor(AppColors.warning)
                            }
                        }

                        Text(viewModel.totalOutstandingToDate.formattedVND)
                            .font(AppTypography.font(size: 17))
                            .foregroundColor(viewModel.totalOutstandingToDate > 0 ? AppColors.warning : AppColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.surfaceCard)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(viewModel.selectedStatusFilter == .hasOutstanding ? AppColors.warning : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. Section Tab Switcher

    private func sectionTabSwitcher(studentCount: Int, paymentCount: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(FinanceSectionTab.allCases) { tab in
                let isSelected = activeSectionTab == tab
                let count = tab == .students ? studentCount : paymentCount
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeSectionTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .students ? "person.2.fill" : "doc.text.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.localizedTitle)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                        Text("\(count)")
                            .font(AppTypography.font(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(isSelected ? Color.white.opacity(0.24) : AppColors.surfaceSubtle)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? AppColors.primaryPink : AppColors.surfaceCard)
                    )
                    .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 4. Student Tuition List Section

    private var simplifiedStatusFilters: [StudentTuitionStatusFilter] {
        [.all, .hasOutstanding, .paid]
    }

    private func studentTuitionListSection(studentItems: [StudentFinanceItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Thanh lọc trạng thái thanh toán gọn gàng (3 mức: Tất cả, Còn nợ, Đã thu đủ)
            HStack(spacing: 8) {
                ForEach(simplifiedStatusFilters) { filter in
                    let isSelected = (viewModel.showOnlyOutstanding ? .hasOutstanding : viewModel.selectedStatusFilter) == filter
                    Button {
                        viewModel.showOnlyOutstanding = (filter == .hasOutstanding)
                        viewModel.selectedStatusFilter = filter
                    } label: {
                        Text(filter.localizedTitle)
                            .font(AppTypography.caption1)
                            .fontWeight(isSelected ? .bold : .medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isSelected ? AppColors.accentRose : AppColors.surfaceCard)
                            )
                            .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : AppColors.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if studentItems.isEmpty {
                AppCard {
                    if viewModel.students.isEmpty {
                        EmptyStateView(
                            icon: "dollarsign.circle.fill",
                            title: L("Chưa phát sinh học phí", "No Tuition Yet"),
                            message: L("Học phí được tính tự động khi hoàn thành buổi dạy.", "Tuition is calculated automatically when a session is completed."),
                            actionTitle: L("Mở Lớp học", "Open Classes")
                        ) {
                            AppNavigationState.shared.selectedTabRaw = AppTab.classes.rawValue
                        }
                    } else {
                        EmptyStateView(
                            icon: "checkmark.circle.fill",
                            title: L("Không có học sinh khớp bộ lọc", "No Matching Students"),
                            message: L("Chuyển sang 'Tất cả' để xem đầy đủ danh sách.", "Switch to 'All' to view all students."),
                            actionTitle: viewModel.selectedStatusFilter != .all ? L("Xem tất cả", "Show All") : nil
                        ) {
                            viewModel.showOnlyOutstanding = false
                            viewModel.selectedStatusFilter = .all
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(studentItems) { item in
                        studentBalanceRow(item: item)
                    }
                }
            }
        }
    }

    // MARK: - 5. Payment Receipts Section (Chỉ hiển thị Phiếu thu, đã bỏ Tiền phát sinh)

    private func paymentReceiptsSection(paymentItems: [PaymentEntity]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if paymentItems.isEmpty {
                AppCard {
                    EmptyStateView(
                        icon: "doc.plaintext",
                        title: L("Chưa có phiếu thu", "No Receipts Yet"),
                        message: L("Phiếu thu học phí sẽ hiển thị tại đây.", "Payment receipts will appear here.")
                    )
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(paymentItems) { payment in
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedPaymentForReceipt = payment
                        } label: {
                            paymentRow(payment: payment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Component Views

    private func studentBalanceRow(item: StudentFinanceItem) -> some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    selectedStudentForDetail = item.student
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        studentAvatarView(student: item.student)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.student.fullName)
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)

                            HStack(spacing: 5) {
                                if !item.enrolledClassNames.isEmpty {
                                    Text(item.enrolledClassNames.joined(separator: " • "))
                                        .font(AppTypography.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.accentRose)
                                        .lineLimit(1)
                                    Text("•")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Text(L("\(item.completedSessionsInPeriodCount) buổi", "\(item.completedSessionsInPeriodCount) sessions"))
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)

                                if item.totalProofAttachmentsCount > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 9))
                                        Text("\(item.totalProofAttachmentsCount)")
                                            .font(AppTypography.caption2)
                                    }
                                    .foregroundColor(AppColors.secondaryText)
                                }
                            }

                            Text(
                                L(
                                    "Đã thu: \(item.collectedInPeriod.formattedVND)",
                                    "Collected: \(item.collectedInPeriod.formattedVND)"
                                )
                            )
                            .font(AppTypography.caption2)
                            .foregroundColor(item.collectedInPeriod > 0 ? AppColors.success : AppColors.secondaryText)
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Cột phải: Số nợ + nút Thu tiền (hoặc trạng thái Đã thu đủ) không lặp lại dòng dưới
                if item.outstanding > 0 {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(L("Nợ \(item.outstanding.formattedVND)", "Owed \(item.outstanding.formattedVND)"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.warning)
                            .lineLimit(1)

                        Button {
                            selectedStudentForPayment = item.student
                            isShowingRecordPaymentSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "banknote.fill")
                                    .font(.system(size: 11))
                                Text(L("Thu tiền", "Collect"))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.onPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppColors.primaryPink))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        selectedStudentForDetail = item.student
                    } label: {
                        VStack(alignment: .trailing, spacing: 4) {
                            StatusBadge(
                                title: item.accrued > 0 ? L("Đã thu đủ", "Paid") : L("0 ₫", "0 ₫"),
                                icon: "checkmark.circle.fill",
                                textColor: item.accrued > 0 ? AppColors.success : AppColors.secondaryText,
                                backgroundColor: item.accrued > 0 ? AppColors.success.opacity(0.12) : AppColors.surfaceSubtle
                            )

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func studentAvatarView(student: StudentEntity) -> some View {
        ZStack {
            Circle()
                .fill(AppColors.secondaryPink)
                .frame(width: 44, height: 44)
            #if canImport(UIKit)
            if let path = student.avatarPath, !path.isEmpty,
               let uiImg = AvatarStorageService.shared.loadAvatar(named: path) ?? PhotoStorageService.shared.loadImage(named: path) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Text(initials(for: student.fullName))
                    .font(AppTypography.caption1)
                    .foregroundColor(AppColors.accentRose)
                    .fontWeight(.bold)
            }
            #else
            Text(initials(for: student.fullName))
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.accentRose)
                .fontWeight(.bold)
            #endif
        }
    }

    private func paymentStatusBadge(status: StudentTuitionPaymentStatus) -> some View {
        switch status {
        case .paid:
            StatusBadge(title: status.rawValue, icon: "checkmark.circle.fill", textColor: AppColors.success, backgroundColor: AppColors.success.opacity(0.12))
        case .partiallyPaid:
            StatusBadge(title: status.rawValue, icon: "circle.lefthalf.filled", textColor: AppColors.warning, backgroundColor: AppColors.warning.opacity(0.12))
        case .unpaid:
            StatusBadge(title: status.rawValue, icon: "exclamationmark.circle.fill", textColor: AppColors.error, backgroundColor: AppColors.error.opacity(0.12))
        case .noCharges:
            StatusBadge(title: "Đã thu đủ", icon: "checkmark.circle", textColor: AppColors.secondaryText, backgroundColor: AppColors.surfaceSubtle)
        }
    }

    private func paymentRow(payment: PaymentEntity) -> some View {
        let code = "#REC-\(payment.id.uuidString.prefix(8).uppercased())"
        return AppCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.success.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.success)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(viewModel.studentName(for: payment.studentId))
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.primaryText)
                            .fontWeight(.bold)
                        Text(code)
                            .font(AppTypography.font(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                    }

                    HStack(spacing: 6) {
                        Text(payment.paymentMethod)
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.secondaryPink.opacity(0.6))
                            .cornerRadius(4)

                        Text(payment.paidAt.formatted(date: .numeric, time: .shortened))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("+\(payment.amount.formattedVND)")
                        .font(AppTypography.headline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.success)

                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("Hóa đơn", "Invoice"))
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(AppColors.accentRose)
                }
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let last = parts.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "S"
    }
}
