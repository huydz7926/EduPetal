import Foundation

/// DTO chứa toàn bộ các chỉ số tổng hợp cho Màn hình Home Dashboard
public struct DashboardMetrics: Sendable, Equatable {
    public let activeStudentsCount: Int
    public let activeClassesCount: Int
    public let todaySessions: [TeachingSessionEntity]
    public let upcomingSessions: [TeachingSessionEntity]
    public let todayCompletedSessionsCount: Int
    public let todayTotalSessionsCount: Int
    public let financeSummary: FinanceSummaryEntity
    public let pendingGradingAssignmentsCount: Int
    public let pendingCompletionSessionsCount: Int
    public let studentsWithOutstandingTuitionCount: Int

    /// Danh sách buổi dạy ưu tiên hiển thị trên Trang chủ:
    /// Hiển thị các buổi hôm nay nếu có; nếu hôm nay trống thì hiển thị các buổi sắp tới gần nhất.
    public var displaySessions: [TeachingSessionEntity] {
        todaySessions.isEmpty ? upcomingSessions : todaySessions
    }

    /// Cho biết Trang chủ đang hiển thị danh sách buổi sắp tới (do hôm nay không có ca dạy)
    public var isShowingUpcomingSessions: Bool {
        todaySessions.isEmpty && !upcomingSessions.isEmpty
    }

    public init(
        activeStudentsCount: Int = 0,
        activeClassesCount: Int = 0,
        todaySessions: [TeachingSessionEntity] = [],
        upcomingSessions: [TeachingSessionEntity] = [],
        todayCompletedSessionsCount: Int = 0,
        todayTotalSessionsCount: Int = 0,
        financeSummary: FinanceSummaryEntity = .zero,
        pendingGradingAssignmentsCount: Int = 0,
        pendingCompletionSessionsCount: Int = 0,
        studentsWithOutstandingTuitionCount: Int = 0
    ) {
        self.activeStudentsCount = activeStudentsCount
        self.activeClassesCount = activeClassesCount
        self.todaySessions = todaySessions
        self.upcomingSessions = upcomingSessions
        self.todayCompletedSessionsCount = todayCompletedSessionsCount
        self.todayTotalSessionsCount = todayTotalSessionsCount
        self.financeSummary = financeSummary
        self.pendingGradingAssignmentsCount = pendingGradingAssignmentsCount
        self.pendingCompletionSessionsCount = pendingCompletionSessionsCount
        self.studentsWithOutstandingTuitionCount = studentsWithOutstandingTuitionCount
    }

    public static let empty = DashboardMetrics()
}

/// Use case tổng hợp các chỉ số hoạt động và công việc cần xử lý cho Home Dashboard
public struct CalculateDashboardMetricsUseCase: Sendable {
    private let financeSummaryUseCase = CalculateFinanceSummaryUseCase()

    public init() {}

    public func execute(
        students: [StudentEntity],
        classes: [ClassGroupEntity],
        sessions: [TeachingSessionEntity],
        records: [AssignmentRecordEntity],
        charges: [ChargeEntity],
        payments: [PaymentEntity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardMetrics {
        // 1. Học sinh và Lớp học đang hoạt động (loại trừ đã lưu trữ và khử trùng theo ID để không đếm 1 học sinh nhiều lần)
        let activeStudentIds = Set(students.lazy.filter { !$0.isArchived }.map { $0.id })
        let activeClassIds = Set(classes.lazy.filter { !$0.isArchived }.map { $0.id })

        // 2. Các ca dạy hôm nay (cùng ngày/tháng/năm với `now`) và các ca dạy sắp tới
        let todaySessions = sessions.filter {
            calendar.isDate($0.startTime, inSameDayAs: now)
        }.sorted { $0.startTime < $1.startTime }

        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let upcomingSessions = Array(
            sessions.filter {
                $0.startTime >= tomorrowStart && $0.status != .cancelled
            }
            .sorted { $0.startTime < $1.startTime }
            .prefix(5)
        )

        let todayCompleted = todaySessions.filter { $0.status == .completed }.count
        let todayTotal = todaySessions.count

        // 3. Tổng kết tài chính dùng chung nguồn nghiệp vụ với tab Học phí (CalculateFinanceSummaryUseCase)
        let financeSummary = financeSummaryUseCase.execute(charges: charges, payments: payments)

        // 4. Số bài tập học sinh đã nộp cần chấm (.submitted)
        let pendingGrading = records.filter { $0.status == .submitted }.count

        // 5. Số buổi dạy đã qua giờ kết thúc nhưng chưa hoàn thành (vẫn đang .scheduled)
        let pendingCompletion = sessions.filter {
            $0.status == .scheduled && $0.endTime < now
        }.count

        // 6. Số lượng học sinh còn dư nợ học phí chưa nộp (chỉ nhóm một lần theo studentId để tối ưu O(N))
        let chargesByStudent = Dictionary(grouping: charges, by: { $0.studentId })
        let paymentsByStudent = Dictionary(grouping: payments, by: { $0.studentId })
        var studentsWithDebtCount = 0
        for studentId in activeStudentIds {
            let sSummary = financeSummaryUseCase.execute(
                charges: chargesByStudent[studentId] ?? [],
                payments: paymentsByStudent[studentId] ?? []
            )
            if sSummary.outstandingBalance > 0 {
                studentsWithDebtCount += 1
            }
        }

        return DashboardMetrics(
            activeStudentsCount: activeStudentIds.count,
            activeClassesCount: activeClassIds.count,
            todaySessions: todaySessions,
            upcomingSessions: upcomingSessions,
            todayCompletedSessionsCount: todayCompleted,
            todayTotalSessionsCount: todayTotal,
            financeSummary: financeSummary,
            pendingGradingAssignmentsCount: pendingGrading,
            pendingCompletionSessionsCount: pendingCompletion,
            studentsWithOutstandingTuitionCount: studentsWithDebtCount
        )
    }

    /// Trả về lời chào phù hợp thời gian thực theo chuẩn tiếng Việt
    public func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Chào buổi sáng ☀️"
        case 12..<18:
            return "Chào buổi chiều 🌤️"
        default:
            return "Chào buổi tối 🌙"
        }
    }
}

