import SwiftUI

/// Màn hình Danh sách Học sinh (Module 2 — Student Management)
public struct StudentListView: View {
    @State public var viewModel: StudentListViewModel
    @State private var isShowingAddSheet: Bool = false

    private let studentRepository: StudentRepositoryProtocol
    private let classRepository: ClassRepositoryProtocol
    private let scheduleRepository: ScheduleRepositoryProtocol?
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?

    public init(
        viewModel: StudentListViewModel,
        studentRepository: StudentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.studentRepository = studentRepository
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
        self.gradeRepository = gradeRepository
        self.assignmentRepository = assignmentRepository
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Segment (Đang học / Lưu trữ)
                Picker(L("Trạng thái", "Status"), selection: $viewModel.showArchived) {
                    Text(L("Đang học", "Active")).tag(false)
                    Text(L("Đã lưu trữ", "Archived")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView(L("Đang tải danh sách...", "Loading list..."))
                    Spacer()
                } else if viewModel.filteredStudents.isEmpty {
                    EmptyStateView(
                        icon: viewModel.showArchived ? "archivebox" : "person.crop.circle.badge.plus",
                        title: viewModel.showArchived ? L("Chưa có học sinh lưu trữ", "No Archived Students") : L("Chưa có học sinh", "No Students Yet"),
                        message: viewModel.showArchived
                            ? L("Danh sách học sinh đã lưu trữ trống.", "No archived students.")
                            : L("Nhấn Thêm học sinh để tạo hồ sơ mới.", "Tap Add Student to create a profile."),
                        actionTitle: viewModel.showArchived ? nil : L("Thêm học sinh", "Add Student")
                    ) {
                        isShowingAddSheet = true
                    }
                } else {
                    List {
                        ForEach(viewModel.filteredStudents) { student in
                            NavigationLink {
                                StudentDetailView(
                                    viewModel: StudentDetailViewModel(
                                        student: student,
                                        studentRepository: studentRepository,
                                        classRepository: classRepository,
                                        scheduleRepository: scheduleRepository,
                                        gradeRepository: gradeRepository,
                                        assignmentRepository: assignmentRepository,
                                        financeRepository: financeRepository
                                    )
                                )
                            } label: {
                                studentRow(student)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if student.isArchived {
                                    // Nút Xóa vĩnh viễn (chỉ xuất hiện trong mục Đã lưu trữ)
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.requestDelete(student: student)
                                        }
                                    } label: {
                                        Label("Xóa vĩnh viễn", systemImage: "trash.fill")
                                    }
                                    .tint(AppColors.error)

                                    // Nút Khôi phục
                                    Button {
                                        Task {
                                            await viewModel.restoreStudent(id: student.id)
                                        }
                                    } label: {
                                        Label("Khôi phục", systemImage: "arrow.uturn.backward.circle.fill")
                                    }
                                    .tint(AppColors.success)
                                } else {
                                    // Nút Lưu trữ (Thao tác vuốt mượt mà kiểu Messenger)
                                    Button {
                                        Task {
                                            await viewModel.requestArchive(student: student)
                                        }
                                    } label: {
                                        Label("Lưu trữ", systemImage: "archivebox.fill")
                                    }
                                    .tint(AppColors.accentRose)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    #if canImport(UIKit)
                    .refreshable {
                        await viewModel.loadData()
                    }
                    #endif
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: Text(L("Tìm theo tên, SĐT, email...", "Search by name, phone, email...")))
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Học sinh", "Students"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L("Thêm học sinh", "Add Student"))
                        }
                        .font(AppTypography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                StudentEditView { newStudent in
                    Task {
                        try? await studentRepository.saveStudent(newStudent)
                        await viewModel.loadData()
                    }
                }
            }
            .confirmationDialog(
                "Xác nhận xóa học sinh",
                isPresented: Binding(
                    get: { viewModel.studentToDelete != nil },
                    set: { if !$0 { viewModel.studentToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.studentToDelete
            ) { student in
                Button("Xóa vĩnh viễn", role: .destructive) {
                    Task {
                        await viewModel.executeDelete(id: student.id)
                    }
                }
                Button("Hủy", role: .cancel) {
                    viewModel.studentToDelete = nil
                }
            } message: { student in
                Text("Bạn có chắc chắn muốn xóa học sinh \(student.fullName)? Thao tác này không thể hoàn tác.")
            }
            .alert(
                "Không thể xóa học sinh",
                isPresented: Binding(
                    get: { viewModel.studentBlockedFromDelete != nil },
                    set: { if !$0 { viewModel.studentBlockedFromDelete = nil } }
                ),
                presenting: viewModel.studentBlockedFromDelete
            ) { item in
                Button("Chuyển vào Lưu trữ") {
                    Task {
                        await viewModel.executeArchive(id: item.student.id)
                    }
                }
                Button("Đã hiểu", role: .cancel) {
                    viewModel.studentBlockedFromDelete = nil
                }
            } message: { item in
                if item.debtAmount > 0 {
                    Text("Còn nợ \(item.debtAmount.formattedVND). Hãy lưu trữ thay vì xóa.")
                } else {
                    Text("Đã có lịch sử học phí. Hãy lưu trữ thay vì xóa.")
                }
            }
            .alert(
                "Lưu trữ học sinh",
                isPresented: Binding(
                    get: { viewModel.studentToArchiveWithUpcomingSessions != nil },
                    set: { if !$0 { viewModel.studentToArchiveWithUpcomingSessions = nil } }
                ),
                presenting: viewModel.studentToArchiveWithUpcomingSessions
            ) { item in
                Button("Tiếp tục lưu trữ") {
                    Task {
                        await viewModel.executeArchive(id: item.student.id)
                    }
                }
                Button("Hủy", role: .cancel) {
                    viewModel.studentToArchiveWithUpcomingSessions = nil
                }
            } message: { item in
                Text("Còn \(item.upcomingCount) buổi sắp tới. Lưu trữ không xóa lịch dạy.")
            }
            .task {
                await viewModel.loadData()
            }
            .onAppear {
                Task {
                    await viewModel.loadData()
                }
            }
        }
    }

    private func studentRow(_ student: StudentEntity) -> some View {
        let studentClasses = viewModel.enrolledClasses(for: student.id)

        return AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
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
                                .lineLimit(1)

                            if student.isArchived {
                                Text(L("Đã lưu trữ", "Archived"))
                                    .font(AppTypography.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(AppColors.surfaceSubtle))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }

                        if !student.phoneNumber.isEmpty {
                            Text(student.phoneNumber)
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.secondaryText)
                        } else if !student.parentPhone.isEmpty {
                            Text("PH: \(student.parentPhone)")
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.secondaryText)
                        } else {
                            Text(
                                studentClasses.isEmpty
                                    ? L("Chưa tham gia lớp học", "Not enrolled in any class")
                                    : L("Đang tham gia \(studentClasses.count) lớp", "Enrolled in \(studentClasses.count) classes")
                            )
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.secondaryText)
                        }
                    }

                    Spacer(minLength: 4)

                    // Huy hiệu số lớp tham gia ngay trên thẻ học sinh
                    HStack(spacing: 4) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            studentClasses.isEmpty
                                ? L("0 lớp", "0 classes")
                                : L("\(studentClasses.count) lớp", "\(studentClasses.count) classes")
                        )
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            studentClasses.isEmpty
                                ? AppColors.surfaceSubtle
                                : AppColors.secondaryPink
                        )
                    )
                    .foregroundColor(
                        studentClasses.isEmpty
                            ? AppColors.secondaryText
                            : AppColors.accentRose
                    )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                }

                // Danh sách thông tin chi tiết từng lớp đang tham gia (Tên lớp, Môn học, Đơn giá/buổi)
                if !studentClasses.isEmpty {
                    Divider()
                        .background(AppColors.divider.opacity(0.6))

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(studentClasses) { cls in
                            let effectivePrice = student.defaultPricePerSession ?? cls.defaultPricePerSession
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: cls.colorHex))
                                    .frame(width: 8, height: 8)

                                Text(cls.name)
                                    .font(AppTypography.caption1)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)

                                if !cls.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("• \(cls.subject)")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text("\(effectivePrice.formattedVND)/\(L("buổi", "sess"))")
                                    .font(AppTypography.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.accentRose)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: cls.colorHex).opacity(0.08))
                            )
                        }
                    }
                } else if let customPrice = student.defaultPricePerSession {
                    HStack {
                        Text(L("Đơn giá riêng:", "Custom fee:"))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("\(customPrice.formattedVND)/\(L("buổi", "session"))")
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                    }
                }

                // Nút thao tác trực tiếp trên thẻ khi ở mục Đã lưu trữ (Swipe chỉ là cách phụ)
                if student.isArchived {
                    Divider()
                        .background(AppColors.divider.opacity(0.6))

                    HStack(spacing: AppSpacing.sm) {
                        Button {
                            Task {
                                await viewModel.restoreStudent(id: student.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                Text(L("Khôi phục", "Restore"))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: AppRadius.sm).fill(AppColors.successBackground))
                            .foregroundColor(AppColors.success)
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            Task {
                                await viewModel.requestDelete(student: student)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text(L("Xóa vĩnh viễn", "Delete Permanently"))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: AppRadius.sm).fill(AppColors.errorBackground))
                            .foregroundColor(AppColors.error)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if let last = parts.last, let first = last.first {
            return String(first).uppercased()
        }
        return "EP"
    }
}

