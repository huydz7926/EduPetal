import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Lịch dạy thiết kế theo phong cách trang chủ SnapSpend (Dashboard + Memory Calendar + Day/Month Strip)
public struct ScheduleCalendarView: View {
    public enum ScheduleTimeMode: String, CaseIterable {
        case day = "Ngày"
        case month = "Tháng"

        public var localizedTitle: String {
            switch self {
            case .day: return L("Ngày", "Day")
            case .month: return L("Tháng", "Month")
            }
        }
    }

    public enum ScheduleDisplayLayout {
        case calendar
        case list
    }

    @State public var viewModel: ScheduleViewModel
    @State private var navigationState = AppNavigationState.shared
    @State private var timeMode: ScheduleTimeMode = .month
    @State private var displayLayout: ScheduleDisplayLayout = .calendar
    @State private var selectedClassFilterId: UUID? = nil
    @State private var isShowingAddSheet: Bool = false
    @State private var deepLinkedSession: TeachingSessionEntity? = nil

    private let scheduleRepository: ScheduleRepositoryProtocol
    private let classRepository: ClassRepositoryProtocol
    private let studentRepository: StudentRepositoryProtocol
    private let financeRepository: FinanceRepositoryProtocol?
    private let gradeRepository: GradeRepositoryProtocol?
    private let assignmentRepository: AssignmentRepositoryProtocol?

    private let calendar = Calendar.current
    private var weekdayHeaders: [String] {
        LocalizationManager.currentLanguageThreadSafe == .english
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    }

    public init(
        viewModel: ScheduleViewModel,
        scheduleRepository: ScheduleRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol,
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

    // MARK: - Computed Sessions

    private var filteredSessions: [TeachingSessionEntity] {
        guard let classId = selectedClassFilterId else {
            return viewModel.sessions
        }
        return viewModel.sessions.filter { $0.classId == classId }
    }

    private var sessionsInSelectedMonth: [TeachingSessionEntity] {
        filteredSessions
            .filter { calendar.isDate($0.startTime, equalTo: viewModel.selectedDate, toGranularity: .month) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var sessionsInSelectedDay: [TeachingSessionEntity] {
        filteredSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: viewModel.selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var activeSummarySessions: [TeachingSessionEntity] {
        timeMode == .month ? sessionsInSelectedMonth : sessionsInSelectedDay
    }

    private var scheduledCount: Int {
        activeSummarySessions.filter { $0.status == .scheduled }.count
    }

    private var completedCount: Int {
        activeSummarySessions.filter { $0.status == .completed }.count
    }

    private var showTodayButton: Bool {
        if timeMode == .day {
            return !calendar.isDateInToday(viewModel.selectedDate)
        } else {
            return !calendar.isDate(viewModel.selectedDate, equalTo: Date(), toGranularity: .month)
                || !calendar.isDateInToday(viewModel.selectedDate)
        }
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. SnapSpend-style Toolbar & Horizontal Month/Day Picker Strip
                snapSpendToolbarAndStrip
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .background(AppColors.background)

                // 2. Main Scroll Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 2 Thẻ KPI Sắp tới & Hoàn thành (SnapSpend TransactionSummaryCardsRow style)
                        summaryCardsRow
                            .padding(.horizontal, 16)

                        if viewModel.isLoading && viewModel.sessions.isEmpty {
                            ProgressView("Đang tải lịch dạy...")
                                .padding(.vertical, 48)
                        } else if timeMode == .month && displayLayout == .calendar {
                            // Lịch Tháng dạng lưới 7 cột (SnapSpend MemoryCalendarView style)
                            monthCalendarCard
                                .padding(.horizontal, 16)

                            // Danh sách các buổi học của ngày đang chọn bên dưới lịch tháng
                            selectedDaySessionsBelowCalendarSection
                                .padding(.horizontal, 16)
                        } else if timeMode == .month && displayLayout == .list {
                            // Danh sách toàn bộ buổi dạy trong tháng
                            monthListSessionsSection
                                .padding(.horizontal, 16)
                        } else {
                            // Chế độ Ngày (Danh sách buổi dạy trong ngày đang chọn)
                            dayModeSessionsSection
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 100)
                }
                #if canImport(UIKit)
                .refreshable {
                    await viewModel.loadData()
                }
                #endif
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Lịch dạy", "Schedule"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L("Lên lịch", "Schedule"))
                        }
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                SessionEditView(
                    classes: viewModel.classes,
                    existingSessions: viewModel.sessions,
                    defaultDate: viewModel.selectedDate,
                    classRepository: classRepository,
                    studentRepository: studentRepository,
                    onSaveBatch: { sessions, participantIds in
                        Task {
                            if sessions.count == 1, let first = sessions.first {
                                try? await viewModel.saveSession(first, participantStudentIds: participantIds)
                            } else {
                                try? await viewModel.saveRecurringSessions(sessions, participantStudentIds: participantIds)
                            }
                        }
                    },
                    onSave: { newSession, participantIds in
                        Task {
                            try? await viewModel.saveSession(newSession, participantStudentIds: participantIds)
                        }
                    }
                )
            }
            .navigationDestination(item: $deepLinkedSession) { session in
                SessionDetailView(
                    viewModel: SessionDetailViewModel(
                        session: session,
                        scheduleRepository: scheduleRepository,
                        classRepository: classRepository,
                        studentRepository: studentRepository,
                        financeRepository: financeRepository
                    ),
                    scheduleRepository: scheduleRepository,
                    classRepository: classRepository,
                    studentRepository: studentRepository,
                    financeRepository: financeRepository,
                    gradeRepository: gradeRepository,
                    assignmentRepository: assignmentRepository
                )
            }
            .onChange(of: navigationState.targetSessionId) { _, newSessionId in
                if newSessionId != nil {
                    Task {
                        await resolveDeepLinkedSessionIfNeeded()
                    }
                }
            }
            .onChange(of: navigationState.shouldOpenAddSessionSheet) { _, shouldOpen in
                if shouldOpen {
                    navigationState.shouldOpenAddSessionSheet = false
                    isShowingAddSheet = true
                }
            }
            .task {
                await viewModel.loadData()
                await resolveDeepLinkedSessionIfNeeded()
            }
            .onAppear {
                Task {
                    await viewModel.loadData()
                    await resolveDeepLinkedSessionIfNeeded()
                }
            }
        }
    }

