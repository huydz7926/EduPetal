import SwiftUI

/// Màn hình Chi tiết Lớp học (Module 3 — Class Management)
/// Gồm 4 mục rõ ràng: Tổng quan, Học sinh trong lớp, Lịch dạy và Học phí liên quan
public struct ClassDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State public var viewModel: ClassDetailViewModel
    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingAddStudentSheet: Bool = false
    @State private var isShowingMonthlyScheduleSheet: Bool = false
    @State private var isShowingSingleSessionSheet: Bool = false
    @State private var isNextStepBannerDismissed: Bool = false
    @State private var studentPendingUnenroll: StudentEntity? = nil
    @State private var studentForPaymentSheet: ClassStudentTuitionSummary? = nil

    private let classRepository: ClassRepositoryProtocol
    private let studentRepository: StudentRepositoryProtocol?
    private let scheduleRepository: ScheduleRepositoryProtocol?
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?

    public init(
        viewModel: ClassDetailViewModel,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol? = nil,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil
    ) {
        viewModel.scheduleRepository = scheduleRepository
        viewModel.financeRepository = financeRepository
        self._viewModel = State(initialValue: viewModel)
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
        self.gradeRepository = gradeRepository
        self.assignmentRepository = assignmentRepository
    }

    public var body: some View {
        mainScrollContent
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(viewModel.classGroup.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Sửa", "Edit")) {
                    isShowingEditSheet = true
                }
                .foregroundColor(AppColors.accentRose)
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            ClassEditView(classGroup: viewModel.classGroup) { updated in
                Task {
                    try? await classRepository.saveClass(updated)
                    await viewModel.loadMembers()
                }
            }
        }
        .sheet(isPresented: $isShowingAddStudentSheet) {
            ClassAddStudentSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingMonthlyScheduleSheet) {
            ClassMonthlyScheduleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingSingleSessionSheet) {
            singleSessionEditSheetView
        }
        .sheet(item: $studentForPaymentSheet) { item in
            recordPaymentSheetView(for: item)
        }
        .confirmationDialog(
            L("Kết thúc học sinh khỏi lớp?", "Remove student from class?"),
            isPresented: Binding(
                get: { studentPendingUnenroll != nil },
                set: { if !$0 { studentPendingUnenroll = nil } }
            ),
            titleVisibility: .visible,
            presenting: studentPendingUnenroll
        ) { student in
            Button(L("Kết thúc tham gia lớp", "End Class Enrollment"), role: .destructive) {
                Task {
                    await viewModel.unenrollStudent(id: student.id)
                    studentPendingUnenroll = nil
                }
            }
            Button(L("Hủy", "Cancel"), role: .cancel) {
                studentPendingUnenroll = nil
            }
        } message: { student in
            Text(
                L(
                    "Học sinh '\(student.fullName)' sẽ dừng tham gia lớp '\(viewModel.classGroup.name)'. Toàn bộ lịch sử buổi học và học phí trước đó vẫn được giữ nguyên.",
                    "Student '\(student.fullName)' will stop attending '\(viewModel.classGroup.name)'. All past session and tuition records are preserved."
                )
            )
        }
        // Hộp thoại 1: Xác nhận chắc chắn xóa khi lớp KHÔNG còn nợ học phí
        .alert(
            "Chắc chắn xóa lớp học?",
            isPresented: $viewModel.isShowingSimpleDeleteAlert
        ) {
            Button("Chắc chắn xóa", role: .destructive) {
                Task {
                    await viewModel.confirmDeleteArchivedClass(confirmPaidIfUnpaid: false)
                }
            }
            Button("Hủy", role: .cancel) {
                viewModel.isShowingSimpleDeleteAlert = false
            }
        } message: {
            Text("Xóa lớp '\(viewModel.classGroup.name)'? Không thể hoàn tác.")
        }
        // Hộp thoại 2: Lớp còn học phí chưa thanh toán -> nhắc chưa thanh toán & yêu cầu xác nhận đã thanh toán mới cho xóa
        .alert(
            "Còn học phí chưa thanh toán",
            isPresented: Binding(
                get: { viewModel.unpaidDeletePrompt != nil },
                set: { if !$0 { viewModel.unpaidDeletePrompt = nil } }
            ),
            presenting: viewModel.unpaidDeletePrompt
        ) { prompt in
            Button("Xác nhận đã thanh toán & Xóa lớp", role: .destructive) {
                Task {
                    await viewModel.confirmDeleteArchivedClass(confirmPaidIfUnpaid: true)
                }
            }
            Button("Chưa thanh toán (Hủy)", role: .cancel) {
                viewModel.unpaidDeletePrompt = nil
            }
        } message: { prompt in
            Text("Còn \(prompt.unpaidAmount.formattedVND) chưa thanh toán (\(prompt.unpaidChargeCount) khoản). Xác nhận đã thanh toán để xóa lớp.")
        }
        .alert(
            "Thông báo",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Đóng", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .onChange(of: viewModel.didDeleteClass) { _, deleted in
            if deleted {
                dismiss()
            }
        }
        .task {
            await viewModel.loadMembers()
        }
        .onAppear {
            Task {
                await viewModel.loadMembers()
            }
        }
    }

    private var mainScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                headerCardView
                    .padding(.horizontal, AppSpacing.md)

                sectionSegmentedBar
                    .padding(.horizontal, AppSpacing.md)

                Group {
                    switch viewModel.activeSection {
                    case .overview:
                        overviewSectionView
                    case .students:
                        studentsSectionView
                    case .schedule:
                        scheduleSectionView
                    case .finance:
                        financeSectionView
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
            .padding(.vertical, AppSpacing.md)
        }
    }

    private var singleSessionEditSheetView: some View {
        SessionEditView(
            classes: [viewModel.classGroup],
            existingSessions: viewModel.allSystemSessions,
            defaultDate: Date(),
            classRepository: classRepository,
            studentRepository: studentRepository,
            onSaveBatch: { sessions, participantIds in
                Task {
                    for s in sessions {
                        _ = await viewModel.createSingleSession(s, participantStudentIds: participantIds)
                    }
                }
            },
            onSave: { newSession, participantIds in
                Task {
                    _ = await viewModel.createSingleSession(newSession, participantStudentIds: participantIds)
                }
            }
        )
    }

    private func recordPaymentSheetView(for item: ClassStudentTuitionSummary) -> some View {
        RecordPaymentSheet(
            students: [item.student],
            preselectedStudentId: item.student.id,
            getOutstandingBalance: { _ in item.outstandingAmount },
            getUnpaidSessionItems: { _ in item.unpaidSessionDetails },
            onSave: { _, amount, paidAt, method, note in
                try await viewModel.recordPaymentForStudent(
                    studentId: item.student.id,
                    amount: amount,
                    paidAt: paidAt,
                    paymentMethod: method,
                    note: note
                )
            },
            onSaveWithSelection: { _, amount, paidAt, method, note, selectedChargeIds in
                try await viewModel.recordPaymentForStudent(
                    studentId: item.student.id,
                    amount: amount,
                    paidAt: paidAt,
                    paymentMethod: method,
                    note: note,
                    selectedChargeIds: selectedChargeIds
                )
            }
        )
    }

    // MARK: - Header & Segmented Bar

    private var headerCardView: some View {
        let trimmedSubject = viewModel.classGroup.subject.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(Color(hex: viewModel.classGroup.colorHex))
                        .frame(width: 14, height: 14)

                    if !trimmedSubject.isEmpty {
                        Text(trimmedSubject)
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    if viewModel.classGroup.isArchived {
                        StatusBadge(
                            title: L("Đã lưu trữ", "Archived"),
                            icon: "archivebox.fill",
                            textColor: AppColors.warning,
                            backgroundColor: AppColors.warningBackground
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        StatusBadge(
                            title: L("Đang mở", "Active"),
                            icon: "checkmark.circle.fill",
                            textColor: AppColors.success,
                            backgroundColor: AppColors.successBackground
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(viewModel.classGroup.name)
                    .font(AppTypography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.primaryText)

                Divider()
                    .background(AppColors.divider)

                HStack(spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Học sinh", "Students"))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(L("\(viewModel.enrolledStudents.count) học sinh", "\(viewModel.enrolledStudents.count) students"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Đơn giá mặc định", "Default Price"))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(viewModel.classGroup.defaultPricePerSession.formattedVND)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.accentRose)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(L("Thời lượng", "Duration"))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(L("\(viewModel.classGroup.sessionDurationMinutes) phút", "\(viewModel.classGroup.sessionDurationMinutes) mins"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
            }
        }
    }

    private var sectionSegmentedBar: some View {
        HStack(spacing: 8) {
            ForEach(ClassDetailSection.allCases) { sec in
                let isSelected = viewModel.activeSection == sec
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.activeSection = sec
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sec.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(sec.localizedTitle)
                            .font(AppTypography.caption1)
                            .fontWeight(isSelected ? .bold : .medium)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(isSelected ? AppColors.primaryPink : AppColors.surfaceCard)
                    )
                    .foregroundColor(isSelected ? .white : AppColors.primaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.divider, lineWidth: isSelected ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 1. Mục Tổng quan

    private var overviewSectionView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Hành động nhanh của lớp (khi lớp đang mở)
            if !viewModel.classGroup.isArchived {
                HStack(spacing: AppSpacing.xs) {
                    Button {
                        isShowingAddStudentSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                            Text(L("Thêm học sinh", "Add Student"))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.secondaryPink))
                        .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingMonthlyScheduleSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                            Text(L("Lịch theo tháng", "Monthly Schedule"))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.accentRose))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Buổi dạy tiếp theo
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Label(L("Buổi dạy tiếp theo", "Next Session"), systemImage: "calendar.badge.clock")
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)

                        Spacer()

                        Button {
                            viewModel.activeSection = .schedule
                        } label: {
                            Text(L("Xem lịch (\(viewModel.upcomingSessions.count))", "All (\(viewModel.upcomingSessions.count))"))
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)
                        }
                        .buttonStyle(.plain)
                    }

                    if let nextSession = viewModel.nextUpcomingSession {
                        sessionCardRow(nextSession)
                    } else {
                        HStack {
                            Text(L("Chưa có buổi dạy sắp tới.", "No upcoming sessions scheduled."))
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            if !viewModel.classGroup.isArchived {
                                Button {
                                    isShowingMonthlyScheduleSheet = true
                                } label: {
                                    Text(L("+ Lên lịch tháng", "+ Monthly Schedule"))
                                        .font(AppTypography.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.accentRose)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }

            // Tóm tắt Học phí liên quan của lớp
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Label(L("Học phí của lớp", "Class Tuition"), systemImage: "dollarsign.circle.fill")
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Button {
                            viewModel.activeSection = .finance
                        } label: {
                            Text(L("Chi tiết", "Details"))
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: AppSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Đã phát sinh", "Accrued"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalAccruedAmount.formattedVND)
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Đã thu", "Collected"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalCollectedAmount.formattedVND)
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.success)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("Còn nợ", "Outstanding"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalOutstandingAmount.formattedVND)
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.totalOutstandingAmount > 0 ? AppColors.error : AppColors.secondaryText)
                        }
                    }
                }
            }

            if !viewModel.classGroup.notes.isEmpty {
                AppCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Ghi chú lớp học", "Class Notes"))
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.secondaryText)
                        Text(viewModel.classGroup.notes)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Lưu trữ / Khôi phục / Xóa vĩnh viễn lớp
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L("Trạng thái & Lưu trữ", "Status & Archive"))
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.secondaryText)

                    if viewModel.classGroup.isArchived {
                        HStack(spacing: AppSpacing.xs) {
                            Button {
                                Task {
                                    await viewModel.restoreClass()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                    Text(L("Khôi phục lớp", "Restore Class"))
                                }
                                .font(AppTypography.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.successBackground))
                                .foregroundColor(AppColors.success)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                Task {
                                    await viewModel.requestDeleteArchivedClass()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                    Text(L("Xóa vĩnh viễn", "Delete Permanently"))
                                }
                                .font(AppTypography.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.errorBackground))
                                .foregroundColor(AppColors.error)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.archiveClass()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                Text(L("Lưu trữ lớp học", "Archive Class"))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.surfaceSubtle))
                            .foregroundColor(AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 2. Mục Học sinh trong lớp

    private var studentsSectionView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(L("Học sinh trong lớp (\(viewModel.enrolledStudents.count))", "Students in Class (\(viewModel.enrolledStudents.count))"))
                    .font(AppTypography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                if !viewModel.classGroup.isArchived {
                    Button {
                        isShowingAddStudentSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                            Text(L("Thêm học sinh", "Add Student"))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppColors.accentRose))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.enrolledStudents.isEmpty {
                AppCard {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "person.2.badge.gearshape")
                            .font(.system(size: 30))
                            .foregroundColor(AppColors.accentRose)
                        Text(L("Chưa có học sinh trong lớp", "No students in this class yet"))
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text(
                            L(
                                "Thêm học sinh có sẵn hoặc tạo học sinh mới ngay tại đây. Việc thêm học sinh vào lớp chưa làm phát sinh học phí.",
                                "Add existing students or create a new student right here. Adding students does not generate tuition charges yet."
                            )
                        )
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)

                        if !viewModel.classGroup.isArchived {
                            Button {
                                isShowingAddStudentSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text(L("Thêm học sinh vào lớp", "Add Student to Class"))
                                }
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppColors.accentRose))
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                }
            } else {
                ForEach(viewModel.enrolledStudents) { student in
                    studentMemberRow(student)
                }
            }
        }
    }

    // MARK: - 3. Mục Lịch dạy của lớp

    private var scheduleSectionView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if !viewModel.classGroup.isArchived {
                HStack(spacing: AppSpacing.xs) {
                    Button {
                        isShowingMonthlyScheduleSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                            Text(L("Thiết lập lịch theo tháng", "Monthly Schedule"))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.accentRose))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingSingleSessionSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text(L("Thêm buổi lẻ", "Single Session"))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.secondaryPink))
                        .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.classSessions.isEmpty {
                AppCard {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 30))
                            .foregroundColor(AppColors.accentRose)
                        Text(L("Chưa có lịch dạy cho lớp này", "No sessions scheduled yet"))
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text(
                            L(
                                "Thiết lập lịch theo tháng để tạo nhanh các buổi dạy định kỳ. Tạo lịch chưa làm phát sinh học phí cho đến khi xác nhận hoàn thành buổi dạy.",
                                "Set up a monthly schedule to generate recurring sessions. Scheduling sessions does not generate tuition charges until completed."
                            )
                        )
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)

                        if !viewModel.classGroup.isArchived {
                            Button {
                                isShowingMonthlyScheduleSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text(L("Thiết lập lịch theo tháng", "Set Up Monthly Schedule"))
                                }
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppColors.accentRose))
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                }
            } else {
                if !viewModel.upcomingSessions.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(L("Buổi dạy sắp tới (\(viewModel.upcomingSessions.count))", "Upcoming Sessions (\(viewModel.upcomingSessions.count))"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)

                        ForEach(viewModel.upcomingSessions) { session in
                            sessionCardRow(session)
                        }
                    }
                }

                if !viewModel.historySessions.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(L("Lịch sử buổi dạy (\(viewModel.historySessions.count))", "Session History (\(viewModel.historySessions.count))"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.secondaryText)

                        ForEach(viewModel.historySessions) { session in
                            sessionCardRow(session)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionCardRow(_ session: TeachingSessionEntity) -> some View {
        if let schRepo = scheduleRepository,
           let stuRepo = studentRepository,
           let finRepo = financeRepository {
            NavigationLink {
                SessionDetailView(
                    viewModel: SessionDetailViewModel(
                        session: session,
                        scheduleRepository: schRepo,
                        classRepository: classRepository,
                        studentRepository: stuRepo,
                        financeRepository: finRepo
                    ),
                    scheduleRepository: schRepo,
                    classRepository: classRepository,
                    studentRepository: stuRepo,
                    financeRepository: finRepo,
                    gradeRepository: gradeRepository,
                    assignmentRepository: assignmentRepository
                )
            } label: {
                sessionCardContent(session, showChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            sessionCardContent(session, showChevron: false)
        }
    }

    private func sessionCardContent(_ session: TeachingSessionEntity, showChevron: Bool) -> some View {
        AppCard {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.primaryText)

                    Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened)) • \(L("Chạm để điểm danh / hoàn thành", "Tap to take attendance / complete"))")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                switch session.status {
                case .scheduled:
                    StatusBadge(
                        title: L("Sắp dạy", "Scheduled"),
                        icon: "clock.fill",
                        textColor: AppColors.info,
                        backgroundColor: AppColors.infoBackground
                    )
                case .completed:
                    StatusBadge(
                        title: L("Hoàn thành", "Completed"),
                        icon: "checkmark.circle.fill",
                        textColor: AppColors.success,
                        backgroundColor: AppColors.successBackground
                    )
                case .cancelled:
                    StatusBadge(
                        title: L("Đã hủy", "Cancelled"),
                        icon: "xmark.circle.fill",
                        textColor: AppColors.error,
                        backgroundColor: AppColors.errorBackground
                    )
                }

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                }
            }
        }
    }

    // MARK: - 4. Mục Học phí liên quan của lớp

    private var financeSectionView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(L("Tổng hợp học phí lớp '\(viewModel.classGroup.name)'", "Tuition Summary for '\(viewModel.classGroup.name)'"))
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.primaryText)

                    HStack(spacing: AppSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Đã phát sinh", "Accrued"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalAccruedAmount.formattedVND)
                                .font(AppTypography.headline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Đã thu", "Collected"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalCollectedAmount.formattedVND)
                                .font(AppTypography.headline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.success)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("Còn nợ", "Outstanding"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Text(viewModel.totalOutstandingAmount.formattedVND)
                                .font(AppTypography.headline)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.totalOutstandingAmount > 0 ? AppColors.error : AppColors.secondaryText)
                        }
                    }

                    Text(L("Học phí chỉ phát sinh khi buổi dạy được xác nhận hoàn thành và học sinh có mặt.", "Tuition only accrues when a session is marked completed and the student attended."))
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            // Khoản phải thu theo từng học sinh
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("Theo học sinh trong lớp", "By Student in Class"))
                    .font(AppTypography.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.primaryText)

                if viewModel.studentTuitionSummaries.isEmpty {
                    AppCard {
                        Text(L("Chưa có học sinh hoặc khoản thu nào phát sinh cho lớp này.", "No student tuition records for this class yet."))
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.sm)
                    }
                } else {
                    ForEach(viewModel.studentTuitionSummaries) { summary in
                        AppCard {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                HStack {
                                    Text(summary.student.fullName)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)

                                    Spacer()

                                    Text(L("\(summary.completedSessionsCount) buổi có mặt", "\(summary.completedSessionsCount) attended"))
                                        .font(AppTypography.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(AppColors.surfaceSubtle))
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                HStack(spacing: AppSpacing.sm) {
                                    Text(L("Phát sinh: \(summary.accruedAmount.formattedVND)", "Accrued: \(summary.accruedAmount.formattedVND)"))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)

                                    Text(L("Đã thu: \(summary.collectedAmount.formattedVND)", "Paid: \(summary.collectedAmount.formattedVND)"))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.success)

                                    Spacer()

                                    Text(L("Nợ: \(summary.outstandingAmount.formattedVND)", "Owed: \(summary.outstandingAmount.formattedVND)"))
                                        .font(AppTypography.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(summary.outstandingAmount > 0 ? AppColors.error : AppColors.secondaryText)
                                }

                                if summary.outstandingAmount > 0 {
                                    Button {
                                        studentForPaymentSheet = summary
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "banknote.fill")
                                            Text(L("Thu học phí (\(summary.outstandingAmount.formattedVND))", "Record Payment (\(summary.outstandingAmount.formattedVND))"))
                                        }
                                        .font(AppTypography.caption1)
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(RoundedRectangle(cornerRadius: AppRadius.sm).fill(AppColors.accentRose))
                                        .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                }
            }

            // Lịch sử thu tiền của lớp
            if !viewModel.classPaymentHistory.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L("Lịch sử thu tiền (\(viewModel.classPaymentHistory.count))", "Payment History (\(viewModel.classPaymentHistory.count))"))
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.primaryText)

                    ForEach(viewModel.classPaymentHistory) { item in
                        AppCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.student.fullName)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("\(item.paidAt.formatted(date: .abbreviated, time: .shortened)) • \(item.paymentMethod)")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                                Spacer()
                                Text("+\(item.amountAllocatedToClass.formattedVND)")
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.success)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func studentMemberRow(_ student: StudentEntity) -> some View {
        AppCard {
            HStack(spacing: AppSpacing.sm) {
                if let stuRepo = studentRepository {
                    NavigationLink {
                        StudentDetailView(
                            viewModel: StudentDetailViewModel(
                                student: student,
                                studentRepository: stuRepo,
                                classRepository: classRepository,
                                scheduleRepository: scheduleRepository,
                                gradeRepository: gradeRepository,
                                assignmentRepository: assignmentRepository,
                                financeRepository: financeRepository
                            )
                        )
                    } label: {
                        studentMemberContent(student)
                    }
                    .buttonStyle(.plain)
                } else {
                    studentMemberContent(student)
                }

                if !viewModel.classGroup.isArchived {
                    Menu {
                        Button(role: .destructive) {
                            studentPendingUnenroll = student
                        } label: {
                            Label(L("Kết thúc học lớp này", "End Class Enrollment"), systemImage: "person.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(4)
                    }
                }
            }
        }
    }

    private func studentMemberContent(_ student: StudentEntity) -> some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(
                avatarPath: student.avatarPath,
                initials: String(student.fullName.prefix(1)).uppercased(),
                size: 42,
                showBorder: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(student.fullName)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                if let customPrice = student.defaultPricePerSession, customPrice > 0 {
                    Text(L("Đơn giá: \(customPrice.formattedVND)/buổi (Giá riêng)", "Price: \(customPrice.formattedVND)/session (Custom)"))
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.accentRose)
                        .fontWeight(.medium)
                } else {
                    Text(L("Đơn giá: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/buổi (Theo lớp)", "Price: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/session (Class default)"))
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Sheet Thêm học sinh vào lớp (Chọn học sinh có sẵn hoặc Tạo học sinh mới)

public struct ClassAddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var viewModel: ClassDetailViewModel

    private enum Mode: Int, CaseIterable {
        case existing = 0
        case createNew = 1
    }

    @State private var mode: Mode = .existing
    @State private var searchQuery: String = ""
    @State private var selectedStudentIds: Set<UUID> = []

    // Form tạo học sinh mới gọn nhẹ
    @State private var newFullName: String = ""
    @State private var newPhone: String = ""
    @State private var newParentPhone: String = ""
    @State private var hasCustomPrice: Bool = false
    @State private var customPrice: Int64 = 150_000
    @State private var newNotes: String = ""
    @State private var isSubmitting: Bool = false

    public init(viewModel: ClassDetailViewModel) {
        self.viewModel = viewModel
    }

    private var filteredAvailableStudents: [StudentEntity] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.availableStudentsToEnroll }
        return viewModel.availableStudentsToEnroll.filter { s in
            s.fullName.lowercased().contains(q) ||
            s.phoneNumber.lowercased().contains(q) ||
            s.parentPhone.lowercased().contains(q)
        }
    }

    private var isNewStudentValid: Bool {
        !newFullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasCustomPrice || customPrice > 0)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("Cách thêm học sinh", "Add Mode"), selection: $mode) {
                    Text(L("Chọn học sinh có sẵn (\(viewModel.availableStudentsToEnroll.count))", "Existing (\(viewModel.availableStudentsToEnroll.count))"))
                        .tag(Mode.existing)
                    Text(L("Tạo học sinh mới", "Create New"))
                        .tag(Mode.createNew)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)

                if mode == .existing {
                    existingStudentsView
                } else {
                    createNewStudentFormView
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Thêm học sinh vào lớp", "Add Student to Class"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Hủy", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .existing {
                        Button(
                            selectedStudentIds.isEmpty
                            ? L("Thêm", "Add")
                            : L("Thêm (\(selectedStudentIds.count))", "Add (\(selectedStudentIds.count))")
                        ) {
                            guard !isSubmitting, !selectedStudentIds.isEmpty else { return }
                            isSubmitting = true
                            Task {
                                let ok = await viewModel.enrollStudents(ids: Array(selectedStudentIds))
                                isSubmitting = false
                                if ok {
                                    dismiss()
                                }
                            }
                        }
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.accentRose)
                        .disabled(selectedStudentIds.isEmpty || isSubmitting || viewModel.isSavingEnrollment)
                    } else {
                        Button(L("Tạo & Thêm", "Create & Add")) {
                            guard !isSubmitting, isNewStudentValid else { return }
                            isSubmitting = true
                            let student = StudentEntity(
                                fullName: newFullName.trimmingCharacters(in: .whitespacesAndNewlines),
                                phoneNumber: newPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                                parentPhone: newParentPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                                defaultPricePerSession: hasCustomPrice ? customPrice : nil,
                                notes: newNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            Task {
                                let ok = await viewModel.createAndEnrollStudent(student)
                                isSubmitting = false
                                if ok {
                                    dismiss()
                                }
                            }
                        }
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.accentRose)
                        .disabled(!isNewStudentValid || isSubmitting || viewModel.isSavingEnrollment)
                    }
                }
            }
            .onAppear {
                if viewModel.availableStudentsToEnroll.isEmpty {
                    mode = .createNew
                }
                customPrice = viewModel.classGroup.defaultPricePerSession
            }
        }
    }

    @ViewBuilder
    private var existingStudentsView: some View {
        if viewModel.availableStudentsToEnroll.isEmpty {
            VStack(spacing: AppSpacing.md) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 42))
                    .foregroundColor(AppColors.accentRose)
                Text(L("Chưa có học sinh nào ngoài lớp này", "No other existing students available"))
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                Text(L("Bạn có thể tạo hồ sơ học sinh mới và thêm thẳng vào lớp '\(viewModel.classGroup.name)'.", "Create a new student profile and add them directly to '\(viewModel.classGroup.name)'."))
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)

                Button {
                    mode = .createNew
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(L("Chuyển sang Tạo học sinh mới", "Create New Student"))
                    }
                    .font(AppTypography.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppColors.accentRose))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.secondaryText)
                    TextField(L("Tìm học sinh theo tên, SĐT...", "Search student by name, phone..."), text: $searchQuery)
                        .font(AppTypography.body)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.surfaceSubtle))
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xs)

                List(filteredAvailableStudents) { student in
                    let isSelected = selectedStudentIds.contains(student.id)
                    Button {
                        if isSelected {
                            selectedStudentIds.remove(student.id)
                        } else {
                            selectedStudentIds.insert(student.id)
                        }
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(isSelected ? AppColors.accentRose : AppColors.tertiaryText)

                            AvatarView(
                                avatarPath: student.avatarPath,
                                initials: String(student.fullName.prefix(1)).uppercased(),
                                size: 38,
                                showBorder: false
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(student.fullName)
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)

                                if let custom = student.defaultPricePerSession, custom > 0 {
                                    Text(L("Giá riêng: \(custom.formattedVND)/buổi", "Custom: \(custom.formattedVND)/session"))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.accentRose)
                                } else {
                                    Text(L("Theo giá lớp: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/buổi", "Class price: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/session"))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private var createNewStudentFormView: some View {
        Form {
            Section {
                TextField(L("Họ và tên học sinh *", "Student Full Name *"), text: $newFullName)
                    .font(AppTypography.body)
            } header: {
                Text(L("Thông tin bắt buộc", "Required Info"))
            } footer: {
                Text(L("Học sinh mới sẽ được tự động thêm vào lớp '\(viewModel.classGroup.name)'.", "The new student will be automatically enrolled in '\(viewModel.classGroup.name)'."))
                    .font(AppTypography.caption2)
            }

            Section(L("Liên hệ & Học phí (Tùy chọn)", "Contact & Tuition (Optional)")) {
                TextField(L("Số điện thoại học sinh", "Student Phone"), text: $newPhone)
                    #if canImport(UIKit)
                    .keyboardType(.phonePad)
                    #endif

                TextField(L("Số điện thoại phụ huynh", "Parent Phone"), text: $newParentPhone)
                    #if canImport(UIKit)
                    .keyboardType(.phonePad)
                    #endif

                Toggle(L("Thiết lập đơn giá riêng", "Custom Session Price"), isOn: $hasCustomPrice)
                    .tint(AppColors.primaryPink)

                if hasCustomPrice {
                    CurrencyTextField(L("Đơn giá mỗi buổi", "Price per Session"), placeholder: "150.000", value: $customPrice)
                    if customPrice <= 0 {
                        Label(L("Đơn giá riêng phải lớn hơn 0 đ.", "Custom price must be greater than 0."), systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                    }
                } else {
                    Text(L("Áp dụng đơn giá mặc định của lớp: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/buổi.", "Uses class default price: \(viewModel.classGroup.defaultPricePerSession.formattedVND)/session."))
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.secondaryText)
                }

                TextField(L("Ghi chú (tùy chọn)", "Notes (optional)"), text: $newNotes)
            }
        }
    }
}

// MARK: - Sheet Thiết lập Lịch theo tháng cho Lớp học

public struct ClassMonthlyScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var viewModel: ClassDetailViewModel

    @State private var selectedMonthOffset: Int = 0
    @State private var selectedDays: Set<DayOfWeek> = [.monday, .wednesday, .friday]
    @State private var sessionStartTime: Date = {
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comp.hour = 18
        comp.minute = 0
        return Calendar.current.date(from: comp) ?? Date()
    }()
    @State private var sessionEndTime: Date = {
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comp.hour = 19
        comp.minute = 30
        return Calendar.current.date(from: comp) ?? Date().addingTimeInterval(90 * 60)
    }()
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isSubmitting: Bool = false

    public init(viewModel: ClassDetailViewModel) {
        self.viewModel = viewModel
    }

    private var targetMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: selectedMonthOffset, to: Date()) ?? Date()
    }

    private var previewSessions: [TeachingSessionEntity] {
        viewModel.previewMonthlySessions(
            selectedDays: selectedDays,
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: sessionStartTime,
            sessionEndTime: sessionEndTime
        )
    }

    private var overlaps: [(newSession: TeachingSessionEntity, conflictWith: TeachingSessionEntity)] {
        viewModel.checkOverlaps(for: previewSessions)
    }

    private var isTimeValid: Bool {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: sessionStartTime)
        let e = cal.dateComponents([.hour, .minute], from: sessionEndTime)
        return ((e.hour ?? 0) * 60 + (e.minute ?? 0)) > ((s.hour ?? 0) * 60 + (s.minute ?? 0))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(L("1. Chọn tháng & khoảng ngày", "1. Month & Date Range")) {
                    HStack {
                        Text(L("Tháng áp dụng", "Target Month"))
                            .font(AppTypography.body)
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                if selectedMonthOffset > 0 {
                                    selectedMonthOffset -= 1
                                    syncMonthDates(offset: selectedMonthOffset)
                                }
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(selectedMonthOffset > 0 ? AppColors.accentRose : AppColors.tertiaryText)
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedMonthOffset <= 0)

                            Text(monthTitle(for: targetMonthDate))
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.accentRose)
                                .frame(minWidth: 100, alignment: .center)

                            Button {
                                selectedMonthOffset += 1
                                syncMonthDates(offset: selectedMonthOffset)
                            } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(AppColors.accentRose)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    DatePicker(L("Từ ngày", "Start Date"), selection: $startDate, displayedComponents: .date)
                    DatePicker(L("Đến ngày", "End Date"), selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section(L("2. Chọn thứ & khung giờ học", "2. Weekdays & Time")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Các thứ trong tuần", "Days of Week"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)

                        HStack(spacing: 6) {
                            ForEach(DayOfWeek.allCases.sorted()) { day in
                                let isSelected = selectedDays.contains(day)
                                Button {
                                    if isSelected {
                                        selectedDays.remove(day)
                                    } else {
                                        selectedDays.insert(day)
                                    }
                                } label: {
                                    Text(day.shortName)
                                        .font(AppTypography.caption1)
                                        .fontWeight(isSelected ? .bold : .medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                                .fill(isSelected ? AppColors.accentRose : AppColors.surfaceSubtle)
                                        )
                                        .foregroundColor(isSelected ? .white : AppColors.primaryText)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker(L("Giờ bắt đầu", "Start Time"), selection: $sessionStartTime, displayedComponents: .hourAndMinute)
                        .onChange(of: sessionStartTime) { _, newStart in
                            sessionEndTime = newStart.addingTimeInterval(TimeInterval(viewModel.classGroup.sessionDurationMinutes * 60))
                        }

                    DatePicker(L("Giờ kết thúc", "End Time"), selection: $sessionEndTime, displayedComponents: .hourAndMinute)

                    if !isTimeValid {
                        Label(L("Giờ kết thúc phải sau giờ bắt đầu.", "End time must be after start time."), systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                    }
                }

                Section {
                    if !overlaps.isEmpty {
                        Label(
                            L("Có \(overlaps.count) buổi trùng giờ với lịch đã có. Bạn hãy kiểm tra trước khi lưu.", "\(overlaps.count) session(s) overlap with existing schedule."),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.warning)
                    }

                    if previewSessions.isEmpty {
                        Text(L("Chưa có buổi học mới nào để tạo (hoặc các buổi trong khung giờ này đã được tạo trước đó).", "No new sessions to create in this range."))
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(previewSessions.prefix(12)) { s in
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(AppColors.accentRose)
                                Text(s.startTime.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(s.startTime.formatted(date: .omitted, time: .shortened)) – \(s.endTime.formatted(date: .omitted, time: .shortened))")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        if previewSessions.count > 12 {
                            Text(L("... và \(previewSessions.count - 12) buổi khác", "... and \(previewSessions.count - 12) more sessions"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                } header: {
                    Text(L("3. Xem trước (\(previewSessions.count) buổi mới)", "3. Preview (\(previewSessions.count) new sessions)"))
                } footer: {
                    Text(L("Tất cả \(viewModel.enrolledStudents.count) học sinh đang tham gia lớp sẽ được tự động thêm vào danh sách điểm danh chờ của từng buổi. Tạo lịch chưa làm phát sinh học phí.", "All \(viewModel.enrolledStudents.count) active students will be added to pending attendance. Scheduling does not generate tuition charges."))
                        .font(AppTypography.caption2)
                }
            }
            .navigationTitle(L("Thiết lập lịch theo tháng", "Monthly Schedule"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Hủy", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        previewSessions.isEmpty
                        ? L("Lưu", "Save")
                        : L("Lưu (\(previewSessions.count) buổi)", "Save (\(previewSessions.count))")
                    ) {
                        guard !isSubmitting, !previewSessions.isEmpty, isTimeValid else { return }
                        isSubmitting = true
                        Task {
                            let count = await viewModel.createMonthlySchedule(
                                selectedDays: selectedDays,
                                startDate: startDate,
                                endDate: endDate,
                                sessionStartTime: sessionStartTime,
                                sessionEndTime: sessionEndTime
                            )
                            isSubmitting = false
                            if count > 0 {
                                viewModel.activeSection = .schedule
                                dismiss()
                            }
                        }
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.accentRose)
                    .disabled(previewSessions.isEmpty || !isTimeValid || isSubmitting || viewModel.isSavingSchedule)
                }
            }
            .onAppear {
                let durationSecs = TimeInterval(viewModel.classGroup.sessionDurationMinutes * 60)
                sessionEndTime = sessionStartTime.addingTimeInterval(durationSecs)
                syncMonthDates(offset: 0)
            }
        }
    }

    private func syncMonthDates(offset: Int) {
        let cal = Calendar.current
        let now = Date()
        let monthDate = cal.date(byAdding: .month, value: offset, to: now) ?? now
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        let firstOfMonth = cal.date(from: comps) ?? now
        let lastOfMonth: Date
        if let nextMonth = cal.date(byAdding: .month, value: 1, to: firstOfMonth),
           let lastDay = cal.date(byAdding: .day, value: -1, to: nextMonth) {
            lastOfMonth = lastDay
        } else {
            lastOfMonth = firstOfMonth
        }

        if offset == 0 {
            startDate = max(cal.startOfDay(for: now), firstOfMonth)
        } else {
            startDate = firstOfMonth
        }
        endDate = max(startDate, lastOfMonth)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "MM/yyyy"
        return "Tháng \(formatter.string(from: date))"
    }
}
