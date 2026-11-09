import SwiftUI

/// Màn hình Danh sách Lớp học (Module 3 — Class Management)
/// Chỉ tập trung Quản lý lớp (Đang mở / Đã lưu trữ), xem số học sinh đang có và xóa lớp ở mục lưu trữ kèm kiểm tra học phí
public struct ClassListView: View {
    @Environment(\.dismiss) private var dismiss
    @State public var viewModel: ClassListViewModel
    @State private var isShowingAddSheet: Bool = false
    @State private var newlyCreatedClass: ClassGroupEntity? = nil

    private let classRepository: ClassRepositoryProtocol
    private let studentRepository: StudentRepositoryProtocol
    private let scheduleRepository: ScheduleRepositoryProtocol?
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?
    public let showsDismissButton: Bool

    public init(
        viewModel: ClassListViewModel,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil,
        showsDismissButton: Bool = false
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
        self.showsDismissButton = showsDismissButton
    }

    public var body: some View {
        NavigationStack {
            mainContentView
            .searchable(text: $viewModel.searchQuery, prompt: L("Tìm theo tên lớp, môn học...", "Search by class name, subject..."))
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Lớp học", "Classes"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Đóng", "Close")) {
                            dismiss()
                        }
                        .foregroundColor(AppColors.accentRose)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L("Thêm lớp", "Add Class"))
                        }
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                ClassEditView { newClass in
                    Task {
                        let saved = await viewModel.saveClass(newClass)
                        if saved {
                            newlyCreatedClass = newClass
                        }
                    }
                }
            }
            .navigationDestination(item: $newlyCreatedClass) { createdClass in
                ClassDetailView(
                    viewModel: ClassDetailViewModel(
                        classGroup: createdClass,
                        classRepository: classRepository,
                        studentRepository: studentRepository,
                        scheduleRepository: scheduleRepository,
                        financeRepository: financeRepository
                    ),
                    classRepository: classRepository,
                    studentRepository: studentRepository,
                    scheduleRepository: scheduleRepository,
                    financeRepository: financeRepository,
                    gradeRepository: gradeRepository,
                    assignmentRepository: assignmentRepository
                )
            }
            // Hộp thoại 1: Xác nhận chắc chắn xóa khi lớp KHÔNG còn nợ học phí
            .alert(
                "Chắc chắn xóa lớp học?",
                isPresented: Binding(
                    get: { viewModel.classPendingSimpleDelete != nil },
                    set: { if !$0 { viewModel.classPendingSimpleDelete = nil } }
                ),
                presenting: viewModel.classPendingSimpleDelete
            ) { classToDelete in
                Button("Chắc chắn xóa", role: .destructive) {
                    Task {
                        await viewModel.confirmDeleteClass(id: classToDelete.id, confirmPaidIfUnpaid: false)
                    }
                }
                Button("Hủy", role: .cancel) {
                    viewModel.classPendingSimpleDelete = nil
                }
            } message: { classToDelete in
                Text("Bạn có chắc chắn muốn xóa vĩnh viễn lớp '\(classToDelete.name)' không? Hành động này không thể hoàn tác.")
            }
            // Hộp thoại 2: Lớp còn học phí chưa thanh toán -> nhắc chưa thanh toán & yêu cầu xác nhận đã thanh toán mới cho xóa
            .alert(
                "Còn học phí chưa thanh toán",
                isPresented: Binding(
                    get: { viewModel.classPendingUnpaidDelete != nil },
                    set: { if !$0 { viewModel.classPendingUnpaidDelete = nil } }
                ),
                presenting: viewModel.classPendingUnpaidDelete
            ) { prompt in
                Button("Xác nhận đã thanh toán & Xóa lớp", role: .destructive) {
                    Task {
                        await viewModel.confirmDeleteClass(id: prompt.classGroup.id, confirmPaidIfUnpaid: true)
                    }
                }
                Button("Chưa thanh toán (Hủy)", role: .cancel) {
                    viewModel.classPendingUnpaidDelete = nil
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

    private var mainContentView: some View {
        let activeCount = viewModel.classes.filter { !$0.isArchived }.count
        let archivedCount = viewModel.classes.filter { $0.isArchived }.count

        return VStack(spacing: 0) {
            Picker(L("Trạng thái", "Status"), selection: $viewModel.showArchived) {
                Text(L("Đang mở (\(activeCount))", "Active (\(activeCount))")).tag(false)
                Text(L("Đã lưu trữ (\(archivedCount))", "Archived (\(archivedCount))")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)

            if viewModel.isLoading && viewModel.classes.isEmpty {
                Spacer()
                ProgressView(L("Đang tải danh sách lớp...", "Loading classes..."))
                Spacer()
            } else if viewModel.filteredClasses.isEmpty {
                EmptyStateView(
                    icon: viewModel.showArchived ? "archivebox" : "graduationcap.fill",
                    title: viewModel.showArchived
                        ? L("Chưa có lớp lưu trữ", "No Archived Classes")
                        : L("Chưa có lớp học", "No Classes Yet"),
                    message: viewModel.showArchived
                        ? L("Danh sách lớp đã lưu trữ trống.", "No archived classes.")
                        : L("Nhấn Thêm lớp để tạo lớp học mới.", "Tap Add Class to create a new class."),
                    actionTitle: viewModel.showArchived ? nil : L("Thêm lớp", "Add Class")
                ) {
                    isShowingAddSheet = true
                }
            } else {
                List {
                    ForEach(viewModel.filteredClasses) { classGroup in
                        classListRow(classGroup)
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
    }

    private func classListRow(_ classGroup: ClassGroupEntity) -> some View {
        ZStack {
            NavigationLink {
                ClassDetailView(
                    viewModel: ClassDetailViewModel(
                        classGroup: classGroup,
                        classRepository: classRepository,
                        studentRepository: studentRepository,
                        scheduleRepository: scheduleRepository,
                        financeRepository: financeRepository
                    ),
                    classRepository: classRepository,
                    studentRepository: studentRepository,
                    scheduleRepository: scheduleRepository,
                    financeRepository: financeRepository,
                    gradeRepository: gradeRepository,
                    assignmentRepository: assignmentRepository
                )
            } label: {
                EmptyView()
            }
            .opacity(0)

            classCard(classGroup)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if classGroup.isArchived {
                Button(role: .destructive) {
                    Task {
                        await viewModel.requestDeleteArchivedClass(classGroup)
                    }
                } label: {
                    Label("Xóa lớp", systemImage: "trash")
                }
                .tint(AppColors.error)

                Button {
                    Task {
                        await viewModel.restoreClass(id: classGroup.id)
                    }
                } label: {
                    Label("Khôi phục", systemImage: "arrow.uturn.backward.circle")
                }
                .tint(AppColors.success)
            } else {
                Button {
                    Task {
                        await viewModel.archiveClass(id: classGroup.id)
                    }
                } label: {
                    Label("Lưu trữ", systemImage: "archivebox.fill")
                }
                .tint(AppColors.accentRose)
            }
        }
    }

    private func classCard(_ c: ClassGroupEntity) -> some View {
        let count = viewModel.studentCounts[c.id] ?? 0
        let nextSession = viewModel.nextUpcomingSessions[c.id]
        let trimmedSubject = c.subject.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Hàng 1: Tên lớp + Môn học (nếu có) + Số học sinh đang tham gia
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Circle()
                        .fill(Color(hex: c.colorHex))
                        .frame(width: 12, height: 12)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name)
                            .font(AppTypography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                            .multilineTextAlignment(.leading)

                        if !trimmedSubject.isEmpty {
                            Text(trimmedSubject)
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                        Text(L("\(count) học sinh", "\(count) students"))
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppColors.secondaryPink))
                    .foregroundColor(AppColors.accentRose)
                    .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                        .padding(.top, 5)
                }

                // Hàng 2: Buổi dạy tiếp theo
                HStack(spacing: 6) {
                    Image(systemName: nextSession != nil ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(nextSession != nil ? AppColors.info : AppColors.secondaryText)

                    if let nextSession {
                        Text(
                            L(
                                "Buổi tiếp theo: \(nextSession.startTime.formatted(date: .abbreviated, time: .shortened))",
                                "Next session: \(nextSession.startTime.formatted(date: .abbreviated, time: .shortened))"
                            )
                        )
                        .font(AppTypography.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    } else {
                        Text(
                            c.isArchived
                            ? L("Lớp đã lưu trữ", "Archived class")
                            : L("Chưa có buổi dạy sắp tới", "No upcoming sessions")
                        )
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(AppColors.surfaceSubtle)
                )

                // Hàng 3: Đơn giá mặc định mỗi buổi & Thời lượng
                HStack {
                    HStack(spacing: 4) {
                        Text(L("Đơn giá:", "Price:"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        Text(L("\(c.defaultPricePerSession.formattedVND)/buổi", "\(c.defaultPricePerSession.formattedVND)/session"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.accentRose)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(L("\(c.sessionDurationMinutes) phút/buổi", "\(c.sessionDurationMinutes) mins/session"))
                    }
                    .font(AppTypography.caption1)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                }

                // Hàng 4: Nút thao tác trực tiếp trên thẻ khi ở mục Đã lưu trữ
                if c.isArchived {
                    Divider()
                        .background(AppColors.divider)

                    HStack(spacing: AppSpacing.sm) {
                        Button {
                            Task {
                                await viewModel.restoreClass(id: c.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                Text(L("Khôi phục lớp", "Restore"))
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
                                await viewModel.requestDeleteArchivedClass(c)
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
}
