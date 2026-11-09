import SwiftUI

/// Màn hình Hồ sơ chi tiết Học sinh (Giáo viên quản lý 1 học sinh)
/// Bao gồm phần đầu thông tin & 4 mục rõ ràng: Tổng quan, Điểm số, Học phí, Lớp học
public struct StudentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State public var viewModel: StudentDetailViewModel

    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingAddClassSheet: Bool = false
    @State private var preselectedClassIdForSchedule: UUID? = nil
    @State private var isShowingCreateClassSheet: Bool = false
    @State private var isShowingGradeFormSheet: Bool = false
    @State private var editingGradeItem: StudentGradeItem? = nil
    @State private var isShowingRecordPaymentSheet: Bool = false
    @State private var selectedAttachmentDetail: (attachment: SessionAttachmentEntity, sessionTitle: String, className: String)? = nil
    @State private var classItemToLeave: StudentClassEnrollmentItem? = nil
    @State private var leaveClassDate: Date = Date()

    public init(viewModel: StudentDetailViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                // MARK: - 1. Phần đầu: Avatar, Họ tên, Trạng thái, Nút Chỉnh sửa & Nút Thêm vào lớp
                headerProfileCard

                // MARK: - 2. Thanh chọn 4 mục rõ ràng: Tổng quan, Điểm số, Học phí, Lớp học
                sectionSegmentedBar

                // MARK: - 3. Nội dung từng mục
                Group {
                    switch viewModel.activeTab {
                    case .overview:
                        overviewTabView
                    case .grades:
                        gradesTabView
                    case .tuition:
                        tuitionTabView
                    case .classes:
                        classesTabView
                    case .assignments, .attendance, .notes:
                        overviewTabView
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(viewModel.student.fullName)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Text(L("Sửa", "Edit"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                    }

                    Menu {
                        if viewModel.student.isArchived {
                            Button {
                                Task {
                                    await viewModel.restoreStudent()
                                }
                            } label: {
                                Label(L("Khôi phục học sinh", "Restore Student"), systemImage: "arrow.uturn.backward.circle")
                            }

                            Button(role: .destructive) {
                                Task {
                                    await viewModel.requestDelete()
                                }
                            } label: {
                                Label(L("Xóa vĩnh viễn", "Delete Permanently"), systemImage: "trash")
                            }
                        } else {
                            Button {
                                Task {
                                    await viewModel.archiveStudent()
                                }
                            } label: {
                                Label(L("Lưu trữ học sinh", "Archive Student"), systemImage: "archivebox")
                            }

                            Button(role: .destructive) {
                                Task {
                                    await viewModel.requestDelete()
                                }
                            } label: {
                                Label(L("Xóa vĩnh viễn", "Delete Permanently"), systemImage: "trash")
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(L("Tác vụ", "Actions"))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppColors.secondaryPink))
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
        }
        // Sheet chỉnh sửa học sinh (lưu thật xuống DB)
        .sheet(isPresented: $isShowingEditSheet) {
            StudentEditView(student: viewModel.student) { updatedStudent in
                Task {
                    await viewModel.saveUpdatedStudent(updatedStudent)
                }
            }
        }
        // Sheet thêm học sinh vào lớp & thiết lập lịch tháng
        .sheet(isPresented: $isShowingAddClassSheet, onDismiss: {
            preselectedClassIdForSchedule = nil
        }) {
            StudentAddClassSheet(
                viewModel: viewModel,
                preselectedClassId: preselectedClassIdForSchedule,
                onRequestCreateNewClass: {
                    isShowingAddClassSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShowingCreateClassSheet = true
                    }
                }
            )
        }
        // Sheet tạo lớp mới nhanh nếu chưa có lớp
        .sheet(isPresented: $isShowingCreateClassSheet) {
            ClassEditView { newClass in
                Task {
                    try? await viewModel.classRepository.saveClass(newClass)
                    await viewModel.loadEnrolledClasses()
                    isShowingAddClassSheet = true
                }
            }
        }
        // Sheet thêm / sửa điểm số
        .sheet(isPresented: $isShowingGradeFormSheet) {
            StudentGradeEntrySheet(
                viewModel: viewModel,
                editingItem: editingGradeItem
            )
        }
        // Sheet ghi nhận thu tiền
        .sheet(isPresented: $isShowingRecordPaymentSheet) {
            RecordPaymentSheet(
                students: [viewModel.student],
                preselectedStudentId: viewModel.student.id,
                getOutstandingBalance: { _ in viewModel.studentFinanceSummary.outstandingBalance },
                getUnpaidSessionItems: { _ in viewModel.unpaidChargeSessionDetails },
                onSave: { _, amount, paidAt, method, note in
                    try await viewModel.recordPayment(
                        amount: amount,
                        paidAt: paidAt,
                        paymentMethod: method,
                        note: note
                    )
                },
                onSaveWithSelection: { _, amount, paidAt, method, note, selectedChargeIds in
                    try await viewModel.recordPayment(
                        amount: amount,
                        paidAt: paidAt,
                        paymentMethod: method,
                        note: note,
                        selectedChargeIds: selectedChargeIds
                    )
                }
            )
        }
        // Sheet xem chi tiết ảnh minh chứng
        .sheet(
            isPresented: Binding(
                get: { selectedAttachmentDetail != nil },
                set: { if !$0 { selectedAttachmentDetail = nil } }
            )
        ) {
            if let detail = selectedAttachmentDetail {
                ProofPhotoDetailView(
                    attachment: detail.attachment,
                    sessionTitle: detail.sessionTitle,
                    className: detail.className
                )
            }
        }
        // Sheet kết thúc tham gia lớp học
        .sheet(item: $classItemToLeave) { item in
            leaveClassConfirmationSheet(for: item)
        }
        // Hộp thoại xác nhận xóa vĩnh viễn
        .confirmationDialog(
            "Xác nhận xóa học sinh",
            isPresented: $viewModel.isDeleteConfirmationShowing,
            titleVisibility: .visible
        ) {
            Button("Xóa vĩnh viễn", role: .destructive) {
                Task {
                    await viewModel.executeDelete()
                }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bạn có chắc chắn muốn xóa học sinh \(viewModel.student.fullName)? Thao tác này không thể hoàn tác.")
        }
        // Cảnh báo chặn xóa khi còn nợ hoặc lịch sử tài chính
        .alert(
            "Không thể xóa học sinh",
            isPresented: $viewModel.isDeleteBlockedShowing
        ) {
            if !viewModel.student.isArchived {
                Button("Chuyển vào Lưu trữ") {
                    Task {
                        await viewModel.archiveStudent()
                    }
                }
            }
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            if viewModel.debtAmount > 0 {
                Text("Còn nợ \(viewModel.debtAmount.formattedVND). Hãy lưu trữ thay vì xóa.")
            } else {
                Text("Đã có lịch sử học phí. Hãy lưu trữ thay vì xóa.")
            }
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
        .onChange(of: viewModel.isDismissRequired) { _, shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
        .task {
            await viewModel.loadEnrolledClasses()
        }
    }

    // MARK: - Header Profile Card

    private var headerProfileCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    AvatarView(
                        avatarPath: viewModel.student.avatarPath,
                        initials: initials(for: viewModel.student.fullName),
                        size: 64,
                        showBorder: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(viewModel.student.fullName)
                                .font(AppTypography.title3)
                                .foregroundColor(AppColors.primaryText)

                            studentStatusBadge
                        }

                        if !viewModel.student.phoneNumber.isEmpty {
                            Label(viewModel.student.phoneNumber, systemImage: "phone.fill")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                        } else if !viewModel.student.parentPhone.isEmpty {
                            Label("PH: \(viewModel.student.parentPhone)", systemImage: "person.2.fill")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                        }

                        if let customPrice = viewModel.student.defaultPricePerSession, customPrice > 0 {
                            Label("Đơn giá riêng: \(customPrice.formattedVND)/buổi", systemImage: "banknote.fill")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.accentRose)
                                .fontWeight(.semibold)
                        } else {
                            Label("Đơn giá: Theo mức mặc định của lớp", systemImage: "banknote")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                        }

                        Label(
                            viewModel.enrolledClasses.isEmpty
                                ? L("Chưa tham gia lớp nào", "Not enrolled in any class")
                                : L("Đang tham gia \(viewModel.enrolledClasses.count) lớp", "Enrolled in \(viewModel.enrolledClasses.count) classes"),
                            systemImage: "graduationcap.fill"
                        )
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.enrolledClasses.isEmpty ? AppColors.secondaryText : AppColors.accentRose)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    private var studentStatusBadge: some View {
        Group {
            if viewModel.student.isArchived {
                StatusBadge(
                    title: "Đã lưu trữ",
                    icon: "archivebox.fill",
                    textColor: AppColors.secondaryText,
                    backgroundColor: AppColors.surfaceSubtle
                )
            } else {
                StatusBadge(
                    title: "Đang học",
                    icon: "checkmark.circle.fill",
                    textColor: AppColors.success,
                    backgroundColor: AppColors.successBackground
                )
            }
        }
    }

    // MARK: - 4-Section Navigation Bar

    private var sectionSegmentedBar: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(StudentDetailTab.primaryTabs) { tab in
                let isSelected = viewModel.activeTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.rawValue)
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
        .padding(.horizontal, AppSpacing.md)
    }

    // MARK: - A. Mục Tổng quan (Overview)

    private var overviewTabView: some View {
        VStack(spacing: AppSpacing.sm) {
            // 1. Thống kê nhanh: Số buổi hoàn thành trong tháng & Buổi học tiếp theo
            HStack(spacing: AppSpacing.sm) {
                AppCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "checkmark.calendar")
                                .foregroundColor(AppColors.accentRose)
                            Spacer()
                            Text("\(viewModel.completedSessionsThisMonthCount)")
                                .font(AppTypography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.accentRose)
                        }
                        Text("Buổi hoàn thành tháng này")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "person.badge.clock.fill")
                                .foregroundColor(AppColors.success)
                            Spacer()
                            let stats = viewModel.attendanceStats
                            Text(stats.total > 0 ? String(format: "%.0f%%", stats.rate) : "—")
                                .font(AppTypography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.success)
                        }
                        let stats = viewModel.attendanceStats
                        Text(stats.total > 0 ? "Chuyên cần (\(stats.present)/\(stats.total) buổi)" : "Chưa có buổi điểm danh")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 2. Buổi học tiếp theo
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(AppColors.accentRose)
                        Text("Buổi học tiếp theo")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }

                    if let upcoming = viewModel.nextUpcomingSession {
                        HStack(alignment: .center, spacing: AppSpacing.sm) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(upcoming.session.title)
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.primaryText)

                                Text("Lớp: \(upcoming.className)")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.accentRose)

                                Text("\(upcoming.session.startTime.formatted(date: .abbreviated, time: .shortened)) – \(upcoming.session.endTime.formatted(date: .omitted, time: .shortened))")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            StatusBadge.sessionScheduled()
                        }
                        .padding(AppSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(AppColors.surfaceSubtle)
                        )
                    } else {
                        Text("Chưa có buổi học nào sắp tới được lên lịch cho học sinh này.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 3. Tóm tắt Học phí (Phát sinh, Đã thu, Còn nợ - dùng chung dữ liệu)
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "dongsign.circle.fill")
                            .foregroundColor(AppColors.accentRose)
                        Text("Tình hình học phí")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Button {
                            viewModel.activeTab = .tuition
                        } label: {
                            Text("Xem chi tiết")
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)
                        }
                    }

                    HStack(spacing: AppSpacing.xs) {
                        financeMetricBox(
                            title: "Đã thu",
                            amount: viewModel.studentFinanceSummary.collectedTuition,
                            color: AppColors.success
                        )
                        financeMetricBox(
                            title: "Còn nợ",
                            amount: viewModel.studentFinanceSummary.outstandingBalance,
                            color: viewModel.studentFinanceSummary.outstandingBalance > 0 ? AppColors.warning : AppColors.secondaryText
                        )
                    }
                }
            }

            // 4. Các lớp đang tham gia
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "graduationcap.fill")
                            .foregroundColor(AppColors.accentRose)
                        Text("Các lớp đang tham gia (\(viewModel.activeEnrollmentItems.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Button {
                            viewModel.activeTab = .classes
                        } label: {
                            Text("Quản lý lớp")
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)
                        }
                    }

                    if viewModel.activeEnrollmentItems.isEmpty {
                        Text("Học sinh hiện chưa tham gia lớp học nào.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(viewModel.activeEnrollmentItems) { item in
                            HStack {
                                Circle()
                                    .fill(Color(hex: item.classGroup.colorHex))
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.classGroup.name)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("Môn: \(item.classGroup.subject.isEmpty ? "Chưa rõ" : item.classGroup.subject) • Từ \(item.enrollment.enrolledAt.formatted(date: .numeric, time: .omitted))")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.effectivePrice.formattedVND)/buổi")
                                        .font(AppTypography.caption1)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.accentRose)
                                    Text(item.isCustomPrice ? "Giá riêng" : "Giá lớp")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                            if item.id != viewModel.activeEnrollmentItems.last?.id {
                                Divider().background(AppColors.divider)
                            }
                        }
                    }
                }
            }

            // 5. Thông tin liên hệ & Ghi chú sư phạm
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Thông tin liên hệ & Ghi chú")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    infoRow(icon: "phone.fill", label: "SĐT học sinh", value: viewModel.student.phoneNumber)
                    infoRow(icon: "person.2.fill", label: "SĐT phụ huynh", value: viewModel.student.parentPhone)
                    infoRow(icon: "envelope.fill", label: "Email", value: viewModel.student.email)

                    Divider().background(AppColors.divider)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghi chú sư phạm:")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        Text(viewModel.student.notes.isEmpty ? "Chưa có ghi chú sư phạm." : viewModel.student.notes)
                            .font(AppTypography.body)
                            .foregroundColor(viewModel.student.notes.isEmpty ? AppColors.tertiaryText : AppColors.primaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - B. Mục Điểm số (Grades)

    private var gradesTabView: some View {
        VStack(spacing: AppSpacing.sm) {
            // Thanh công cụ: Lọc theo lớp/môn + Nút Thêm điểm
            HStack {
                Menu {
                    Button {
                        viewModel.selectedGradeClassFilterId = nil
                    } label: {
                        HStack {
                            Text("Tất cả lớp & môn")
                            if viewModel.selectedGradeClassFilterId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(viewModel.allClasses.filter { !$0.isArchived }) { c in
                        Button {
                            viewModel.selectedGradeClassFilterId = c.id
                        } label: {
                            HStack {
                                Text("\(c.name) (\(c.subject.isEmpty ? "Môn chung" : c.subject))")
                                if viewModel.selectedGradeClassFilterId == c.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        if let classId = viewModel.selectedGradeClassFilterId,
                           let c = viewModel.classGroup(for: classId) {
                            Text("\(c.name) • \(c.subject)")
                        } else {
                            Text("Tất cả lớp & môn")
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppColors.surfaceCard))
                    .foregroundColor(AppColors.primaryText)
                    .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                }

                Spacer()

                Button {
                    editingGradeItem = nil
                    isShowingGradeFormSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                        Text("Thêm điểm")
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppColors.primaryPink))
                    .foregroundColor(AppColors.onPrimary)
                }
            }

            // Biểu đồ tiến bộ học tập & ĐTB Trọng số (Chỉ hiện số khi đã có điểm, chưa có điểm hiển thị trạng thái trống)
            GradeProgressChartView(
                items: viewModel.filteredGradeItems,
                average: viewModel.weightedAverage
            )

            // Danh sách bài kiểm tra & điểm số
            if viewModel.filteredGradeItems.isEmpty {
                AppCard {
                    EmptyStateView(
                        icon: "chart.bar.doc.horizontal",
                        title: "Chưa có điểm kiểm tra",
                        message: "Học sinh chưa có cột điểm nào (không tính là 0 điểm). Bấm \"Thêm điểm\" để ghi nhận bài kiểm tra mới.",
                        actionTitle: "Thêm điểm đầu tiên"
                    ) {
                        editingGradeItem = nil
                        isShowingGradeFormSheet = true
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Danh sách bài kiểm tra (\(viewModel.filteredGradeItems.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    ForEach(viewModel.filteredGradeItems.sorted(by: { $0.assessment.date > $1.assessment.date }), id: \.grade.id) { item in
                        let cGroup = viewModel.classGroup(for: item.assessment.classId)
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        if let cGroup {
                                            HStack(spacing: 6) {
                                                Text(cGroup.name)
                                                    .font(AppTypography.caption2)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color(hex: cGroup.colorHex).opacity(0.15)))
                                                    .foregroundColor(Color(hex: cGroup.colorHex))

                                                if !cGroup.subject.isEmpty {
                                                    Text("Môn: \(cGroup.subject)")
                                                        .font(AppTypography.caption2)
                                                        .foregroundColor(AppColors.secondaryText)
                                                }
                                            }
                                        }

                                        Text(item.assessment.title)
                                            .font(AppTypography.headline)
                                            .foregroundColor(AppColors.primaryText)

                                        Text("Ngày KT: \(item.assessment.date.formatted(date: .numeric, time: .omitted)) • Hệ số \(String(format: "%.1f", item.assessment.weight))")
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.secondaryText)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                                            Text(String(format: "%.1f", item.grade.score))
                                                .font(AppTypography.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(AppColors.accentRose)
                                            Text("/ \(String(format: "%.1f", item.assessment.maxScore))")
                                                .font(AppTypography.caption1)
                                                .foregroundColor(AppColors.secondaryText)
                                        }

                                        Button {
                                            editingGradeItem = item
                                            isShowingGradeFormSheet = true
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "pencil")
                                                Text("Sửa điểm")
                                            }
                                            .font(AppTypography.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.accentRose)
                                        }
                                    }
                                }

                                if !item.grade.notes.isEmpty {
                                    Divider().background(AppColors.divider)
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "text.bubble.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.accentRose)
                                        Text("Nhận xét: \(item.grade.notes)")
                                            .font(AppTypography.footnote)
                                            .foregroundColor(AppColors.primaryText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - C. Mục Học phí (Tuition)

    private var tuitionTabView: some View {
        let metrics = viewModel.periodTuitionMetrics
        let totalOutstanding = viewModel.studentFinanceSummary.outstandingBalance

        return VStack(spacing: AppSpacing.sm) {
            // 1. Bộ lọc tháng + Nút Ghi nhận thu tiền
            HStack {
                Menu {
                    Button {
                        viewModel.selectedTuitionMonth = nil
                    } label: {
                        HStack {
                            Text("Toàn bộ các kỳ")
                            if viewModel.selectedTuitionMonth == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(viewModel.availableTuitionMonths, id: \.self) { monthDate in
                        Button {
                            viewModel.selectedTuitionMonth = monthDate
                        } label: {
                            HStack {
                                Text(monthLabel(for: monthDate))
                                if let selected = viewModel.selectedTuitionMonth,
                                   Calendar.current.isDate(selected, equalTo: monthDate, toGranularity: .month) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        if let month = viewModel.selectedTuitionMonth {
                            Text("Kỳ: \(monthLabel(for: month))")
                        } else {
                            Text("Kỳ: Toàn bộ công nợ")
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppColors.surfaceCard))
                    .foregroundColor(AppColors.primaryText)
                    .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                }

                Spacer()

                Button {
                    isShowingRecordPaymentSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "banknote.fill")
                        Text("Ghi nhận thu tiền")
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(totalOutstanding > 0 ? AppColors.primaryPink : AppColors.surfaceSubtle)
                    )
                    .foregroundColor(totalOutstanding > 0 ? .white : AppColors.tertiaryText)
                }
                .disabled(totalOutstanding <= 0)
            }

            // 2. Thẻ Tổng hợp Số buổi, Học phí phát sinh, Đã thu và Tổng còn nợ (ghi nhãn rõ kỳ vs toàn bộ)
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text(viewModel.selectedTuitionMonth == nil ? "Tổng hợp toàn bộ học phí" : "Số liệu trong \(monthLabel(for: viewModel.selectedTuitionMonth!))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Text("\(metrics.presentCount)/\(metrics.sessionCount) buổi có mặt")
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AppColors.secondaryPink))
                            .foregroundColor(AppColors.accentRose)
                    }

                    HStack(spacing: AppSpacing.xs) {
                        financeMetricBox(
                            title: viewModel.selectedTuitionMonth == nil ? "Đã thu" : "Đã thu kỳ này",
                            amount: metrics.collected,
                            color: AppColors.success
                        )
                        financeMetricBox(
                            title: "Tổng còn nợ",
                            amount: totalOutstanding,
                            color: totalOutstanding > 0 ? AppColors.warning : AppColors.secondaryText
                        )
                    }
                }
            }

            // 3. Danh sách các buổi đã dạy cho học sinh (Ngày dạy, lớp, tiêu đề, đơn giá, trạng thái thanh toán, ảnh minh chứng, ghi chú)
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Danh sách buổi đã dạy (\(viewModel.filteredSessionTuitionItems.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    if viewModel.filteredSessionTuitionItems.isEmpty {
                        if viewModel.studentCharges.isEmpty {
                            EmptyStateView(
                                icon: "calendar.badge.checkmark",
                                title: "Chưa có buổi dạy hoàn thành",
                                message: "Khi giáo viên hoàn thành buổi học có học sinh tham gia, thông tin buổi dạy, ảnh minh chứng và học phí sẽ hiển thị tại đây."
                            )
                        } else {
                            // Hiển thị các khoản phí trực tiếp nếu có charge độc lập
                            ForEach(viewModel.studentCharges.sorted(by: { $0.createdAt > $1.createdAt })) { charge in
                                standaloneChargeRow(charge)
                            }
                        }
                    } else {
                        ForEach(viewModel.filteredSessionTuitionItems) { item in
                            sessionTuitionRow(item)
                            if item.id != viewModel.filteredSessionTuitionItems.last?.id {
                                Divider().background(AppColors.divider)
                            }
                        }
                    }
                }
            }

            // 4. Lịch sử thu tiền
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Lịch sử thu tiền (\(viewModel.filteredPayments.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)

                    if viewModel.filteredPayments.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "Chưa có giao dịch thu tiền",
                            message: "Chưa có bản ghi thanh toán học phí nào trong kỳ đang chọn."
                        )
                    } else {
                        ForEach(viewModel.filteredPayments.sorted(by: { $0.paidAt > $1.paidAt })) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payment.paidAt.formatted(date: .numeric, time: .shortened))
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("\(payment.paymentMethod)\(payment.note.isEmpty ? "" : " • " + payment.note)")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                Text("+\(payment.amount.formattedVND)")
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.success)
                            }
                            .padding(.vertical, 4)
                            if payment.id != viewModel.filteredPayments.last?.id {
                                Divider().background(AppColors.divider)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sessionTuitionRow(_ item: StudentSessionTuitionItem) -> some View {
        let className = item.classGroup?.name ?? "Lớp học"
        let colorHex = item.classGroup?.colorHex ?? "#E88FA8"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(className)
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: colorHex).opacity(0.15)))
                            .foregroundColor(Color(hex: colorHex))

                        Text(item.session.startTime.formatted(date: .numeric, time: .shortened))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                    }

                    Text(item.session.title)
                        .font(AppTypography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.primaryText)

                    Text("Đơn giá: \(item.unitPriceDisplayed.formattedVND)/buổi")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let charge = item.charge {
                        Text(charge.amount.formattedVND)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                        chargeStatusBadge(for: charge.status)
                    } else if item.attendance.status == .present {
                        Text(item.unitPriceDisplayed.formattedVND)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                        StatusBadge.attendancePresent()
                    } else {
                        Text("0 ₫ (Nghỉ)")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        attendanceStatusBadge(for: item.attendance.status)
                    }
                }
            }

            // Ghi chú buổi học hoặc ghi chú điểm danh
            if !item.session.userDisplayNotes.isEmpty || !item.attendance.note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !item.session.userDisplayNotes.isEmpty {
                        Text("Ghi chú buổi học: \(item.session.userDisplayNotes)")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    if !item.attendance.note.isEmpty {
                        Text("Ghi chú học sinh: \(item.attendance.note)")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.accentRose)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: AppRadius.xs).fill(AppColors.surfaceSubtle))
            }

            // Ảnh minh chứng của buổi dạy
            if !item.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(item.attachments) { att in
                            Button {
                                selectedAttachmentDetail = (att, item.session.title, className)
                            } label: {
                                HStack(spacing: 6) {
                                    #if canImport(UIKit)
                                    if let uiImg = PhotoStorageService.shared.loadImage(named: att.filePath) {
                                        Image(uiImage: uiImg)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipped()
                                            .cornerRadius(AppRadius.xs)
                                    } else {
                                        Image(systemName: "photo.fill")
                                            .foregroundColor(AppColors.accentRose)
                                            .frame(width: 44, height: 44)
                                            .background(AppColors.secondaryPink.opacity(0.3))
                                            .cornerRadius(AppRadius.xs)
                                    }
                                    #else
                                    Image(systemName: "photo.fill")
                                        .foregroundColor(AppColors.accentRose)
                                        .frame(width: 44, height: 44)
                                    #endif

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Ảnh minh chứng")
                                            .font(AppTypography.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.primaryText)
                                        Text(att.caption.isEmpty ? "Chạm để xem ảnh lớn" : att.caption)
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm)
                                        .fill(AppColors.surfaceSubtle)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func standaloneChargeRow(_ charge: ChargeEntity) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Buổi học ngày \(charge.createdAt.formatted(date: .numeric, time: .omitted))")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.primaryText)
                Text("Đơn giá snapshot: \(charge.unitPriceSnapshot.formattedVND)")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(charge.amount.formattedVND)
                    .font(AppTypography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.primaryText)
                chargeStatusBadge(for: charge.status)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - D. Mục Lớp học (Classes)

    private var classesTabView: some View {
        VStack(spacing: AppSpacing.sm) {
            // 1 nút tác vụ duy nhất cho việc Thêm vào lớp & Thiết lập lịch tháng
            if !viewModel.student.isArchived {
                Button {
                    preselectedClassIdForSchedule = nil
                    isShowingAddClassSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Thêm vào lớp & Thiết lập lịch tháng")
                    }
                    .font(AppTypography.subheadline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.primaryPink))
                    .foregroundColor(AppColors.onPrimary)
                }
                .buttonStyle(.plain)
            }

            // 1. Các lớp đang tham gia
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundColor(AppColors.success)
                        Text("Đang tham gia (\(viewModel.activeEnrollmentItems.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }

                    if viewModel.activeEnrollmentItems.isEmpty {
                        EmptyStateView(
                            icon: "graduationcap",
                            title: "Chưa tham gia lớp nào",
                            message: "Bấm nút \"Thêm vào lớp & Thiết lập lịch tháng\" phía trên để chọn lớp, ngày bắt đầu học, đơn giá và lịch học theo tháng."
                        )
                    } else {
                        ForEach(viewModel.activeEnrollmentItems) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center, spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: item.classGroup.colorHex))
                                        .frame(width: 12, height: 12)

                                    NavigationLink {
                                        ClassDetailView(
                                            viewModel: ClassDetailViewModel(
                                                classGroup: item.classGroup,
                                                classRepository: viewModel.classRepository,
                                                studentRepository: viewModel.studentRepository,
                                                scheduleRepository: viewModel.scheduleRepository,
                                                financeRepository: viewModel.financeRepository
                                            ),
                                            classRepository: viewModel.classRepository,
                                            studentRepository: viewModel.studentRepository,
                                            scheduleRepository: viewModel.scheduleRepository,
                                            financeRepository: viewModel.financeRepository,
                                            gradeRepository: viewModel.gradeRepository,
                                            assignmentRepository: viewModel.assignmentRepository
                                        )
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(item.classGroup.name)
                                                .font(AppTypography.headline)
                                                .foregroundColor(AppColors.primaryText)
                                                .multilineTextAlignment(.leading)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(AppColors.accentRose)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    StatusBadge(
                                        title: "Đang học",
                                        icon: "checkmark.circle.fill",
                                        textColor: AppColors.success,
                                        backgroundColor: AppColors.successBackground
                                    )
                                    .fixedSize(horizontal: true, vertical: false)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Môn: \(item.classGroup.subject.isEmpty ? "Chưa phân môn" : item.classGroup.subject) • Thời lượng: \(item.classGroup.sessionDurationMinutes) phút")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)

                                    Text("Ngày bắt đầu: \(item.enrollment.enrolledAt.formatted(date: .numeric, time: .omitted))")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)

                                    HStack(spacing: 4) {
                                        Text("Đơn giá áp dụng: \(item.effectivePrice.formattedVND)/buổi")
                                            .font(AppTypography.caption1)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.accentRose)
                                        Text(item.isCustomPrice ? "(Đơn giá riêng)" : "(Đơn giá lớp)")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Spacer()

                                    Button(role: .destructive) {
                                        leaveClassDate = max(Date(), item.enrollment.enrolledAt)
                                        classItemToLeave = item
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                            Text("Kết thúc học")
                                        }
                                        .font(AppTypography.caption1)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule().fill(AppColors.errorBackground)
                                        )
                                        .foregroundColor(AppColors.error)
                                        .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6)

                            if item.id != viewModel.activeEnrollmentItems.last?.id {
                                Divider().background(AppColors.divider)
                            }
                        }
                    }
                }
            }

            // 2. Lịch sử tham gia lớp (Đã kết thúc nhưng giữ nguyên lịch sử)
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(AppColors.secondaryText)
                        Text("Lịch sử tham gia lớp (\(viewModel.historicalEnrollmentItems.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }

                    if viewModel.historicalEnrollmentItems.isEmpty {
                        Text("Chưa có lịch sử kết thúc tham gia lớp nào.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.historicalEnrollmentItems) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.classGroup.name)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)

                                    let startStr = item.enrollment.enrolledAt.formatted(date: .numeric, time: .omitted)
                                    let endStr = item.enrollment.leftAt?.formatted(date: .numeric, time: .omitted) ?? "Đã kết thúc"
                                    Text("Thời gian học: \(startStr) → \(endStr)")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)

                                    Text("Đơn giá áp dụng: \(item.effectivePrice.formattedVND)/buổi")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                StatusBadge(
                                    title: "Đã kết thúc",
                                    icon: "clock",
                                    textColor: AppColors.secondaryText,
                                    backgroundColor: AppColors.surfaceSubtle
                                )
                            }
                            .padding(.vertical, 4)

                            if item.id != viewModel.historicalEnrollmentItems.last?.id {
                                Divider().background(AppColors.divider)
                            }
                        }
                    }
                }
            }
        }
    }

    private func leaveClassConfirmationSheet(for item: StudentClassEnrollmentItem) -> some View {
        NavigationStack {
            Form {
                Section("Thông tin lớp học") {
                    HStack {
                        Text("Lớp học")
                        Spacer()
                        Text(item.classGroup.name)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Ngày bắt đầu")
                        Spacer()
                        Text(item.enrollment.enrolledAt.formatted(date: .numeric, time: .omitted))
                    }
                }

                Section {
                    DatePicker(
                        "Ngày kết thúc tham gia",
                        selection: $leaveClassDate,
                        in: item.enrollment.enrolledAt...,
                        displayedComponents: [.date]
                    )
                } footer: {
                    Text("Lớp sẽ chuyển vào Lịch sử tham gia. Điểm danh, điểm số, học phí được giữ nguyên.")
                }
            }
            .navigationTitle("Kết thúc tham gia lớp")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        classItemToLeave = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xác nhận", role: .destructive) {
                        let targetClassId = item.classGroup.id
                        let targetDate = leaveClassDate
                        classItemToLeave = nil
                        Task {
                            await viewModel.endClassParticipation(classId: targetClassId, leftAt: targetDate)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helper Subviews

    private func financeMetricBox(title: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.secondaryText)
            Text(amount.formattedVND)
                .font(AppTypography.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColors.surfaceSubtle)
        )
    }

    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isDisabled ? AppColors.surfaceSubtle : color.opacity(0.14))
            )
            .foregroundColor(isDisabled ? AppColors.tertiaryText : color)
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }

    private func attendanceStatusBadge(for status: AttendanceStatus) -> some View {
        switch status {
        case .pending:
            return StatusBadge(title: "Chưa điểm danh", icon: "clock", textColor: AppColors.secondaryText, backgroundColor: AppColors.surfaceSubtle)
        case .present:
            return StatusBadge.attendancePresent()
        case .absent:
            return StatusBadge.attendanceAbsent()
        case .excused:
            return StatusBadge.attendanceExcused()
        }
    }

    private func chargeStatusBadge(for status: ChargeStatus) -> some View {
        switch status {
        case .unpaid:
            return StatusBadge(title: status.displayName, icon: "circle", textColor: AppColors.warning, backgroundColor: AppColors.warning.opacity(0.15))
        case .partiallyPaid:
            return StatusBadge(title: status.displayName, icon: "circle.lefthalf.filled", textColor: AppColors.info, backgroundColor: AppColors.infoBackground)
        case .paid:
            return StatusBadge(title: status.displayName, icon: "checkmark.circle.fill", textColor: AppColors.success, backgroundColor: AppColors.success.opacity(0.15))
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppColors.accentRose)
                .frame(width: 24)

            Text(label)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Spacer()

            Text(value.isEmpty ? "Chưa có" : value)
                .font(AppTypography.body)
                .foregroundColor(value.isEmpty ? AppColors.tertiaryText : AppColors.primaryText)
        }
    }

    private func monthLabel(for date: Date) -> String {
        let comp = Calendar.current.dateComponents([.month, .year], from: date)
        let m = comp.month ?? 1
        let y = comp.year ?? 2026
        return "Tháng \(m)/\(y)"
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if let last = parts.last, let firstChar = last.first {
            return String(firstChar).uppercased()
        }
        return "EP"
    }
}

