import SwiftUI
import SwiftData

/// Màn hình gốc kết nối ModelContainer SwiftData, Quản lý Phiên Đăng nhập (`UserSessionManager`) và `MainTabView`
public struct EduPetalRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var sessionManager = UserSessionManager.shared
    @State private var localizationManager = LocalizationManager.shared

    public init() {
        AppTypography.registerCustomFontIfNeeded()
        LocalNotificationService.shared.configureDelegateIfNeeded()
    }

    public var body: some View {
        Group {
            if let activeUser = sessionManager.currentUser {
                EduPetalAppContainer(
                    modelContext: modelContext,
                    activeUser: activeUser
                )
                .id("\(activeUser.userId)_\(sessionManager.sessionGeneration)")
            } else {
                LoginView(sessionManager: sessionManager)
            }
        }
        .font(AppTypography.body)
        .environment(\.locale, localizationManager.locale)
        .preferredColorScheme(themeManager.colorScheme)
        .onAppear {
            themeManager.applyToAllWindows()
        }
        .onChange(of: themeManager.currentTheme) { _, _ in
            themeManager.applyToAllWindows()
        }
        .onOpenURL { url in
            _ = GoogleOAuthService.shared.handleOpenURL(url)
        }
    }
}

@MainActor
private final class SessionWorkspaceDependencies {
    let ownerId: String
    let studentRepo: StudentRepository
    let classRepo: ClassRepository
    let scheduleRepo: ScheduleRepository
    let financeRepo: FinanceRepository
    let assignmentRepo: AssignmentRepository
    let gradeRepo: GradeRepository

    let homeViewModel: HomeViewModel
    let studentListViewModel: StudentListViewModel
    let scheduleViewModel: ScheduleViewModel
    let classListViewModel: ClassListViewModel
    let financeViewModel: FinanceViewModel

    init(modelContext: ModelContext, ownerId: String) {
        self.ownerId = ownerId
        let sRepo = StudentRepository(modelContext: modelContext, ownerId: ownerId)
        let cRepo = ClassRepository(modelContext: modelContext, ownerId: ownerId)
        let schRepo = ScheduleRepository(modelContext: modelContext, ownerId: ownerId)
        let fRepo = FinanceRepository(modelContext: modelContext, ownerId: ownerId)
        let aRepo = AssignmentRepository(modelContext: modelContext, ownerId: ownerId)
        let gRepo = GradeRepository(modelContext: modelContext, ownerId: ownerId)

        self.studentRepo = sRepo
        self.classRepo = cRepo
        self.scheduleRepo = schRepo
        self.financeRepo = fRepo
        self.assignmentRepo = aRepo
        self.gradeRepo = gRepo

        self.homeViewModel = HomeViewModel(
            studentRepository: sRepo,
            classRepository: cRepo,
            scheduleRepository: schRepo,
            assignmentRepository: aRepo,
            financeRepository: fRepo,
            gradeRepository: gRepo
        )

        self.studentListViewModel = StudentListViewModel(
            studentRepository: sRepo,
            classRepository: cRepo,
            scheduleRepository: schRepo,
            financeRepository: fRepo
        )

        self.scheduleViewModel = ScheduleViewModel(
            scheduleRepository: schRepo,
            classRepository: cRepo
        )

        self.classListViewModel = ClassListViewModel(
            classRepository: cRepo,
            scheduleRepository: schRepo,
            financeRepository: fRepo
        )

        self.financeViewModel = FinanceViewModel(
            financeRepository: fRepo,
            studentRepository: sRepo,
            scheduleRepository: schRepo,
            classRepository: cRepo
        )
    }
}

private struct EduPetalAppContainer: View {
    let modelContext: ModelContext
    let activeUser: AuthenticatedUser

    @State private var workspace: SessionWorkspaceDependencies?
    @State private var unownedLegacyRecordsCount: Int = 0
    @State private var isShowingLegacyMigrationAlert: Bool = false

    private var resolvedWorkspace: SessionWorkspaceDependencies {
        if let workspace, workspace.ownerId == activeUser.userId {
            return workspace
        }
        return SessionWorkspaceDependencies(modelContext: modelContext, ownerId: activeUser.userId)
    }

    var body: some View {
        let deps = resolvedWorkspace
        MainTabView(
            homeViewModel: deps.homeViewModel,
            studentListViewModel: deps.studentListViewModel,
            scheduleViewModel: deps.scheduleViewModel,
            classListViewModel: deps.classListViewModel,
            financeViewModel: deps.financeViewModel,
            studentRepository: deps.studentRepo,
            classRepository: deps.classRepo,
            scheduleRepository: deps.scheduleRepo,
            financeRepository: deps.financeRepo,
            gradeRepository: deps.gradeRepo,
            assignmentRepository: deps.assignmentRepo
        )
        .task(id: activeUser.userId) {
            if workspace == nil || workspace?.ownerId != activeUser.userId {
                workspace = deps
            }
            let migrationService = LegacyDataMigrationService.shared
            if !migrationService.hasDismissedMigrationPrompt(forOwnerId: activeUser.userId) {
                let count = migrationService.countUnownedRecords(in: modelContext)
                if count > 0 {
                    unownedLegacyRecordsCount = count
                    isShowingLegacyMigrationAlert = true
                }
            }
        }
        .alert(
            L("Phát hiện dữ liệu cục bộ chưa gắn tài khoản", "Unassigned Local Data Detected"),
            isPresented: $isShowingLegacyMigrationAlert
        ) {
            Button(L("Xác nhận chuyển vào tài khoản này", "Assign to This Account")) {
                _ = try? LegacyDataMigrationService.shared.claimUnownedData(
                    forOwnerId: activeUser.userId,
                    in: modelContext
                )
                LegacyDataMigrationService.shared.setDismissedMigrationPrompt(
                    true,
                    forOwnerId: activeUser.userId
                )
                Task {
                    await deps.homeViewModel.loadDashboard()
                    await deps.studentListViewModel.loadData()
                    await deps.scheduleViewModel.loadData()
                    await deps.classListViewModel.loadData()
                    await deps.financeViewModel.loadData()
                }
            }
            Button(L("Giữ tách biệt (Tài khoản mới trống)", "Keep Separate (Start Fresh)"), role: .cancel) {
                LegacyDataMigrationService.shared.setDismissedMigrationPrompt(
                    true,
                    forOwnerId: activeUser.userId
                )
            }
        } message: {
            Text(
                L(
                    "Có \(unownedLegacyRecordsCount) bản ghi cũ được tạo trước khi đăng nhập. Để đảm bảo cô lập dữ liệu, ứng dụng không tự động gán dữ liệu này. Bạn có muốn chuyển quyền sở hữu dữ liệu cũ sang tài khoản \(activeUser.email) không?",
                    "Found \(unownedLegacyRecordsCount) records created before sign-in. To ensure strict data isolation, they are not automatically merged. Would you like to assign them to \(activeUser.email)?"
                )
            )
        }
    }
}
