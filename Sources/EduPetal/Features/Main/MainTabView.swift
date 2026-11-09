import SwiftUI

/// 5 Tab điều hướng cốt lõi của EduPetal
public enum AppTab: Int, CaseIterable, Identifiable, Sendable {
    case home = 0
    case students = 1
    case schedule = 2
    case classes = 3
    case finance = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .home: return L("Trang chủ", "Home")
        case .students: return L("Học sinh", "Students")
        case .schedule: return L("Lịch dạy", "Schedule")
        case .classes: return L("Lớp học", "Classes")
        case .finance: return L("Học phí", "Tuition")
        }
    }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .students: return "person.2.fill"
        case .schedule: return "calendar"
        case .classes: return "graduationcap.fill"
        case .finance: return "dollarsign.circle.fill"
        }
    }
}

/// Màn hình điều hướng gốc (Root Navigation Container) gồm 5 tab chính
public struct MainTabView: View {
    @State private var navigationState = AppNavigationState.shared
    @State private var localizationManager = LocalizationManager.shared
    @State private var selectedTab: AppTab = .home

    public let homeViewModel: HomeViewModel
    public let studentListViewModel: StudentListViewModel
    public let scheduleViewModel: ScheduleViewModel
    public let classListViewModel: ClassListViewModel
    public let financeViewModel: FinanceViewModel

    private let studentRepository: StudentRepositoryProtocol
    private let classRepository: ClassRepositoryProtocol
    private let scheduleRepository: ScheduleRepositoryProtocol
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?

    public init(
        homeViewModel: HomeViewModel,
        studentListViewModel: StudentListViewModel,
        scheduleViewModel: ScheduleViewModel,
        classListViewModel: ClassListViewModel,
        financeViewModel: FinanceViewModel,
        studentRepository: StudentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil
    ) {
        self.homeViewModel = homeViewModel
        self.studentListViewModel = studentListViewModel
        self.scheduleViewModel = scheduleViewModel
        self.classListViewModel = classListViewModel
        self.financeViewModel = financeViewModel
        self.studentRepository = studentRepository
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
        self.gradeRepository = gradeRepository
        self.assignmentRepository = assignmentRepository
    }

    public var body: some View {
        let _ = localizationManager.currentLanguage
        TabView(selection: $selectedTab) {
            HomeView(viewModel: homeViewModel)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.iconName)
                }
                .tag(AppTab.home)

            StudentListView(
                viewModel: studentListViewModel,
                studentRepository: studentRepository,
                classRepository: classRepository,
                scheduleRepository: scheduleRepository,
                financeRepository: financeRepository,
                gradeRepository: gradeRepository,
                assignmentRepository: assignmentRepository
            )
            .tabItem {
                Label(AppTab.students.title, systemImage: AppTab.students.iconName)
            }
            .tag(AppTab.students)

            ClassListView(
                viewModel: classListViewModel,
                classRepository: classRepository,
                studentRepository: studentRepository,
                scheduleRepository: scheduleRepository,
                financeRepository: financeRepository,
                gradeRepository: gradeRepository,
                assignmentRepository: assignmentRepository,
                showsDismissButton: false
            )
            .tabItem {
                Label(AppTab.classes.title, systemImage: AppTab.classes.iconName)
            }
            .tag(AppTab.classes)

            ScheduleCalendarView(
                viewModel: scheduleViewModel,
                scheduleRepository: scheduleRepository,
                classRepository: classRepository,
                studentRepository: studentRepository,
                financeRepository: financeRepository,
                gradeRepository: gradeRepository,
                assignmentRepository: assignmentRepository
            )
            .tabItem {
                Label(AppTab.schedule.title, systemImage: AppTab.schedule.iconName)
            }
            .tag(AppTab.schedule)

            FinanceDashboardView(viewModel: financeViewModel)
                .tabItem {
                    Label(AppTab.finance.title, systemImage: AppTab.finance.iconName)
                }
                .tag(AppTab.finance)
        }
        .tint(AppColors.primaryPink)
        .onChange(of: selectedTab) { _, newTab in
            if navigationState.selectedTabRaw != newTab.rawValue {
                navigationState.selectedTabRaw = newTab.rawValue
            }
        }
        .onChange(of: navigationState.selectedTabRaw) { _, newRaw in
            if let targetTab = AppTab(rawValue: newRaw), self.selectedTab != targetTab {
                self.selectedTab = targetTab
            }
        }
        .onChange(of: navigationState.targetScheduleDate) { _, newDate in
            if let date = newDate {
                scheduleViewModel.selectedDate = date
                self.selectedTab = .schedule
            }
        }
        .onChange(of: navigationState.targetSessionId) { _, newSessionId in
            if newSessionId != nil {
                self.selectedTab = .schedule
            }
        }
        .onAppear {
            if let targetDate = navigationState.targetScheduleDate {
                scheduleViewModel.selectedDate = targetDate
            }
            if navigationState.targetSessionId != nil {
                self.selectedTab = .schedule
            } else if let targetTab = AppTab(rawValue: navigationState.selectedTabRaw) {
                self.selectedTab = targetTab
            }
        }
    }
}
