import SwiftUI

/// Màn hình Chi tiết Buổi học & Điểm danh (Module 4 — Teaching Sessions)
public struct SessionDetailView: View {
    @State public var viewModel: SessionDetailViewModel
    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingCompleteAlert: Bool = false
    @State private var isShowingCameraView: Bool = false
    @State private var shouldCompleteAfterCamera: Bool = false
    @State private var isShowingEnrollStudentSheet: Bool = false
    @State private var isShowingCreateStudentSheet: Bool = false
    @State private var selectedAttachmentForDetail: SessionAttachmentEntity? = nil
    @State private var lessonNotesText: String = ""
    @State private var homeworkText: String = ""

    private let scheduleRepository: ScheduleRepositoryProtocol
    private let classRepository: ClassRepositoryProtocol
    private let studentRepository: StudentRepositoryProtocol?
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?

    public init(
        viewModel: SessionDetailViewModel,
        scheduleRepository: ScheduleRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.scheduleRepository = scheduleRepository
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.financeRepository = financeRepository
        self.gradeRepository = gradeRepository
        self.assignmentRepository = assignmentRepository
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                // MARK: - Completed Session Banner
                if viewModel.session.status == .completed {
                    completedBanner
                }

                // MARK: - Session Info Header Card
                sessionHeaderCard

                // MARK: - Attendance Section (Thông tin học sinh & Tình trạng hoàn thành)
                attendanceSection

                // MARK: - Proof Photo Attachments Section
                attachmentsSection

                // MARK: - Lesson Notes & Homework
                notesSection

                // MARK: - Complete Session Button (Chỉ hiển thị khi chưa hoàn thành và chưa hủy)
                if viewModel.session.status == .scheduled {
                    completeSessionButton
                }
            }
            .padding(AppSpacing.md)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Chi tiết buổi học")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if viewModel.session.status == .scheduled {
                ToolbarItem(placement: .primaryAction) {
                    Button("Sửa") {
                        isShowingEditSheet = true
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accentRose)
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            SessionEditView(
                session: viewModel.session,
                classes: viewModel.allClasses.isEmpty ? (viewModel.classGroup != nil ? [viewModel.classGroup!] : []) : viewModel.allClasses,
                existingSessions: viewModel.existingSessions,
                classRepository: classRepository,
                studentRepository: studentRepository ?? viewModel.studentRepository,
                onSaveSeriesOption: { updated, updateFuture, _ in
                    Task {
                        if updateFuture {
                            try? await viewModel.updateSeriesFutureSessions(from: updated)
                        } else {
                            try? await viewModel.updateSingleSessionDetached(updated)
                        }
                    }
                },
                onSave: { updated, _ in
                    Task {
                        try? await viewModel.updateSession(updated)
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingEnrollStudentSheet) {
            enrollStudentSheet
        }
        .sheet(isPresented: $isShowingCreateStudentSheet) {
            StudentEditView { newStudent in
                Task {
                    try? await viewModel.studentRepository.saveStudent(newStudent)
                    await viewModel.enrollStudentToSessionClass(newStudent)
                }
            }
        }
        .alert("Cảnh báo điểm danh", isPresented: Binding(
            get: { viewModel.validationAlertMessage != nil },
            set: { if !$0 { viewModel.validationAlertMessage = nil } }
        )) {
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            if let msg = viewModel.validationAlertMessage {
                Text(msg)
            }
        }
        .alert("Cần ảnh minh chứng", isPresented: $viewModel.isPhotoRequiredAlertShowing) {
            Button("Chụp ảnh ngay") {
                shouldCompleteAfterCamera = true
                isShowingCameraView = true
            }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Buổi học có học sinh tham gia cần ít nhất 1 ảnh minh chứng trước khi hoàn thành.")
        }
        .alert(
            "Xác nhận điều chỉnh hoàn thành",
            isPresented: Binding(
                get: { viewModel.pendingPostCompletionAdjustment != nil },
                set: { if !$0 { viewModel.pendingPostCompletionAdjustment = nil } }
            ),
            presenting: viewModel.pendingPostCompletionAdjustment
        ) { adjustment in
            Button("Xác nhận điều chỉnh", role: adjustment.newStatus == .present ? nil : .destructive) {
                Task {
                    await viewModel.confirmPostCompletionAdjustment()
                }
            }
            Button("Hủy", role: .cancel) {
                viewModel.pendingPostCompletionAdjustment = nil
            }
        } message: { adjustment in
            if adjustment.newStatus == .present {
                Text("Buổi học đã hoàn thành. Đổi trạng thái của \(adjustment.student.fullName) sang Đã hoàn thành sẽ phát sinh khoản học phí \(adjustment.unitPrice.formattedVND) cho buổi học này. Bạn có chắc chắn muốn điều chỉnh không?")
            } else {
                Text("Buổi học đã hoàn thành. Đổi trạng thái của \(adjustment.student.fullName) sang Nghỉ sẽ hủy khoản học phí chưa thanh toán (\(adjustment.unitPrice.formattedVND)) của buổi này. Bạn có chắc chắn muốn điều chỉnh không?")
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCameraView) {
            TeachingProofCameraView(
                session: viewModel.session,
                className: viewModel.classGroup?.name ?? "Lớp học"
            ) { fileName, note in
                Task { @MainActor in
                    try? await viewModel.addPhotoAttachment(filePath: fileName, caption: note)
                    if !note.isEmpty && lessonNotesText.isEmpty {
                        lessonNotesText = note
                    }
                    if shouldCompleteAfterCamera {
                        shouldCompleteAfterCamera = false
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        viewModel.requestCompleteSession()
                    }
                }
            }
        }
        #else
        .sheet(isPresented: $isShowingCameraView) {
            TeachingProofCameraView(
                session: viewModel.session,
                className: viewModel.classGroup?.name ?? "Lớp học"
            ) { fileName, note in
                Task { @MainActor in
                    try? await viewModel.addPhotoAttachment(filePath: fileName, caption: note)
                    if !note.isEmpty && lessonNotesText.isEmpty {
                        lessonNotesText = note
                    }
                    if shouldCompleteAfterCamera {
                        shouldCompleteAfterCamera = false
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        viewModel.requestCompleteSession()
                    }
                }
            }
        }
        #endif
        .sheet(item: $selectedAttachmentForDetail) { att in
            ProofPhotoDetailView(
                attachment: att,
                sessionTitle: viewModel.session.title,
                className: viewModel.classGroup?.name ?? "Lớp học"
            )
        }
        .sheet(isPresented: $viewModel.isShowingCompletionSummary) {
            completionSummarySheet
        }
        .task {
            await viewModel.loadData()
            lessonNotesText = viewModel.session.userDisplayNotes
            homeworkText = viewModel.session.homeworkAssigned
        }
    }

    // MARK: - Subviews

    private var sessionHeaderCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    if let c = viewModel.classGroup {
                        Text(c.name)
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: c.colorHex).opacity(0.15)))
                            .foregroundColor(Color(hex: c.colorHex))
                    }

