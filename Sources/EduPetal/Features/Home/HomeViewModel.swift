import Foundation
import Observation

/// Các bước khởi đầu nhanh cho người dùng lần đầu (Mục 6: 1. Tạo lớp -> 2. Thêm học sinh -> 3. Lên lịch buổi đầu)
public enum FirstTimeSetupStep: Int, Sendable, Equatable {
    case createClass = 1
    case addStudent = 2
    case scheduleFirstSession = 3
    case completed = 4
}

/// ViewModel điều phối Màn hình Home Dashboard (Presentation Layer)
@Observable
@MainActor
public final class HomeViewModel {
    public var metrics: DashboardMetrics = .empty
    public var students: [StudentEntity] = []
    public var classes: [ClassGroupEntity] = []
    public var sessions: [TeachingSessionEntity] = []
    public var records: [AssignmentRecordEntity] = []
    public var charges: [ChargeEntity] = []
    public var payments: [PaymentEntity] = []
    public var studentCountsByClassId: [UUID: Int] = [:]
    public var enrolledClassesByStudentId: [UUID: [ClassGroupEntity]] = [:]

    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isShowingSettings: Bool = false
    public var isFirstTimeGuideDismissed: Bool = false

    // Quick Action Sheets Trigger
    public var isShowingAddStudent: Bool = false
    public var isShowingCreateClass: Bool = false
    public var isShowingClassList: Bool = false
    public var isShowingScheduleSession: Bool = false
    public var isShowingCreateAssignment: Bool = false
    public var isShowingRecordPayment: Bool = false

    public let studentRepository: StudentRepositoryProtocol
    public let classRepository: ClassRepositoryProtocol
    public let scheduleRepository: ScheduleRepositoryProtocol
    public let assignmentRepository: AssignmentRepositoryProtocol?
    public let financeRepository: FinanceRepositoryProtocol?
    public let gradeRepository: GradeRepositoryProtocol?
    public let notificationService: NotificationServiceProtocol
    private let explicitOwnerId: String?
    private let metricsUseCase = CalculateDashboardMetricsUseCase()

    public var activeOwnerId: String {
        explicitOwnerId ?? UserSessionManager.shared.currentOwnerId
    }

    private var guideDismissedDefaultsKey: String {
        "edupetal.first_time_guide.dismissed.\(activeOwnerId)"
    }

    public init(
        studentRepository: StudentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol,
        assignmentRepository: AssignmentRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        notificationService: NotificationServiceProtocol = LocalNotificationService.shared,
        explicitOwnerId: String? = nil
    ) {
        self.studentRepository = studentRepository
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.assignmentRepository = assignmentRepository
        self.financeRepository = financeRepository
        self.gradeRepository = gradeRepository
        self.notificationService = notificationService
        self.explicitOwnerId = explicitOwnerId
        let owner = explicitOwnerId ?? UserSessionManager.shared.currentOwnerId
        self.isFirstTimeGuideDismissed = UserDefaults.standard.bool(
            forKey: "edupetal.first_time_guide.dismissed.\(owner)"
        )
    }

    // MARK: - Trải nghiệm người dùng lần đầu (3 bước: Tạo lớp -> Thêm học sinh -> Lên lịch buổi đầu)

    public var hasCreatedFirstClass: Bool {
        !classes.isEmpty
    }

    public var hasAddedFirstStudent: Bool {
        !students.isEmpty
    }

    public var hasScheduledFirstSession: Bool {
        !sessions.isEmpty
    }

    public var completedFirstTimeStepsCount: Int {
        var count = 0
        if hasCreatedFirstClass { count += 1 }
        if hasAddedFirstStudent { count += 1 }
        if hasScheduledFirstSession { count += 1 }
        return count
    }

    public var currentFirstTimeStep: FirstTimeSetupStep {
        if !hasCreatedFirstClass {
            return .createClass
        }
        if !hasAddedFirstStudent {
            return .addStudent
        }
        if !hasScheduledFirstSession {
            return .scheduleFirstSession
        }
        return .completed
    }

    public var shouldShowFirstTimeGuide: Bool {
        !isFirstTimeGuideDismissed && currentFirstTimeStep != .completed
    }

    public func dismissFirstTimeGuide() {
        isFirstTimeGuideDismissed = true
        UserDefaults.standard.set(true, forKey: guideDismissedDefaultsKey)
    }

    public func restoreFirstTimeGuide() {
        isFirstTimeGuideDismissed = false
        UserDefaults.standard.set(false, forKey: guideDismissedDefaultsKey)
    }

    @discardableResult
    public func createClassFromGuide(_ newClass: ClassGroupEntity) async -> Bool {
        let trimmed = newClass.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, newClass.defaultPricePerSession > 0 else { return false }
        do {
            try await classRepository.saveClass(newClass)
            await loadDashboard()
            return true
        } catch {
            self.errorMessage = "Không thể tạo lớp học: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    public func createAndEnrollStudentFromGuide(_ newStudent: StudentEntity, classId: UUID? = nil) async -> Bool {
        let trimmed = newStudent.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await studentRepository.saveStudent(newStudent)
            if let targetClassId = classId ?? classes.first?.id {
                let already = try await classRepository.isStudentEnrolled(studentId: newStudent.id, classId: targetClassId)
                if !already {
                    try await classRepository.enrollStudent(studentId: newStudent.id, classId: targetClassId)
                }
            }
            await loadDashboard()
            return true
        } catch {
            self.errorMessage = "Không thể thêm học sinh: \(error.localizedDescription)"
            return false
        }
    }