    private func resolveDeepLinkedSessionIfNeeded() async {
        if navigationState.shouldOpenAddSessionSheet {
            navigationState.shouldOpenAddSessionSheet = false
            isShowingAddSheet = true
        }
        guard let targetId = navigationState.targetSessionId else { return }
        if let matched = viewModel.sessions.first(where: { $0.id == targetId }) {
            viewModel.selectedDate = matched.startTime
            deepLinkedSession = matched
            navigationState.targetSessionId = nil
        } else if let fetched = try? await scheduleRepository.fetchSession(byId: targetId) {
            viewModel.selectedDate = fetched.startTime
            deepLinkedSession = fetched
            navigationState.targetSessionId = nil
        } else {
            navigationState.targetSessionId = nil
        }
    }

    // MARK: - 1. SnapSpend Toolbar & Horizontal Strip

    private var snapSpendToolbarAndStrip: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Toggle Ngày | Tháng
                HStack(spacing: 0) {
                    ForEach(ScheduleTimeMode.allCases, id: \.self) { mode in
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                timeMode = mode
                            }
                        } label: {
                            Text(mode.localizedTitle)
                                .font(AppTypography.font(size: 14))
                                .foregroundColor(timeMode == mode ? AppColors.primaryText : AppColors.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(timeMode == mode ? AppColors.surfaceCard : Color.clear)
                                        .shadow(color: timeMode == mode ? Color.black.opacity(0.06) : .clear, radius: 3, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(AppColors.surfaceSubtle))

                // Nút "Hôm nay"
                if showTodayButton {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            viewModel.selectedDate = Date()
                        }
                    } label: {
                        Text(L("Hôm nay", "Today"))
                            .font(AppTypography.font(size: 13))
                            .foregroundColor(AppColors.accentRose)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(AppColors.secondaryPink))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // Bộ lọc Lớp học (nút tròn hoặc viên thuốc gọn)
                Menu {
                    Button {
                        selectedClassFilterId = nil
                    } label: {
                        HStack {
                            Text(L("Tất cả các lớp", "All Classes"))
                            if selectedClassFilterId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(viewModel.classes.filter { !$0.isArchived }) { cls in
                        Button {
                            selectedClassFilterId = cls.id
                        } label: {
                            HStack {
                                Text(cls.name)
                                if selectedClassFilterId == cls.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text(
                            selectedClassFilterId.flatMap { id in
                                viewModel.classes.first(where: { $0.id == id })?.name
                            } ?? L("Lọc lớp", "Filter")
                        )
                        .font(AppTypography.caption1)
                        .lineLimit(1)
                    }
                    .foregroundColor(selectedClassFilterId == nil ? AppColors.primaryText : AppColors.accentRose)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(selectedClassFilterId == nil ? AppColors.surfaceCard : AppColors.secondaryPink)
                    )
                }

                // Nút đổi kiểu hiển thị Lịch / Danh sách có nhãn rõ ràng khi ở chế độ Tháng
                if timeMode == .month {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            displayLayout = (displayLayout == .calendar) ? .list : .calendar
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: displayLayout == .calendar ? "list.bullet" : "calendar")
                                .font(.system(size: 13, weight: .semibold))
                            Text(displayLayout == .calendar ? L("Danh sách", "List") : L("Lưới lịch", "Calendar"))
                                .font(AppTypography.caption1)
                        }
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppColors.surfaceCard))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // Thanh cuộn ngang chọn Tháng hoặc chọn Ngày
            if timeMode == .month {
                monthHorizontalStrip
            } else {
                dayHorizontalStrip
            }
        }
    }

    private var monthHorizontalStrip: some View {
        let months = generateMonthsAroundSelected()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(months, id: \.self) { monthDate in
                        let isSelected = calendar.isDate(monthDate, equalTo: viewModel.selectedDate, toGranularity: .month)
                        let isCurrentMonth = calendar.isDate(monthDate, equalTo: Date(), toGranularity: .month)
                        let monthId = monthIdentifier(for: monthDate)

                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                if isCurrentMonth {
                                    viewModel.selectedDate = Date()
                                } else {
                                    viewModel.selectedDate = monthDate
                                }
                            }
                            Task {
                                await viewModel.loadData()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(shortMonthLabel(for: monthDate))
                                    .font(AppTypography.font(size: 14))
                                if isCurrentMonth && !isSelected {
                                    Circle()
                                        .fill(AppColors.accentRose)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .foregroundColor(isSelected ? .white : (isCurrentMonth ? AppColors.primaryText : AppColors.secondaryText))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AppColors.primaryPink : AppColors.surfaceCard)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(monthId)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                let targetId = monthIdentifier(for: viewModel.selectedDate)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.selectedDate) { _, newValue in
                let targetId = monthIdentifier(for: newValue)
                withAnimation {
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
    }

    private var dayHorizontalStrip: some View {
        let days = generateDaysInCurrentMonth()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { date in
                        let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let daySessions = filteredSessions.filter { calendar.isDate($0.startTime, inSameDayAs: date) }
                        let dayId = dayIdentifier(for: date)

                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                viewModel.selectedDate = date
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(shortWeekdayString(for: date))
                                    .font(AppTypography.font(size: 11))
                                    .foregroundColor(isSelected ? .white.opacity(0.9) : AppColors.secondaryText)

                                Text(dayNumberString(for: date))
                                    .font(AppTypography.font(size: 16))
                                    .foregroundColor(isSelected ? .white : (isToday ? AppColors.accentRose : AppColors.primaryText))

                                Circle()
                                    .fill(
                                        !daySessions.isEmpty
                                            ? (isSelected ? Color.white : AppColors.accentRose)
                                            : (isToday && !isSelected ? AppColors.accentRose.opacity(0.5) : Color.clear)
                                    )
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 48, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isSelected ? AppColors.primaryPink : AppColors.surfaceCard)
                                    .shadow(color: isSelected ? AppColors.primaryPink.opacity(0.28) : Color.black.opacity(0.03), radius: 5, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(dayId)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                let targetId = dayIdentifier(for: viewModel.selectedDate)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.selectedDate) { _, newValue in
                let targetId = dayIdentifier(for: newValue)
                withAnimation {
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
    }

    // MARK: - 2. SnapSpend Summary Cards Row

    private var summaryCardsRow: some View {
        HStack(spacing: 12) {
            // Card 1: Buổi sắp tới
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.info.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.info)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeMode == .month ? L("Sắp dạy (Tháng)", "Upcoming (Month)") : L("Sắp dạy (Ngày)", "Upcoming (Day)"))
                        .font(AppTypography.font(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(L("\(scheduledCount) buổi", "\(scheduledCount) sessions"))
                        .font(AppTypography.font(size: 17))
                        .foregroundColor(AppColors.primaryText)
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

            // Card 2: Đã hoàn thành
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.success.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeMode == .month ? L("Hoàn thành (Tháng)", "Completed (Month)") : L("Hoàn thành (Ngày)", "Completed (Day)"))
                        .font(AppTypography.font(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(L("\(completedCount) buổi", "\(completedCount) sessions"))
                        .font(AppTypography.font(size: 17))
                        .foregroundColor(AppColors.success)
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
    }

    // MARK: - 3. SnapSpend MemoryCalendarView-style Month Grid Card

    private var monthCalendarCard: some View {
        let gridCells = buildMonthGridCells(for: viewModel.selectedDate)

        return VStack(spacing: 14) {
            // Header tháng & nút chuyển tháng nhanh
            HStack {
                Text(fullMonthYearTitle(for: viewModel.selectedDate))
                    .font(AppTypography.font(size: 16))
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColors.surfaceSubtle))
                    }
                    .buttonStyle(.plain)

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColors.surfaceSubtle))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            // Tiêu đề các thứ T2..CN
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { day in
                    Text(day)
                        .font(AppTypography.font(size: 12))
                        .foregroundColor(day == "CN" ? AppColors.accentRose : AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            // Lưới 7 cột
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 10
            ) {
                ForEach(Array(gridCells.enumerated()), id: \.offset) { _, cellDate in
                    if let date = cellDate {
                        calendarDayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 58)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppColors.surfaceCard)
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 4)
        )
    }

    private func calendarDayCell(for date: Date) -> some View {
        let daySessions = filteredSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
        let dayNumber = calendar.component(.day, from: date)

        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            if isSelected && daySessions.isEmpty {
                isShowingAddSheet = true
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                    viewModel.selectedDate = date
                }
            }
        } label: {
            ZStack {
                if let firstSession = daySessions.first {
                    let cls = viewModel.classGroup(for: firstSession.classId)
                    let baseColor = Color(hex: cls?.colorHex ?? "#D85B7F")
                    let allCompleted = daySessions.allSatisfy { $0.status == .completed }

                    // Ô ngày có buổi dạy (SnapSpend Memory Tile style)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    allCompleted ? AppColors.success.opacity(0.88) : baseColor.opacity(0.90),
                                    allCompleted ? AppColors.success : baseColor
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(0.76, contentMode: .fit)
                        .overlay(
                            VStack(spacing: 2) {
                                Spacer()
                                Image(systemName: allCompleted ? "checkmark.seal.fill" : "book.closed.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.95))
                                Text(L("\(daySessions.count) buổi", "\(daySessions.count) cls"))
                                    .font(AppTypography.font(size: 9))
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? AppColors.primaryText : (isToday ? Color.white : Color.clear), lineWidth: isSelected ? 2.2 : 1.5)
                        )
                        .shadow(color: baseColor.opacity(0.28), radius: 4, x: 0, y: 2)

                    // Số ngày ở góc trên trái
                    VStack {
                        HStack {
                            Text("\(dayNumber)")
                                .font(AppTypography.font(size: 10))
                                .foregroundColor(.white)
                                .frame(width: 19, height: 19)
                                .background(
                                    Circle()
                                        .fill(isToday ? AppColors.primaryPink : Color.black.opacity(0.28))
                                )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(3)
                } else {
                    // Ô ngày trống
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AppColors.secondaryPink.opacity(0.75) : (isToday ? AppColors.secondaryPink.opacity(0.35) : AppColors.surfaceSubtle))
                        .aspectRatio(0.76, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? AppColors.primaryPink : (isToday ? AppColors.accentRose.opacity(0.5) : Color.clear), lineWidth: 1.5)
                        )

                    if isSelected || isToday {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.accentRose.opacity(0.75))
                            .offset(y: 6)
                    }

                    VStack {
                        HStack {
                            Text("\(dayNumber)")
                                .font(.system(size: 11, weight: (isToday || isSelected) ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isToday ? .white : (isSelected ? AppColors.accentRose : AppColors.primaryText))
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(isToday ? AppColors.primaryPink : Color.clear)
                                )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(3)
                }
            }
            .frame(height: 58)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Session Lists (Below Calendar / Month List / Day Mode)

    private var selectedDaySessionsBelowCalendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(
                    "Lịch ngày \(viewModel.selectedDate.formatted(date: .numeric, time: .omitted))",
                    "Schedule for \(viewModel.selectedDate.formatted(date: .numeric, time: .omitted))"
                ))
                .font(AppTypography.font(size: 16))
                .foregroundColor(AppColors.primaryText)

                Spacer()

                Button {
                    isShowingAddSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(L("Thêm buổi", "Add Session"))
                    }
                    .font(AppTypography.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.accentRose)
                }
                .buttonStyle(.plain)
            }

            if sessionsInSelectedDay.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.accentRose)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Trống lịch trong ngày này", "No sessions on this day"))
                            .font(AppTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.primaryText)
                        Text(L("Bấm 'Thêm buổi' hoặc chạm vào ô ngày để lên lịch dạy.", "Tap 'Add Session' or tap the date cell to schedule."))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.surfaceCard)
                )
            } else {
                ForEach(sessionsInSelectedDay) { session in
                    sessionNavigationCard(session)
                }
            }
        }
    }

    private var monthListSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Danh sách buổi dạy (\(sessionsInSelectedMonth.count))", "Teaching Sessions (\(sessionsInSelectedMonth.count))"))
                    .font(AppTypography.font(size: 16))
                    .foregroundColor(AppColors.primaryText)
                Spacer()
            }

            if sessionsInSelectedMonth.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: L("Chưa có buổi dạy trong tháng", "No Sessions This Month"),
                    message: L("Bấm nút '+' để lên lịch buổi dạy mới hoặc tạo lịch lặp theo tháng.", "Tap '+' to schedule a new session or monthly recurring sessions."),
                    actionTitle: L("Lên lịch buổi dạy", "Schedule Session")
                ) {
                    isShowingAddSheet = true
                }
                .padding(.vertical, 20)
            } else {
                ForEach(sessionsInSelectedMonth) { session in
                    sessionNavigationCard(session, showFullDate: true)
                }
            }
        }
    }

    private var dayModeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sessionsInSelectedDay.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: L("Không có buổi dạy", "No Teaching Sessions"),
                    message: L(
                        "Chưa có buổi dạy nào trong ngày \(viewModel.selectedDate.formatted(date: .numeric, time: .omitted)).",
                        "No teaching sessions scheduled on \(viewModel.selectedDate.formatted(date: .numeric, time: .omitted))."
                    ),
                    actionTitle: L("Lên lịch buổi dạy", "Schedule Session")
                ) {
                    isShowingAddSheet = true
                }
                .padding(.vertical, 24)
            } else {
                ForEach(sessionsInSelectedDay) { session in
                    sessionNavigationCard(session)
                }
            }
        }
    }

    // MARK: - 5. SnapSpend-style Session Card (`dayExpenseCard` equivalent)

    private func sessionNavigationCard(_ session: TeachingSessionEntity, showFullDate: Bool = false) -> some View {
        let classGroup = viewModel.classGroup(for: session.classId)
        let colorHex = classGroup?.colorHex ?? "#D85B7F"
        let classColor = Color(hex: colorHex)

        return NavigationLink {
            SessionDetailView(
                viewModel: SessionDetailViewModel(
                    session: session,
                    scheduleRepository: scheduleRepository,
                    classRepository: classRepository,
                    studentRepository: studentRepository,
                    financeRepository: financeRepository
                ),
                scheduleRepository: scheduleRepository,
                classRepository: classRepository,
                studentRepository: studentRepository,
                financeRepository: financeRepository,
                gradeRepository: gradeRepository,
                assignmentRepository: assignmentRepository
            )
        } label: {
            HStack(spacing: 14) {
                // Icon lớp học kiểu SnapSpend (52x52 rounded tile + badge góc dưới)
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(classColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: session.status == .completed ? "checkmark.seal.fill" : "book.closed.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(classColor)
                        )

                    Circle()
                        .fill(statusColor(for: session.status))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: statusIconName(for: session.status))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 3, y: 3)
                }

                // Nội dung buổi học
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let c = classGroup {
                            Text(c.name)
                                .font(AppTypography.font(size: 11))
                                .foregroundColor(classColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(classColor.opacity(0.14)))
                        }
                        if showFullDate {
                            Text(session.startTime.formatted(date: .numeric, time: .omitted))
                                .font(AppTypography.font(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }

                    Text(session.title)
                        .font(AppTypography.font(size: 16))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
                        Text("•")
                        Text("\(session.durationMinutes)p")
                    }
                    .font(AppTypography.font(size: 12))
                    .foregroundColor(AppColors.secondaryText)
                }

                Spacer(minLength: 4)

                // Trạng thái bên phải
                VStack(alignment: .trailing, spacing: 6) {
                    statusPill(for: session.status)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.tertiaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.surfaceCard)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if session.status == .scheduled {
                Button(role: .destructive) {
                    Task {
                        await viewModel.cancelSession(id: session.id)
                    }
                } label: {
                    Label("Hủy buổi dạy", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func statusPill(for status: SessionStatus) -> some View {
        Text(LocalizationManager.translate(status.displayName))
            .font(AppTypography.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusColor(for: status).opacity(0.14)))
            .foregroundColor(statusColor(for: status))
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .scheduled: return AppColors.info
        case .completed: return AppColors.success
        case .cancelled: return AppColors.error
        }
    }

    private func statusIconName(for status: SessionStatus) -> String {
        switch status {
        case .scheduled: return "clock.fill"
        case .completed: return "checkmark"
        case .cancelled: return "xmark"
        }
    }

    // MARK: - Calendar & Date Helpers

    private func buildMonthGridCells(for date: Date) -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Chuyển đổi sang chuẩn Thứ 2 = 0 ... Chủ nhật = 6
        let leadingEmptyDays = (firstWeekday + 5) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(d)
            }
        }
        return days
    }

    private func shiftMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: viewModel.selectedDate) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                viewModel.selectedDate = newDate
            }
            Task {
                await viewModel.loadData()
            }
        }
    }

    private func generateMonthsAroundSelected() -> [Date] {
        let currentYear = calendar.component(.year, from: viewModel.selectedDate)
        var result: [Date] = []
        for year in [currentYear - 1, currentYear, currentYear + 1] {
            for month in 1...12 {
                if let d = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                    result.append(d)
                }
            }
        }
        return result
    }

    private func generateDaysInCurrentMonth() -> [Date] {
        let comp = calendar.dateComponents([.year, .month], from: viewModel.selectedDate)
        guard let startOfMonth = calendar.date(from: comp),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return [viewModel.selectedDate]
        }
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)
        }
    }

    private func monthIdentifier(for date: Date) -> String {
        let comp = calendar.dateComponents([.year, .month], from: date)
        return "\(comp.year ?? 2026)-\(comp.month ?? 1)"
    }

    private func dayIdentifier(for date: Date) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comp.year ?? 2026)-\(comp.month ?? 1)-\(comp.day ?? 1)"
    }

    private func shortMonthLabel(for date: Date) -> String {
        let comp = calendar.dateComponents([.year, .month], from: date)
        let currentYear = calendar.component(.year, from: Date())
        if LocalizationManager.currentLanguageThreadSafe == .english {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = comp.year == currentYear ? "MMM" : "MMM ''yy"
            return formatter.string(from: date)
        }
        if comp.year == currentYear {
            return "Thg \(comp.month ?? 1)"
        } else {
            return "T\(comp.month ?? 1)/\(String((comp.year ?? 2026) % 100))"
        }
    }

    private func fullMonthYearTitle(for date: Date) -> String {
        if LocalizationManager.currentLanguageThreadSafe == .english {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        let comp = calendar.dateComponents([.year, .month], from: date)
        return "Tháng \(comp.month ?? 1), \(comp.year ?? 2026)"
    }

    private func shortWeekdayString(for date: Date) -> String {
        let wd = calendar.component(.weekday, from: date)
        if LocalizationManager.currentLanguageThreadSafe == .english {
            switch wd {
            case 1: return "Sun"
            case 2: return "Mon"
            case 3: return "Tue"
            case 4: return "Wed"
            case 5: return "Thu"
            case 6: return "Fri"
            case 7: return "Sat"
            default: return ""
            }
        }
        switch wd {
        case 1: return "CN"
        case 2: return "T2"
        case 3: return "T3"
        case 4: return "T4"
        case 5: return "T5"
        case 6: return "T6"
        case 7: return "T7"
        default: return ""
        }
    }

    private func dayNumberString(for date: Date) -> String {
        let day = calendar.component(.day, from: date)
        return String(format: "%02d", day)
    }
}