                    Spacer()

                    statusBadge(for: viewModel.session.status)
                }

                Text(viewModel.session.title)
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.primaryText)

                Divider()
                    .background(AppColors.divider)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thời gian")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)

                        Text("\(viewModel.session.startTime.formatted(date: .abbreviated, time: .shortened)) - \(viewModel.session.endTime.formatted(date: .omitted, time: .shortened))")
                            .font(AppTypography.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.primaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Thời lượng")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)

                        Text("\(viewModel.session.durationMinutes) phút")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.accentRose)
                    }
                }
            }
        }
    }

    // MARK: - Attendance & Student Completion Section

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Tiêu đề khu vực xác nhận hoàn thành từng học sinh
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .foregroundColor(AppColors.accentRose)
                    Text("Xác nhận từng học sinh (\(viewModel.students.count))")
                        .font(AppTypography.title3)
                        .foregroundColor(AppColors.primaryText)
                }

                Spacer()
            }

            // Thẻ Tổng quan Tình trạng hoàn thành điểm danh & buổi học
            attendanceCompletionSummaryCard

            if viewModel.students.isEmpty {
                AppCard {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.accentRose)

                        Text(L("Lớp chưa có học sinh.", "No students in this class."))
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.secondaryText)

                        Button {
                            isShowingEnrollStudentSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.plus")
                                Text(L("Thêm học sinh vào lớp", "Add Student to Class"))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(AppColors.primaryPink))
                            .foregroundColor(AppColors.onPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xs)
                }
            } else {
                // Danh sách thẻ Thông tin học sinh & Tình trạng hoàn thành
                VStack(spacing: AppSpacing.sm) {
                    ForEach(viewModel.students) { student in
                        studentAttendanceCard(for: student)
                    }
                }
            }
        }
    }

    private var attendanceCompletionSummaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: completionStatusIcon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(completionStatusColor)

                        Text(completionStatusTitle)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                    }

                    Spacer()

                    Text("\(viewModel.markedCount)/\(viewModel.students.count) đã điểm danh")
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(completionStatusColor.opacity(0.14)))
                        .foregroundColor(completionStatusColor)
                }

                // Thanh tiến trình điểm danh
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.surfaceSubtle)
                            .frame(height: 8)

                        Capsule()
                            .fill(completionStatusColor)
                            .frame(width: max(0, geo.size.width * viewModel.completionProgress), height: 8)
                            .animation(.easeInOut(duration: 0.25), value: viewModel.completionProgress)
                    }
                }
                .frame(height: 8)

                // Thống kê chi tiết trạng thái từng học sinh
                HStack(spacing: AppSpacing.xs) {
                    attendanceCounterPill(
                        label: "Đã hoàn thành",
                        count: viewModel.presentCount,
                        color: AppColors.success,
                        bg: AppColors.successBackground
                    )

                    attendanceCounterPill(
                        label: "Nghỉ",
                        count: viewModel.absentCount,
                        color: AppColors.error,
                        bg: AppColors.errorBackground
                    )

                    attendanceCounterPill(
                        label: "Chưa xác nhận",
                        count: viewModel.pendingCount,
                        color: viewModel.pendingCount > 0 ? AppColors.warning : AppColors.secondaryText,
                        bg: viewModel.pendingCount > 0 ? AppColors.warningBackground : AppColors.surfaceSubtle
                    )

                    Spacer()
                }
            }
        }
    }

    private func studentAttendanceCard(for student: StudentEntity) -> some View {
        let att = viewModel.attendance(for: student.id)
        let currentStatus = att?.status ?? .pending
        let effectivePrice = viewModel.effectivePrice(for: student)
        let isCustom = viewModel.isCustomPrice(for: student)
        let charge = viewModel.charge(for: student.id)

        return AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // 1. Thông tin học sinh (Avatar, Họ tên, SĐT/PH, Đơn giá, Liên kết Hồ sơ)
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    AvatarView(
                        avatarPath: student.avatarPath,
                        initials: initials(for: student.fullName),
                        size: 46,
                        showBorder: true
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(student.fullName)
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)

                            NavigationLink {
                                StudentDetailView(
                                    viewModel: StudentDetailViewModel(
                                        student: student,
                                        studentRepository: studentRepository ?? viewModel.studentRepository,
                                        classRepository: classRepository,
                                        scheduleRepository: scheduleRepository,
                                        gradeRepository: gradeRepository,
                                        assignmentRepository: assignmentRepository,
                                        financeRepository: financeRepository
                                    )
                                )
                            } label: {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.accentRose)
                            }
                            .buttonStyle(.plain)
                        }

                        // SĐT Học sinh / Phụ huynh / Lớp học
                        HStack(spacing: 8) {
                            if !student.phoneNumber.isEmpty {
                                Label(student.phoneNumber, systemImage: "phone.fill")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            } else if !student.parentPhone.isEmpty {
                                Label("PH: \(student.parentPhone)", systemImage: "person.2.fill")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            } else {
                                Label(viewModel.classGroup?.name ?? "Học sinh trong lớp", systemImage: "graduationcap.fill")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }

                        // Đơn giá học phí của học sinh (ưu tiên snapshot nếu buổi học đã phát sinh khoản thu)
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.accentRose)
                            Text("Đơn giá: \((charge?.unitPriceSnapshot ?? effectivePrice).formattedVND)/buổi")
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)
                            Text(charge != nil ? "(Giá chốt)" : (isCustom ? "(Giá riêng)" : "(Theo lớp)"))
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }

                    Spacer()

                    // Huy hiệu trạng thái điểm danh
                    switch currentStatus {
                    case .present:
                        StatusBadge.attendancePresent()
                    case .absent:
                        StatusBadge.attendanceAbsent()
                    case .excused:
                        StatusBadge.attendanceExcused()
                    case .pending:
                        StatusBadge.attendancePending()
                    }
                }

                // 2. Dòng tóm tắt học phí buổi này (không lặp lại trạng thái đã có trên huy hiệu)
                HStack {
                    Image(systemName: "dongsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(currentStatus == .present ? AppColors.success : AppColors.secondaryText)

                    Text("Học phí buổi này:")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)

                    if currentStatus == .present {
                        Text("+\((charge?.amount ?? effectivePrice).formattedVND)")
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.success)
                    } else if currentStatus == .absent || currentStatus == .excused {
                        Text("0 ₫ (Nghỉ)")
                            .font(AppTypography.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        Text("Dự kiến \(effectivePrice.formattedVND)")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                    }

                    Spacer()

                    if let charge {
                        Text(charge.status.displayName)
                            .font(AppTypography.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    charge.status == .paid
                                        ? AppColors.successBackground
                                        : (charge.status == .partiallyPaid ? AppColors.warningBackground : AppColors.errorBackground)
                                )
                            )
                            .foregroundColor(
                                charge.status == .paid
                                    ? AppColors.success
                                    : (charge.status == .partiallyPaid ? AppColors.warning : AppColors.error)
                            )
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(AppColors.surfaceSubtle)
                )

                // 3. Các nút chọn trạng thái hoàn thành của từng học sinh
                if viewModel.session.status == .scheduled {
                    HStack(spacing: AppSpacing.xs) {
                        attendanceToggleButton(
                            title: "Hoàn thành",
                            icon: "checkmark.circle.fill",
                            isSelected: currentStatus == .present,
                            activeColor: AppColors.success,
                            activeBg: AppColors.successBackground
                        ) {
                            Task {
                                await viewModel.markAttendance(studentId: student.id, status: .present)
                            }
                        }

                        attendanceToggleButton(
                            title: "Nghỉ",
                            icon: "xmark.circle.fill",
                            isSelected: currentStatus == .absent,
                            activeColor: AppColors.error,
                            activeBg: AppColors.errorBackground
                        ) {
                            Task {
                                await viewModel.markAttendance(studentId: student.id, status: .absent)
                            }
                        }

                        attendanceToggleButton(
                            title: "Có phép",
                            icon: "info.circle.fill",
                            isSelected: currentStatus == .excused,
                            activeColor: AppColors.warning,
                            activeBg: AppColors.warningBackground
                        ) {
                            Task {
                                await viewModel.markAttendance(studentId: student.id, status: .excused)
                            }
                        }
                    }
                } else if viewModel.session.status == .completed {
                    HStack {
                        Spacer()
                        Menu {
                            if currentStatus != .present {
                                Button {
                                    Task {
                                        await viewModel.requestPostCompletionStatusAdjustment(studentId: student.id, newStatus: .present)
                                    }
                                } label: {
                                    Label("Đổi sang Đã hoàn thành (Có mặt)", systemImage: "checkmark.circle.fill")
                                }
                            }
                            if currentStatus != .absent {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.requestPostCompletionStatusAdjustment(studentId: student.id, newStatus: .absent)
                                    }
                                } label: {
                                    Label("Đổi sang Nghỉ (Vắng mặt — 0 ₫)", systemImage: "xmark.circle.fill")
                                }
                            }
                            if currentStatus != .excused {
                                Button {
                                    Task {
                                        await viewModel.requestPostCompletionStatusAdjustment(studentId: student.id, newStatus: .excused)
                                    }
                                } label: {
                                    Label("Đổi sang Nghỉ có phép (0 ₫)", systemImage: "info.circle.fill")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Điều chỉnh trạng thái hoàn thành")
                            }
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                        }
                    }
                }
            }
        }
    }

    private var enrollStudentSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isShowingEnrollStudentSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isShowingCreateStudentSheet = true
                        }
                    } label: {
                        Label("Tạo học sinh mới và thêm vào lớp", systemImage: "person.crop.circle.badge.plus")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.accentRose)
                    }
                }

                Section("Chọn học sinh hiện có để thêm vào buổi học") {
                    if viewModel.availableStudentsForEnrollment.isEmpty {
                        Text("Tất cả học sinh đang hoạt động đều đã có trong lớp này.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(viewModel.availableStudentsForEnrollment) { student in
                            HStack(spacing: AppSpacing.sm) {
                                AvatarView(
                                    avatarPath: student.avatarPath,
                                    initials: initials(for: student.fullName),
                                    size: 38
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.fullName)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                    if !student.phoneNumber.isEmpty {
                                        Text(student.phoneNumber)
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task {
                                        await viewModel.enrollStudentToSessionClass(student)
                                        if viewModel.availableStudentsForEnrollment.isEmpty {
                                            isShowingEnrollStudentSheet = false
                                        }
                                    }
                                } label: {
                                    Text("Thêm")
                                        .font(AppTypography.caption1)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(AppColors.primaryPink))
                                        .foregroundColor(AppColors.onPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Thêm học sinh vào lớp")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        isShowingEnrollStudentSheet = false
                    }
                    .foregroundColor(AppColors.accentRose)
                }
            }
        }
    }

    private var notesSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Nội dung bài học & Bài tập về nhà")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Nội dung đã dạy:")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)

                    TextField("Ghi chú nội dung trọng tâm buổi dạy...", text: $lessonNotesText)
                        .font(AppTypography.body)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.session.status != .scheduled)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Bài tập giao về nhà:")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)

                    TextField("Giao bài tập hoặc nhắc nhở sau buổi...", text: $homeworkText)
                        .font(AppTypography.body)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.session.status != .scheduled)
                }

                if viewModel.session.status == .scheduled {
                    Button("Lưu ghi chú") {
                        Task {
                            await viewModel.updateNotes(
                                lessonNotes: lessonNotesText,
                                homeworkAssigned: homeworkText
                            )
                        }
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accentRose)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completeSessionButton: some View {
        VStack(spacing: AppSpacing.xs) {
            PrimaryButton(
                "Hoàn thành buổi học",
                icon: "checkmark.circle.fill",
                isEnabled: viewModel.isAllMarked
            ) {
                viewModel.requestCompleteSession()
            }

            if !viewModel.isAllMarked {
                Text("Cần điểm danh 100% học sinh (có mặt, vắng hoặc có phép) trước khi hoàn thành buổi học.")
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.warning)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, AppSpacing.sm)
    }

    private var completedBanner: some View {
        AppCard {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.success)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Buổi học đã hoàn thành")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Học phí đã được đối soát và ghi nhận an toàn.")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                StatusBadge.sessionCompleted()
            }
        }
    }

    private var attachmentsSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundColor(AppColors.accentRose)
                    Text("Ảnh minh chứng buổi dạy")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()

                    if viewModel.session.status == .scheduled {
                        Button {
                            shouldCompleteAfterCamera = false
                            isShowingCameraView = true
                        } label: {
                            Label("Chụp ảnh", systemImage: "plus.circle.fill")
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(AppColors.secondaryPink))
                                .foregroundColor(AppColors.accentRose)
                        }
                    }
                }

                if viewModel.attachments.isEmpty {
                    Text(viewModel.session.status == .scheduled
                        ? "Chưa có ảnh minh chứng. Bấm \"Chụp ảnh\" để chụp và lưu ảnh lớp học theo tỉ lệ 1:1."
                        : "Không có ảnh minh chứng cho buổi học này.")
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(viewModel.attachments) { att in
                                Button {
                                    selectedAttachmentForDetail = att
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                                .fill(AppColors.secondaryPink.opacity(0.3))
                                                .frame(width: 90, height: 90)

                                            #if canImport(UIKit)
                                            if let uiImage = PhotoStorageService.shared.loadImage(named: att.filePath) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 90, height: 90)
                                                    .clipped()
                                                    .cornerRadius(AppRadius.sm)
                                            } else {
                                                Image(systemName: "photo")
                                                    .font(.system(size: 28))
                                                    .foregroundColor(AppColors.accentRose)
                                            }
                                            #else
                                            Image(systemName: "photo")
                                                .font(.system(size: 28))
                                                .foregroundColor(AppColors.accentRose)
                                            #endif
                                        }

                                        if !att.caption.isEmpty {
                                            Text(att.caption)
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.secondaryText)
                                                .lineLimit(1)
                                                .frame(width: 90, alignment: .leading)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completionSummarySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // Header card
                    AppCard {
                        VStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundColor(AppColors.accentRose)

                            Text("Tổng kết buổi dạy")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)

                            if let c = viewModel.classGroup {
                                Text("\(c.name) • \(viewModel.session.title)")
                                    .font(AppTypography.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                            }

                            Text("\(viewModel.session.startTime.formatted(date: .abbreviated, time: .shortened)) – \(viewModel.session.endTime.formatted(date: .omitted, time: .shortened))")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                    }

                    // 2 Mini KPI cards: Có mặt & Nghỉ
                    HStack(spacing: AppSpacing.sm) {
                        AppCard {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: "person.fill.checkmark")
                                        .foregroundColor(AppColors.success)
                                    Spacer()
                                    Text("\(viewModel.presentCount)")
                                        .font(AppTypography.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.success)
                                }
                                Text("Có mặt")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: "person.fill.xmark")
                                        .foregroundColor(AppColors.error)
                                    Spacer()
                                    Text("\(viewModel.absentCount)")
                                        .font(AppTypography.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.error)
                                }
                                Text("Nghỉ (0 VND)")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }

                    // Total tuition card
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tổng học phí phát sinh:")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)

                                Text(viewModel.totalAccruedTuition.formattedVND)
                                    .font(AppTypography.currencyLarge)
                                    .foregroundColor(AppColors.accentRose)
                            }
                            Spacer()
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.primaryPink.opacity(0.3))
                        }
                    }

                    // Roster detail
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Chi tiết học phí từng học sinh")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)

                        AppCard {
                            VStack(spacing: AppSpacing.xs) {
                                ForEach(viewModel.students) { student in
                                    let att = viewModel.attendance(for: student.id)
                                    let isPresent = att?.status == .present
                                    let price = viewModel.effectivePrice(for: student)

                                    HStack {
                                        Text(student.fullName)
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.primaryText)

                                        Spacer()

                                        if isPresent {
                                            Text("+\(price.formattedVND)")
                                                .font(AppTypography.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(AppColors.success)
                                        } else {
                                            Text("0 VND (Nghỉ)")
                                                .font(AppTypography.footnote)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                    }
                                    if student.id != viewModel.students.last?.id {
                                        Divider().background(AppColors.divider)
                                    }
                                }
                            }
                        }
                    }

                    // Proof photo status
                    if viewModel.presentCount == 0 {
                        AppCard {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(AppColors.info)
                                Text("Tất cả học sinh nghỉ: Buổi học được ghi nhận với tổng tiền 0 VND và không yêu cầu ảnh minh chứng.")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    } else if !viewModel.attachments.isEmpty {
                        AppCard {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "photo.badge.checkmark")
                                    .foregroundColor(AppColors.success)
                                Text("Đã có \(viewModel.attachments.count) ảnh minh chứng lớp học.")
                                    .font(AppTypography.subheadline)
                                    .foregroundColor(AppColors.primaryText)
                                Spacer()
                            }
                        }
                    }

                    // Action buttons
                    VStack(spacing: AppSpacing.xs) {
                        PrimaryButton(
                            viewModel.isCompleting ? "Đang ghi nhận..." : "Xác nhận hoàn thành & Phát sinh học phí",
                            icon: "checkmark.circle.fill",
                            isEnabled: !viewModel.isCompleting
                        ) {
                            Task {
                                await viewModel.confirmAndFinalizeCompletion()
                            }
                        }

                        Button("Kiểm tra lại") {
                            viewModel.isShowingCompletionSummary = false
                        }
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, AppSpacing.xs)
                    }
                    .padding(.top, AppSpacing.sm)
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Tổng kết buổi dạy")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        viewModel.isShowingCompletionSummary = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var completionStatusTitle: String {
        switch viewModel.session.status {
        case .completed:
            return "Đã hoàn thành buổi học & điểm danh"
        case .cancelled:
            return "Buổi học đã bị hủy"
        case .scheduled:
            if viewModel.students.isEmpty {
                return "Chưa có học sinh trong lớp"
            } else if viewModel.isAllMarked {
                return "Đã hoàn tất điểm danh 100%"
            } else {
                return "Đang điểm danh học sinh"
            }
        }
    }

    private var completionStatusIcon: String {
        switch viewModel.session.status {
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.octagon.fill"
        case .scheduled:
            return viewModel.isAllMarked ? "checkmark.circle.fill" : "clock.badge.exclamationmark.fill"
        }
    }

    private var completionStatusColor: Color {
        switch viewModel.session.status {
        case .completed:
            return AppColors.success
        case .cancelled:
            return AppColors.error
        case .scheduled:
            return viewModel.isAllMarked ? AppColors.success : AppColors.warning
        }
    }

    private func studentCompletionLabel(status: AttendanceStatus, markedAt: Date?) -> String {
        if viewModel.session.status == .completed {
            switch status {
            case .present:
                return "Đã hoàn thành buổi học (Có mặt)"
            case .absent:
                return "Đã chốt buổi học (Vắng mặt)"
            case .excused:
                return "Đã chốt buổi học (Nghỉ có phép)"
            case .pending:
                return "Đã hoàn thành buổi học"
            }
        } else if viewModel.session.status == .cancelled {
            return "Buổi học đã hủy"
        } else {
            switch status {
            case .present:
                if let time = markedAt {
                    return "Đã điểm danh Có mặt (\(time.formatted(date: .omitted, time: .shortened)))"
                }
                return "Đã điểm danh Có mặt"
            case .absent:
                if let time = markedAt {
                    return "Đã điểm danh Vắng (\(time.formatted(date: .omitted, time: .shortened)))"
                }
                return "Đã điểm danh Vắng mặt"
            case .excused:
                if let time = markedAt {
                    return "Đã điểm danh Có phép (\(time.formatted(date: .omitted, time: .shortened)))"
                }
                return "Đã điểm danh Có phép"
            case .pending:
                return "Chưa hoàn thành điểm danh"
            }
        }
    }

    private func studentCompletionIcon(status: AttendanceStatus) -> String {
        if viewModel.session.status == .completed {
            return "checkmark.seal.fill"
        }
        switch status {
        case .present, .absent, .excused:
            return "checkmark.circle.fill"
        case .pending:
            return "clock.badge.exclamationmark"
        }
    }

    private func studentCompletionColor(status: AttendanceStatus) -> Color {
        if viewModel.session.status == .completed {
            return AppColors.success
        }
        switch status {
        case .present:
            return AppColors.success
        case .absent:
            return AppColors.error
        case .excused:
            return AppColors.warning
        case .pending:
            return AppColors.warning
        }
    }

    private func attendanceCounterPill(label: String, count: Int, color: Color, bg: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.secondaryText)
            Text("\(count)")
                .font(AppTypography.caption1)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(bg))
    }

    private func attendanceToggleButton(
        title: String,
        icon: String,
        isSelected: Bool,
        activeColor: Color,
        activeBg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(AppTypography.caption1)
                    .fontWeight(isSelected ? .bold : .semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isSelected ? activeBg : AppColors.surfaceSubtle)
            )
            .foregroundColor(isSelected ? activeColor : AppColors.primaryText)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(isSelected ? activeColor : AppColors.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
    }

    private func statusBadge(for status: SessionStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(AppTypography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(statusColor(for: status))
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(statusColor(for: status).opacity(0.12)))
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .scheduled: return AppColors.info
        case .completed: return AppColors.success
        case .cancelled: return AppColors.error
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if let last = parts.last, let firstChar = last.first {
            return String(firstChar).uppercased()
        }
        return "HS"
    }
}