    /// Tải toàn bộ dữ liệu từ các Repository và tổng hợp Metrics
    public func loadDashboard() async {
        isLoading = true
        errorMessage = nil

        do {
            self.isFirstTimeGuideDismissed = UserDefaults.standard.bool(forKey: guideDismissedDefaultsKey)
            self.students = try await studentRepository.fetchStudents(includeArchived: false)
            self.classes = try await classRepository.fetchClasses(includeArchived: false)

            let classesById = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
            let activeStudentIds = Set(students.map { $0.id })
            var countMap: [UUID: Int] = [:]
            var studentClassMap: [UUID: [ClassGroupEntity]] = [:]

            for cls in classes {
                let enrollments = (try? await classRepository.fetchEnrollments(forClassId: cls.id, activeOnly: true)) ?? []
                let validStudentIds = Set(enrollments.map { $0.studentId }.filter { activeStudentIds.contains($0) })
                countMap[cls.id] = validStudentIds.count
                for sid in validStudentIds {
                    if let c = classesById[cls.id] {
                        studentClassMap[sid, default: []].append(c)
                    }
                }
            }
            self.studentCountsByClassId = countMap
            self.enrolledClassesByStudentId = studentClassMap

            let calendar = Calendar.current
            let now = Date()
            let startWindow = calendar.startOfDay(for: now)
            let endWindow = calendar.date(byAdding: .day, value: 30, to: startWindow) ?? now
            self.sessions = try await scheduleRepository.fetchSessions(from: startWindow, to: endWindow)

            // Không truy vấn danh sách AssignmentRecord trên màn hình Tổng quan (đã xóa khối "Bài cần chấm" theo Mục 6 /duan)
            self.records = []

            if let finRepo = financeRepository {
                self.charges = try await finRepo.fetchCharges()
                self.payments = try await finRepo.fetchPayments()
            }

            self.metrics = metricsUseCase.execute(
                students: students,
                classes: classes,
                sessions: sessions,
                records: records,
                charges: charges,
                payments: payments,
                now: Date()
            )
            // Đồng bộ lời nhắc hằng ngày và các buổi dạy 30 ngày tới cho tài khoản hiện tại (không tự xin quyền lúc mở app)
            await notificationService.syncDailyReminder()
            await notificationService.syncSessionReminders(for: sessions)
            isLoading = false
        } catch {
            self.errorMessage = "Không thể tải dữ liệu Dashboard: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Tạo mới một buổi dạy từ Quick Action, snapshot điểm danh cho học sinh và làm mới Dashboard
    public func createSession(_ session: TeachingSessionEntity, participantStudentIds: [UUID] = []) async throws {
        try await scheduleRepository.saveSession(session)
        if !participantStudentIds.isEmpty {
            let attendances = participantStudentIds.map { studentId in
                AttendanceEntity(
                    sessionId: session.id,
                    studentId: studentId,
                    status: .pending,
                    note: ""
                )
            }
            try await scheduleRepository.saveAttendances(attendances)
        }
        if session.status == .scheduled {
            await notificationService.scheduleSessionReminder(for: session)
        } else {
            await notificationService.cancelSessionReminder(sessionId: session.id)
        }
        await loadDashboard()
    }

    /// Lời chào cá nhân hóa theo buổi trong ngày
    public var greeting: String {
        LocalizationManager.translate(metricsUseCase.greeting(for: Date()))
    }

    /// Ngày hiện tại được định dạng chuẩn theo ngôn ngữ
    public var formattedDate: String {
        let formatter = DateFormatter()
        if LocalizationManager.currentLanguageThreadSafe == .english {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        } else {
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "EEEE, d 'tháng' M, yyyy"
        }
        let str = formatter.string(from: Date())
        return str.prefix(1).capitalized + str.dropFirst()
    }

    /// Tìm tên lớp học theo ID
    public func className(for classId: UUID) -> String {
        classes.first(where: { $0.id == classId })?.name ?? L("Lớp học", "Class")
    }

    /// Tìm màu hex của lớp học theo ID
    public func classColorHex(for classId: UUID) -> String {
        classes.first(where: { $0.id == classId })?.colorHex ?? "#E88FA8"
    }

    /// Số học sinh đang hoạt động trong một lớp
    public func activeStudentCount(for classId: UUID) -> Int {
        studentCountsByClassId[classId] ?? 0
    }

    /// Danh sách các lớp đang hoạt động mà một học sinh đang tham gia
    public func enrolledClassNames(for studentId: UUID) -> String {
        let list = enrolledClassesByStudentId[studentId] ?? []
        return list.map { $0.name }.joined(separator: " • ")
    }

    /// Dư nợ học phí hiện tại của một học sinh (cùng nguồn với tab Học phí)
    public func outstandingBalance(for studentId: UUID) -> Int64 {
        let sCharges = charges.filter { $0.studentId == studentId }
        let sPayments = payments.filter { $0.studentId == studentId }
        let accrued = sCharges.reduce(0 as Int64) { $0 + $1.amount }
        let collected = sPayments.reduce(0 as Int64) { $0 + $1.amount }
        return max(0, accrued - collected)
    }

    /// Buổi dạy sắp tới gần nhất của một lớp học
    public func nextSession(for classId: UUID, now: Date = Date()) -> TeachingSessionEntity? {
        sessions
            .filter { $0.classId == classId && $0.status == .scheduled && $0.endTime >= now }
            .sorted { $0.startTime < $1.startTime }
            .first
    }
}