// MARK: - Sheet Thêm / Sửa Điểm số (B. Điểm số)

private struct StudentGradeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: StudentDetailViewModel
    let editingItem: StudentGradeItem?

    @State private var selectedClassId: UUID = UUID()
    @State private var title: String = ""
    @State private var scoreText: String = ""
    @State private var maxScoreText: String = "10"
    @State private var weightText: String = "1"
    @State private var examDate: Date = Date()
    @State private var notes: String = ""
    @State private var localError: String? = nil
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lớp học & Bài kiểm tra") {
                    if viewModel.selectableClassesForGrades.isEmpty {
                        Text("Chưa có lớp học nào. Vui lòng thêm học sinh vào lớp trước khi nhập điểm.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.warning)
                    } else {
                        Picker("Lớp / Môn học", selection: $selectedClassId) {
                            ForEach(viewModel.selectableClassesForGrades) { c in
                                Text("\(c.name)\(c.subject.isEmpty ? "" : " (\(c.subject))")")
                                    .tag(c.id)
                            }
                        }
                    }

                    TextField("Tên bài kiểm tra (VD: Kiểm tra 15 phút, Giữa kỳ...)", text: $title)

                    DatePicker("Ngày kiểm tra", selection: $examDate, displayedComponents: [.date])
                }

                Section("Điểm số & Trọng số") {
                    HStack {
                        Text("Điểm đạt được")
                        Spacer()
                        TextField("VD: 8.5", text: $scoreText)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    HStack {
                        Text("Điểm tối đa")
                        Spacer()
                        TextField("10", text: $maxScoreText)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    HStack {
                        Text("Hệ số (Trọng số)")
                        Spacer()
                        TextField("1.0", text: $weightText)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Nhận xét của giáo viên") {
                    TextField("Nhận xét bài làm, ưu điểm hoặc phần cần cải thiện...", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let localError {
                    Section {
                        Text(localError)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.error)
                    }
                }
            }
            .navigationTitle(editingItem == nil ? "Thêm điểm kiểm tra" : "Sửa điểm kiểm tra")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveGrade()
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving || viewModel.selectableClassesForGrades.isEmpty)
                }
            }
            .onAppear {
                if let editingItem {
                    selectedClassId = editingItem.assessment.classId
                    title = editingItem.assessment.title
                    scoreText = String(format: "%.1f", editingItem.grade.score)
                    maxScoreText = String(format: "%.1f", editingItem.assessment.maxScore)
                    weightText = String(format: "%.1f", editingItem.assessment.weight)
                    examDate = editingItem.assessment.date
                    notes = editingItem.grade.notes
                } else if let firstClass = viewModel.selectableClassesForGrades.first {
                    selectedClassId = firstClass.id
                }
            }
        }
    }

    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private func saveGrade() {
        localError = nil
        guard let score = parseNumber(scoreText) else {
            localError = "Vui lòng nhập điểm đạt được hợp lệ."
            return
        }
        guard let maxScore = parseNumber(maxScoreText) else {
            localError = "Vui lòng nhập điểm tối đa hợp lệ."
            return
        }
        guard let weight = parseNumber(weightText) else {
            localError = "Vui lòng nhập hệ số điểm hợp lệ."
            return
        }

        isSaving = true
        Task {
            do {
                try await viewModel.saveOrUpdateGrade(
                    existingItem: editingItem,
                    classId: selectedClassId,
                    title: title,
                    score: score,
                    maxScore: maxScore,
                    weight: weight,
                    date: examDate,
                    notes: notes
                )
                isSaving = false
                dismiss()
            } catch {
                localError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

// MARK: - Sheet Thêm Học sinh vào Lớp -> Thiết lập Lịch tháng (Tính năng 3)

public struct StudentAddClassSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: StudentDetailViewModel
    let preselectedClassId: UUID?
    let onRequestCreateNewClass: () -> Void
    let onCompleted: (() -> Void)?

    public init(
        viewModel: StudentDetailViewModel,
        preselectedClassId: UUID? = nil,
        onRequestCreateNewClass: @escaping () -> Void = {},
        onCompleted: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.preselectedClassId = preselectedClassId
        self.onRequestCreateNewClass = onRequestCreateNewClass
        self.onCompleted = onCompleted

        let openClasses = viewModel.allClasses.filter { !$0.isArchived }
        let initialClassId: UUID
        if let preselectedClassId, openClasses.contains(where: { $0.id == preselectedClassId }) {
            initialClassId = preselectedClassId
        } else if let firstUnenrolled = openClasses.first(where: { c in
            !viewModel.activeEnrollmentItems.contains(where: { $0.classGroup.id == c.id })
        }) {
            initialClassId = firstUnenrolled.id
        } else {
            initialClassId = openClasses.first?.id ?? UUID()
        }
        self._selectedClassId = State(initialValue: initialClassId)
        self._isConfiguringMonthlySchedule = State(initialValue: preselectedClassId != nil)
    }

    // 1. Chọn lớp & Ngày bắt đầu
    @State private var selectedClassId: UUID
    @State private var enrolledAt: Date = Date()

    // 2. Đơn giá mỗi buổi
    @State private var useCustomPrice: Bool = false
    @State private var customPrice: Int64 = 0

    // 3. Lịch học hiện có của lớp & Thiết lập lịch tháng mới
    @State private var existingClassSessions: [TeachingSessionEntity] = []
    @State private var allSystemSessionsInWindow: [TeachingSessionEntity] = []
    @State private var isConfiguringMonthlySchedule: Bool
    @State private var selectedMonthOffset: Int = 0 // 0 = Tháng hiện tại (theo enrolledAt), 1 = Tháng sau, ...
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
    @State private var rangeStartDate: Date = Date()
    @State private var rangeEndDate: Date = Date()

    // Các buổi đã gom từ tháng trước (khi bấm "Lưu tạm & Thiết lập tiếp tháng sau")
    @State private var stagedSessionsAcrossMonths: [TeachingSessionEntity] = []

    @State private var localError: String? = nil
    @State private var isSubmitting: Bool = false
    @State private var showSavedContinueMonthBanner: String? = nil

    private let recurringUseCase = GenerateRecurringSessionsUseCase()
    private let overlapUseCase = CheckScheduleOverlapUseCase()

    private var activeClasses: [ClassGroupEntity] {
        viewModel.allClasses.filter { !$0.isArchived }
    }

    private var selectedClassGroup: ClassGroupEntity? {
        activeClasses.first(where: { $0.id == selectedClassId })
    }

    /// Các buổi học hiện có của lớp mà học sinh sẽ được tự động thêm vào (scheduled & >= ngày bắt đầu tham gia)
    private var eligibleExistingSessions: [TeachingSessionEntity] {
        let startOfDay = Calendar.current.startOfDay(for: enrolledAt)
        return existingClassSessions.filter { $0.status == .scheduled && $0.startTime >= startOfDay }
    }

    /// Các buổi học của lớp đã hoàn thành hoặc diễn ra trước ngày tham gia (không tự thêm học sinh)
    private var skippedHistoricalOrCompletedSessionsCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: enrolledAt)
        return existingClassSessions.filter {
            $0.status == .completed || ($0.status == .scheduled && $0.startTime < startOfDay)
        }.count
    }

    /// Kiểm tra giờ kết thúc sau giờ bắt đầu
    private var isTimeOrderValid: Bool {
        let cal = Calendar.current
        let startComp = cal.dateComponents([.hour, .minute], from: sessionStartTime)
        let endComp = cal.dateComponents([.hour, .minute], from: sessionEndTime)
        let startMins = (startComp.hour ?? 0) * 60 + (startComp.minute ?? 0)
        let endMins = (endComp.hour ?? 0) * 60 + (endComp.minute ?? 0)
        return endMins > startMins
    }

    /// Danh sách các buổi học được sinh xem trước cho khoảng tháng đang chọn
    private var currentMonthPreviewSessions: [TeachingSessionEntity] {
        guard isConfiguringMonthlySchedule,
              isTimeOrderValid,
              !selectedDays.isEmpty,
              rangeEndDate >= rangeStartDate,
              let c = selectedClassGroup else {
            return []
        }

        let cal = Calendar.current
        let startComp = cal.dateComponents([.hour, .minute], from: sessionStartTime)
        let endComp = cal.dateComponents([.hour, .minute], from: sessionEndTime)
        let durationMins = max(15, ((endComp.hour ?? 0) * 60 + (endComp.minute ?? 0)) - ((startComp.hour ?? 0) * 60 + (startComp.minute ?? 0)))

        var templateStartComp = cal.dateComponents([.year, .month, .day], from: rangeStartDate)
        templateStartComp.hour = startComp.hour
        templateStartComp.minute = startComp.minute
        let tStart = cal.date(from: templateStartComp) ?? rangeStartDate
        let tEnd = tStart.addingTimeInterval(TimeInterval(durationMins * 60))

        let template = TeachingSessionEntity(
            classId: c.id,
            title: "Buổi học: \(c.name)",
            startTime: tStart,
            endTime: tEnd,
            status: .scheduled
        )

        let combinedExisting = existingClassSessions + stagedSessionsAcrossMonths
        let effectiveStart = max(cal.startOfDay(for: enrolledAt), cal.startOfDay(for: rangeStartDate))
        guard rangeEndDate >= effectiveStart else { return [] }

        return recurringUseCase.execute(
            templateSession: template,
            selectedDays: selectedDays,
            startDate: effectiveStart,
            endDate: rangeEndDate,
            existingSessions: combinedExisting
        )
    }

    /// Tổng hợp tất cả các buổi học mới sẽ được tạo (bao gồm các tháng đã gom + tháng đang xem trước)
    private var totalNewSessionsToCreate: [TeachingSessionEntity] {
        let cal = Calendar.current
        var result = stagedSessionsAcrossMonths
        for s in currentMonthPreviewSessions {
            let isDup = result.contains { existing in
                existing.classId == s.classId &&
                cal.isDate(existing.startTime, inSameDayAs: s.startTime) &&
                abs(existing.startTime.timeIntervalSince(s.startTime)) < 120
            }
            if !isDup {
                result.append(s)
            }
        }
        return result.sorted { $0.startTime < $1.startTime }
    }

    /// Kiểm tra xem trong các buổi sắp tạo có buổi nào bị trùng giờ với lớp khác không (cho phép hai buổi liền kề)
    private var overlappingConflicts: [(newSession: TeachingSessionEntity, conflictWith: TeachingSessionEntity)] {
        var conflicts: [(TeachingSessionEntity, TeachingSessionEntity)] = []
        for candidate in totalNewSessionsToCreate {
            if let hit = overlapUseCase.execute(
                newStartTime: candidate.startTime,
                newEndTime: candidate.endTime,
                existingSessions: allSystemSessionsInWindow
            ) {
                conflicts.append((candidate, hit))
            }
        }
        return conflicts
    }

    private var targetMonthDate: Date {
        let cal = Calendar.current
        let baseMonth = cal.date(from: cal.dateComponents([.year, .month], from: enrolledAt)) ?? enrolledAt
        return cal.date(byAdding: .month, value: selectedMonthOffset, to: baseMonth) ?? baseMonth
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                if activeClasses.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        EmptyStateView(
                            icon: "person.3.sequence.fill",
                            title: "Chưa có lớp học nào",
                            message: "Hãy tạo lớp học trước để thêm học sinh \(viewModel.student.fullName) vào lớp.",
                            actionTitle: "Tạo lớp học mới"
                        ) {
                            onRequestCreateNewClass()
                        }
                        .padding(AppSpacing.md)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.md) {
                            // 1. CHỌN LỚP HỌC
                            classSelectionSectionCard

                            // 2. NGÀY THAM GIA & HỌC PHÍ MỖI BUỔI
                            enrollmentAndPriceSectionCard

                            // 3. LỊCH HỌC CỦA LỚP & THIẾT LẬP LỊCH THÁNG
                            scheduleConfigSectionCard

                            // 4. XEM TRƯỚC BUỔI HỌC SẼ ÁP DỤNG
                            previewSessionsSectionCard

                            if let localError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppColors.error)
                                    Text(localError)
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.error)
                                    Spacer()
                                }
                                .padding(AppSpacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm)
                                        .fill(AppColors.error.opacity(0.1))
                                )
                            }

                            PrimaryButton(
                                isSubmitting ? "Đang lưu..." : "Xác nhận thêm vào lớp",
                                icon: "checkmark.circle.fill",
                                isLoading: isSubmitting,
                                isEnabled: !activeClasses.isEmpty && !isSubmitting
                            ) {
                                enrollAndSaveSchedule()
                            }
                            .padding(.top, AppSpacing.xs)
                        }
                        .padding(AppSpacing.md)
                    }
                }
            }
            .navigationTitle("Thêm lớp cho học sinh")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        stagedSessionsAcrossMonths.removeAll()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        enrollAndSaveSchedule()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.accentRose)
                    .disabled(activeClasses.isEmpty || isSubmitting)
                }
            }
            .onAppear {
                Task {
                    if viewModel.allClasses.isEmpty {
                        await viewModel.loadEnrolledClasses()
                    }
                    if let preselectedClassId, activeClasses.contains(where: { $0.id == preselectedClassId }) {
                        selectedClassId = preselectedClassId
                        applyDefaultDurationAndEnrollmentDate(for: preselectedClassId)
                    } else if let firstAvailable = activeClasses.first(where: { c in
                        !viewModel.activeEnrollmentItems.contains(where: { $0.classGroup.id == c.id })
                    }) ?? activeClasses.first {
                        selectedClassId = firstAvailable.id
                        applyDefaultDurationAndEnrollmentDate(for: firstAvailable.id)
                    }
                    if let existingCustom = viewModel.student.defaultPricePerSession, existingCustom > 0 {
                        useCustomPrice = true
                        customPrice = existingCustom
                    }
                    syncMonthDateRange(forOffset: 0)
                    await refreshClassSchedulePreview()
                }
            }
        }
    }

    // MARK: - Subviews cho StudentAddClassSheet

    private var classSelectionSectionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("1. Chọn lớp học", systemImage: "graduationcap.fill")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Button {
                        onRequestCreateNewClass()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Lớp mới")
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ForEach(activeClasses) { c in
                        let isSelected = (c.id == selectedClassId)
                        let isAlreadyActive = viewModel.activeEnrollmentItems.contains(where: { $0.classGroup.id == c.id })
                        Button {
                            guard selectedClassId != c.id else { return }
                            selectedClassId = c.id
                            stagedSessionsAcrossMonths.removeAll()
                            selectedMonthOffset = 0
                            applyDefaultDurationAndEnrollmentDate(for: c.id)
                            syncMonthDateRange(forOffset: 0)
                            Task {
                                await refreshClassSchedulePreview()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: c.colorHex))
                                    .frame(width: 14, height: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(c.name)
                                            .font(AppTypography.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(AppColors.primaryText)
                                        if isAlreadyActive {
                                            Text("Đang học")
                                                .font(AppTypography.font(size: 10))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
                                                .foregroundColor(AppColors.success)
                                        }
                                    }
                                    Text("\(c.subject.isEmpty ? "Chưa phân môn" : c.subject) • \(c.defaultPricePerSession.formattedVND)/buổi")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? AppColors.accentRose : AppColors.tertiaryText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .fill(isSelected ? AppColors.secondaryPink.opacity(0.45) : AppColors.surfaceSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(isSelected ? AppColors.accentRose : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var enrollmentAndPriceSectionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("2. Ngày bắt đầu & Đơn giá", systemImage: "banknote.fill")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                HStack {
                    Text("Ngày bắt đầu học")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    DatePicker("", selection: $enrolledAt, displayedComponents: [.date])
                        .labelsHidden()
                        .onChange(of: enrolledAt) { _, _ in
                            syncMonthDateRange(forOffset: selectedMonthOffset)
                            Task {
                                await refreshClassSchedulePreview()
                            }
                        }
                }

                Divider().background(AppColors.divider)

                Toggle(isOn: $useCustomPrice.animation(.easeInOut(duration: 0.15))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Áp dụng học phí riêng")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.primaryText)
                        if let c = selectedClassGroup, !useCustomPrice {
                            Text("Mặc định theo lớp: \(c.defaultPricePerSession.formattedVND)/buổi")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.success)
                        }
                    }
                }
                .tint(AppColors.accentRose)

                if useCustomPrice {
                    CurrencyTextField("Đơn giá riêng mỗi buổi (VND)", value: $customPrice)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(AppColors.surfaceSubtle)
                        )
                }
            }
        }
    }

    private var scheduleConfigSectionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("3. Lịch học", systemImage: "calendar.badge.clock")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                if !eligibleExistingSessions.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(AppColors.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đã có sẵn \(eligibleExistingSessions.count) buổi sắp tới của lớp")
                                .font(AppTypography.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primaryText)
                            Text("Học sinh sẽ tự động được thêm vào các buổi từ \(enrolledAt.formatted(date: .numeric, time: .omitted)).")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.success.opacity(0.1))
                    )
                }

                Toggle(
                    eligibleExistingSessions.isEmpty
                        ? "Tạo lịch học theo tháng"
                        : "Tạo thêm lịch tháng mới",
                    isOn: $isConfiguringMonthlySchedule.animation(.easeInOut(duration: 0.2))
                )
                .font(AppTypography.subheadline)
                .tint(AppColors.accentRose)

                if isConfiguringMonthlySchedule {
                    Divider().background(AppColors.divider)

                    // Chọn tháng
                    HStack {
                        Text("Tháng áp dụng")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        HStack(spacing: 10) {
                            Button {
                                if selectedMonthOffset > 0 {
                                    selectedMonthOffset -= 1
                                    syncMonthDateRange(forOffset: selectedMonthOffset)
                                }
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(selectedMonthOffset > 0 ? AppColors.accentRose : AppColors.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedMonthOffset <= 0)

                            Text(monthYearString(for: targetMonthDate))
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.accentRose)
                                .frame(minWidth: 100, alignment: .center)

                            Button {
                                selectedMonthOffset += 1
                                syncMonthDateRange(forOffset: selectedMonthOffset)
                                Task {
                                    await refreshOverlapWindowIfNeeded()
                                }
                            } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(AppColors.accentRose)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Chọn thứ trong tuần
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chọn thứ học trong tuần")
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
                                                .fill(isSelected ? AppColors.primaryPink : AppColors.surfaceSubtle)
                                        )
                                        .foregroundColor(isSelected ? .white : AppColors.primaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Khung giờ học
                    HStack(spacing: AppSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bắt đầu")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                            DatePicker("", selection: $sessionStartTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                                .onChange(of: sessionStartTime) { _, newStart in
                                    if let c = selectedClassGroup {
                                        sessionEndTime = newStart.addingTimeInterval(TimeInterval(c.sessionDurationMinutes * 60))
                                    }
                                }
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundColor(AppColors.tertiaryText)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Kết thúc")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                            DatePicker("", selection: $sessionEndTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.surfaceSubtle)
                    )

                    if !isTimeOrderValid {
                        Text("Giờ kết thúc phải sau giờ bắt đầu.")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                    }

                    // Khoảng ngày áp dụng
                    HStack {
                        Text("Từ ngày")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        DatePicker("", selection: $rangeStartDate, displayedComponents: [.date])
                            .labelsHidden()
                            .onChange(of: rangeStartDate) { _, newStart in
                                let minAllowed = Calendar.current.startOfDay(for: enrolledAt)
                                if newStart < minAllowed {
                                    rangeStartDate = minAllowed
                                }
                                if rangeEndDate < rangeStartDate {
                                    rangeEndDate = rangeStartDate
                                }
                            }
                        Spacer()
                        Text("Đến")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        DatePicker("", selection: $rangeEndDate, displayedComponents: [.date])
                            .labelsHidden()
                            .onChange(of: rangeEndDate) { _, newEnd in
                                if newEnd < rangeStartDate {
                                    rangeEndDate = rangeStartDate
                                }
                            }
                    }

                    if !currentMonthPreviewSessions.isEmpty {
                        Button {
                            stageCurrentMonthAndAdvanceToNextMonth()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.plus")
                                Text("Giữ \(currentMonthPreviewSessions.count) buổi & thiết lập tiếp tháng sau")
                                    .font(AppTypography.caption1)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .fill(AppColors.secondaryPink.opacity(0.6))
                            )
                            .foregroundColor(AppColors.accentRose)
                        }
                        .buttonStyle(.plain)
                    }

                    if let banner = showSavedContinueMonthBanner {
                        Text(banner)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.success)
                    }
                }
            }
        }
    }

    private var previewSessionsSectionCard: some View {
        let totalCount = eligibleExistingSessions.count + totalNewSessionsToCreate.count
        return AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("4. Xem trước lịch học", systemImage: "list.bullet.rectangle.portrait")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("\(totalCount) buổi")
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.secondaryPink))
                        .foregroundColor(AppColors.accentRose)
                }

                if !overlappingConflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.error)
                            Text("Trùng giờ dạy \(overlappingConflicts.count) buổi!")
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.error)
                        }
                        if let firstConflict = overlappingConflicts.first {
                            Text("Buổi \(firstConflict.newSession.startTime.formatted(date: .numeric, time: .shortened)) trùng với '\(firstConflict.conflictWith.title)'.")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.error)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.error.opacity(0.1))
                    )
                }

                if totalCount == 0 {
                    Text("Chưa có buổi học nào được chọn.")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)
                } else {
                    let previewList = (eligibleExistingSessions + totalNewSessionsToCreate)
                        .sorted { $0.startTime < $1.startTime }

                    ForEach(previewList.prefix(8)) { s in
                        HStack {
                            Circle()
                                .fill(AppColors.accentRose)
                                .frame(width: 6, height: 6)
                            Text(s.startTime.formatted(date: .numeric, time: .omitted))
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text("\(s.startTime.formatted(date: .omitted, time: .shortened)) – \(s.endTime.formatted(date: .omitted, time: .shortened))")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }

                    if previewList.count > 8 {
                        Text("... và \(previewList.count - 8) buổi tiếp theo.")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }

                    if !stagedSessionsAcrossMonths.isEmpty {
                        Button("Xóa các buổi đã giữ từ tháng trước", role: .destructive) {
                            stagedSessionsAcrossMonths.removeAll()
                            showSavedContinueMonthBanner = nil
                        }
                        .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    private func applyDefaultDurationAndEnrollmentDate(for classId: UUID) {
        if let c = activeClasses.first(where: { $0.id == classId }) {
            sessionEndTime = sessionStartTime.addingTimeInterval(TimeInterval(c.sessionDurationMinutes * 60))
        }
        if let activeEnrollment = viewModel.activeEnrollmentItems.first(where: { $0.classGroup.id == classId }) {
            enrolledAt = activeEnrollment.enrollment.enrolledAt
        } else {
            enrolledAt = Date()
        }
    }

    private func syncMonthDateRange(forOffset offset: Int) {
        let cal = Calendar.current
        let baseMonth = cal.date(from: cal.dateComponents([.year, .month], from: enrolledAt)) ?? enrolledAt
        let targetMonth = cal.date(byAdding: .month, value: offset, to: baseMonth) ?? baseMonth

        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: targetMonth)) ?? targetMonth
        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? targetMonth

        if offset == 0 {
            rangeStartDate = max(cal.startOfDay(for: enrolledAt), monthStart)
        } else {
            rangeStartDate = monthStart
        }
        rangeEndDate = max(rangeStartDate, monthEnd)
    }

    private func refreshClassSchedulePreview() async {
        let allForClass = await viewModel.fetchAllClassSessions(forClassId: selectedClassId)
        existingClassSessions = allForClass
        if preselectedClassId != nil {
            isConfiguringMonthlySchedule = true
        } else if !eligibleExistingSessions.isEmpty {
            isConfiguringMonthlySchedule = false
        }
        await refreshOverlapWindowIfNeeded()
    }

    private func refreshOverlapWindowIfNeeded() async {
        let cal = Calendar.current
        let winStart = cal.startOfDay(for: enrolledAt)
        let monthsAhead = max(12, selectedMonthOffset + 3)
        let winEnd = cal.date(byAdding: .month, value: monthsAhead, to: winStart) ?? winStart
        allSystemSessionsInWindow = await viewModel.fetchAllSessionsForOverlapCheck(from: winStart, to: winEnd)
    }

    private func stageCurrentMonthAndAdvanceToNextMonth() {
        let currentBatch = currentMonthPreviewSessions
        let cal = Calendar.current
        for s in currentBatch {
            let exists = stagedSessionsAcrossMonths.contains { existing in
                existing.classId == s.classId &&
                cal.isDate(existing.startTime, inSameDayAs: s.startTime) &&
                abs(existing.startTime.timeIntervalSince(s.startTime)) < 120
            }
            if !exists {
                stagedSessionsAcrossMonths.append(s)
            }
        }
        let currentLabel = monthYearString(for: targetMonthDate)
        selectedMonthOffset += 1
        syncMonthDateRange(forOffset: selectedMonthOffset)
        Task {
            await refreshOverlapWindowIfNeeded()
        }
        showSavedContinueMonthBanner = "Đã giữ \(currentBatch.count) buổi của \(currentLabel). Tiếp tục chọn lịch cho \(monthYearString(for: targetMonthDate))."
    }

    private func monthYearString(for date: Date) -> String {
        let comp = Calendar.current.dateComponents([.month, .year], from: date)
        return "Tháng \(comp.month ?? 1)/\(comp.year ?? 2026)"
    }

    private func enrollAndSaveSchedule() {
        guard !isSubmitting else { return }
        localError = nil

        if useCustomPrice && customPrice <= 0 {
            localError = "Vui lòng nhập đơn giá riêng lớn hơn 0 VND hoặc chọn đơn giá theo lớp."
            return
        }

        if isConfiguringMonthlySchedule && !isTimeOrderValid {
            localError = "Giờ kết thúc phải sau giờ bắt đầu."
            return
        }

        if isConfiguringMonthlySchedule && !overlappingConflicts.isEmpty {
            localError = "Có buổi học bị trùng giờ dạy với lịch hiện có. Vui lòng điều chỉnh giờ học."
            return
        }

        isSubmitting = true
        let sessionsToSave = isConfiguringMonthlySchedule ? totalNewSessionsToCreate : []

        Task {
            do {
                try await viewModel.enrollStudentInClass(
                    classId: selectedClassId,
                    enrolledAt: enrolledAt,
                    useCustomPrice: useCustomPrice,
                    customPrice: useCustomPrice ? customPrice : nil,
                    newMonthlySessionsToCreate: sessionsToSave
                )
                isSubmitting = false
                onCompleted?()
                dismiss()
            } catch {
                localError = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
