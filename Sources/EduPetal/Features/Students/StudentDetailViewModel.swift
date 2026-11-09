import Foundation
import Observation

/// Các mục trong màn hình Chi tiết Học sinh (Giáo viên quản lý 1 học sinh)
/// Bao gồm 4 mục chính: Tổng quan, Điểm số, Học phí, Lớp học
public enum StudentDetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Tổng quan"
    case grades = "Điểm số"
    case tuition = "Học phí"
    case classes = "Lớp học"
    // Giữ các case tương thích ngược nếu được gọi từ module khác
    case assignments = "Bài tập"
    case attendance = "Điểm danh"
    case notes = "Ghi chú"

    /// 4 mục chính hiển thị trên thanh điều hướng Chi tiết Học sinh theo đặc tả
    public static var primaryTabs: [StudentDetailTab] {
        [.overview, .grades, .tuition, .classes]
    }

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "person.text.rectangle"
        case .grades: return "chart.bar.xaxis"
        case .tuition: return "dollarsign.circle"
        case .classes: return "graduationcap.fill"
        case .assignments: return "doc.text"
        case .attendance: return "calendar.badge.clock"
        case .notes: return "note.text"
        }
    }
}

public struct StudentAttendanceRecord: Identifiable, Sendable {
    public let id: UUID
    public let sessionDate: Date
    public let sessionTitle: String
    public let status: AttendanceStatus
    public let notes: String

    public init(id: UUID = UUID(), sessionDate: Date, sessionTitle: String, status: AttendanceStatus, notes: String = "") {
        self.id = id
        self.sessionDate = sessionDate
        self.sessionTitle = sessionTitle
        self.status = status
        self.notes = notes
    }
}

/// Dữ liệu tổng hợp một buổi đã dạy gắn với học sinh trong mục Học phí
public struct StudentSessionTuitionItem: Identifiable, Sendable {
    public let id: UUID
    public let session: TeachingSessionEntity
    public let classGroup: ClassGroupEntity?
    public let attendance: AttendanceEntity
    public let charge: ChargeEntity?
    public let attachments: [SessionAttachmentEntity]
    public let effectiveUnitPrice: Int64

    public init(
        id: UUID,
        session: TeachingSessionEntity,
        classGroup: ClassGroupEntity?,
        attendance: AttendanceEntity,
        charge: ChargeEntity?,
        attachments: [SessionAttachmentEntity],
        effectiveUnitPrice: Int64
    ) {
        self.id = id
        self.session = session
        self.classGroup = classGroup
        self.attendance = attendance
        self.charge = charge
        self.attachments = attachments
        self.effectiveUnitPrice = effectiveUnitPrice
    }

    public var unitPriceDisplayed: Int64 {
        if let charge {
            return charge.unitPriceSnapshot
        }
        return attendance.status == .present ? effectiveUnitPrice : 0
    }

    public var accruedAmount: Int64 {
        if let charge {
            return charge.amount
        }
        return 0
    }
}

/// Dữ liệu hiển thị một bản ghi tham gia lớp học (Đang tham gia / Lịch sử)
public struct StudentClassEnrollmentItem: Identifiable, Sendable {
    public let id: UUID
    public let enrollment: EnrollmentEntity
    public let classGroup: ClassGroupEntity
    public let effectivePrice: Int64
    public let isCustomPrice: Bool

    public init(
        enrollment: EnrollmentEntity,
        classGroup: ClassGroupEntity,
        effectivePrice: Int64,
        isCustomPrice: Bool
    ) {
        self.id = enrollment.id
        self.enrollment = enrollment
        self.classGroup = classGroup
        self.effectivePrice = effectivePrice
        self.isCustomPrice = isCustomPrice
    }
}

/// ViewModel quản lý Hồ sơ chi tiết Học sinh (Presentation Layer)
/// Dùng chung nguồn dữ liệu nghiệp vụ giữa 4 mục: Tổng quan, Điểm số, Học phí, Lớp học
@Observable
@MainActor
public final class StudentDetailViewModel {
    public var student: StudentEntity
    public var enrolledClasses: [ClassGroupEntity] = []
    public var allClasses: [ClassGroupEntity] = []
    public var enrollmentItems: [StudentClassEnrollmentItem] = []

    public var activeTab: StudentDetailTab = .overview
    public var studentGradeItems: [StudentGradeItem] = []
    public var selectedGradeClassFilterId: UUID? = nil

    public var studentAssignmentPairs: [(record: AssignmentRecordEntity, assignment: AssignmentEntity)] = []
    public var studentCharges: [ChargeEntity] = []
    public var studentPayments: [PaymentEntity] = []
    public var studentAllocations: [PaymentAllocationEntity] = []
    public var studentAttendances: [StudentAttendanceRecord] = []
    public var studentSessionTuitionItems: [StudentSessionTuitionItem] = []

    /// Tháng đang lọc ở mục Học phí (`nil` = Xem toàn bộ các kỳ)
    public var selectedTuitionMonth: Date? = nil

    /// Dữ liệu buổi học tiếp theo & số buổi đã hoàn thành trong tháng hiện tại (Mục Tổng quan)
    public var nextUpcomingSession: (session: TeachingSessionEntity, className: String)? = nil
    public var completedSessionsThisMonthCount: Int = 0

    /// Tổng hợp học phí toàn bộ đến hiện tại (dùng chung cho Tổng quan & Học phí)
    public var studentFinanceSummary: FinanceSummaryEntity = .zero

    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isDismissRequired: Bool = false
    public var isDeleteConfirmationShowing: Bool = false
    public var isDeleteBlockedShowing: Bool = false
    public var debtAmount: Int64 = 0
    public var hasFinancialHistoryBlock: Bool = false

    public let studentRepository: StudentRepositoryProtocol
    public let classRepository: ClassRepositoryProtocol
    public let scheduleRepository: ScheduleRepositoryProtocol?
    public let gradeRepository: GradeRepositoryProtocol?
    public let assignmentRepository: AssignmentRepositoryProtocol?
    public let financeRepository: FinanceRepositoryProtocol?

    private let averageUseCase = CalculateWeightedAverageUseCase()
    private let validateGradeUseCase = ValidateGradeInputUseCase()
    private let effectivePriceUseCase = GetEffectiveStudentPriceUseCase()
    private let recordPaymentUseCase = RecordPaymentUseCase()

    public init(
        student: StudentEntity,
        studentRepository: StudentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        gradeRepository: GradeRepositoryProtocol? = nil,
        assignmentRepository: AssignmentRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil
    ) {
        self.student = student
        self.studentRepository = studentRepository
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.gradeRepository = gradeRepository
        self.assignmentRepository = assignmentRepository
        self.financeRepository = financeRepository
    }

    // MARK: - Computed Properties (Dùng chung dữ liệu nghiệp vụ)

    public var attendanceStats: (present: Int, absent: Int, excused: Int, total: Int, rate: Double) {
        let present = studentAttendances.filter { $0.status == .present }.count
        let absent = studentAttendances.filter { $0.status == .absent }.count
        let excused = studentAttendances.filter { $0.status == .excused }.count
        let total = studentAttendances.count
        let rate = total > 0 ? (Double(present) / Double(total)) * 100.0 : 100.0
        return (present, absent, excused, total, rate)
    }

    /// Điểm số sau khi lọc theo lớp/môn (nếu có chọn bộ lọc)
    public var filteredGradeItems: [StudentGradeItem] {
        guard let classId = selectedGradeClassFilterId else {
            return studentGradeItems
        }
        return studentGradeItems.filter { $0.assessment.classId == classId }
    }

    /// Điểm trung bình trọng số: Trả về `nil` khi chưa có điểm (không coi bằng 0)
    public var weightedAverage: Double? {
        averageUseCase.execute(items: filteredGradeItems)
    }

    /// Danh sách các lớp đang tham gia
    public var activeEnrollmentItems: [StudentClassEnrollmentItem] {
        enrollmentItems.filter { $0.enrollment.isActive && !$0.classGroup.isArchived }
    }

    /// Danh sách lịch sử tham gia lớp đã kết thúc
    public var historicalEnrollmentItems: [StudentClassEnrollmentItem] {
        enrollmentItems.filter { !$0.enrollment.isActive || $0.classGroup.isArchived }
    }

    /// Các lớp đang hoạt động mà học sinh có thể chọn khi nhập điểm
    public var selectableClassesForGrades: [ClassGroupEntity] {
        if !enrolledClasses.isEmpty {
            return enrolledClasses
        }
        return allClasses.filter { !$0.isArchived }
    }

    /// Danh sách các tháng có phát sinh buổi dạy hoặc thanh toán để hiển thị bộ lọc tháng
    public var availableTuitionMonths: [Date] {
        let calendar = Calendar.current
        var monthStarts: Set<Date> = []

        if let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) {
            monthStarts.insert(currentMonth)
        }

        for item in studentSessionTuitionItems {
            if let m = calendar.date(from: calendar.dateComponents([.year, .month], from: item.session.startTime)) {
                monthStarts.insert(m)
            }
        }
        for payment in studentPayments {
            if let m = calendar.date(from: calendar.dateComponents([.year, .month], from: payment.paidAt)) {
                monthStarts.insert(m)
            }
        }
        return monthStarts.sorted(by: >)
    }

    /// Các buổi đã dạy cho học sinh theo bộ lọc tháng hiện tại (`nil` = Tất cả)
    public var filteredSessionTuitionItems: [StudentSessionTuitionItem] {
        guard let month = selectedTuitionMonth else {
            return studentSessionTuitionItems
        }
        let cal = Calendar.current
        return studentSessionTuitionItems.filter {
            cal.isDate($0.session.startTime, equalTo: month, toGranularity: .month)
        }
    }

    /// Các giao dịch thanh toán theo bộ lọc tháng hiện tại (`nil` = Tất cả)
    public var filteredPayments: [PaymentEntity] {
        guard let month = selectedTuitionMonth else {
            return studentPayments
        }
        let cal = Calendar.current
        return studentPayments.filter {
            cal.isDate($0.paidAt, equalTo: month, toGranularity: .month)
        }
    }

    /// Số liệu thống kê Học phí cho kỳ đang chọn (hoặc toàn bộ nếu `selectedTuitionMonth == nil`)
    /// Luôn tách bạch với `studentFinanceSummary.outstandingBalance` (tổng nợ toàn bộ đến hiện tại)
    public var periodTuitionMetrics: (sessionCount: Int, presentCount: Int, accrued: Int64, collected: Int64) {
        let items = filteredSessionTuitionItems
        let sessionCount = items.count
        let presentCount = items.filter { $0.attendance.status == .present }.count

        if let month = selectedTuitionMonth {
            let cal = Calendar.current
            let accrued = items.reduce(0 as Int64) { $0 + $1.accruedAmount }
            // Hoặc cộng các khoản charge phát sinh trong tháng đó nếu buổi chưa liên kết
            let monthCharges = studentCharges.filter {
                cal.isDate($0.createdAt, equalTo: month, toGranularity: .month)
            }
            let finalAccrued = max(accrued, monthCharges.reduce(0 as Int64) { $0 + $1.amount })
            let collected = filteredPayments.reduce(0 as Int64) { $0 + $1.amount }
            return (sessionCount, presentCount, finalAccrued, collected)
        } else {
            return (
                sessionCount,
                presentCount,
                studentFinanceSummary.accruedTuition,
                studentFinanceSummary.collectedTuition
            )
        }
    }

    public func classGroup(for id: UUID) -> ClassGroupEntity? {
        allClasses.first(where: { $0.id == id }) ?? enrolledClasses.first(where: { $0.id == id })
    }

    public func effectivePrice(for classGroup: ClassGroupEntity) -> Int64 {
        effectivePriceUseCase.execute(student: student, classGroup: classGroup)
    }

    // MARK: - Data Loading

    public func loadEnrolledClasses() async {
        isLoading = true
        errorMessage = nil
        do {
            // Làm mới thông tin học sinh từ DB
            if let latestStudent = try await studentRepository.fetchStudent(byId: student.id) {
                self.student = latestStudent
            }

            let fetchedClasses = try await classRepository.fetchClasses(includeArchived: true)
            self.allClasses = fetchedClasses
            var classesById: [UUID: ClassGroupEntity] = [:]
            for c in fetchedClasses {
                classesById[c.id] = c
            }

            // 1. Tải toàn bộ danh sách tham gia lớp (cả đang học & lịch sử)
            let allEnrollments = try await classRepository.fetchEnrollments(forStudentId: student.id, activeOnly: false)
            var builtEnrollmentItems: [StudentClassEnrollmentItem] = []
            var activeClasses: [ClassGroupEntity] = []

            for enrollment in allEnrollments {
                let cGroup: ClassGroupEntity?
                if let cached = classesById[enrollment.classId] {
                    cGroup = cached
                } else {
                    cGroup = try await classRepository.fetchClass(byId: enrollment.classId)
                }

                if let cGroup {
                    classesById[cGroup.id] = cGroup
                    let price = effectivePriceUseCase.execute(student: student, classGroup: cGroup)
                    let isCustom = (student.defaultPricePerSession ?? 0) > 0
                    builtEnrollmentItems.append(
                        StudentClassEnrollmentItem(
                            enrollment: enrollment,
                            classGroup: cGroup,
                            effectivePrice: price,
                            isCustomPrice: isCustom
                        )
                    )
                    if enrollment.isActive && !cGroup.isArchived && !student.isArchived {
                        if !activeClasses.contains(where: { $0.id == cGroup.id }) {
                            activeClasses.append(cGroup)
                        }
                    }
                }
            }
            self.enrollmentItems = builtEnrollmentItems.sorted { $0.enrollment.enrolledAt > $1.enrollment.enrolledAt }
            self.enrolledClasses = activeClasses

            // 2. Tải Điểm số
            if let gradeRepo = gradeRepository {
                let grades = try await gradeRepo.fetchGradesForStudent(studentId: student.id)
                var items: [StudentGradeItem] = []
                for g in grades {
                    if let assessment = try await gradeRepo.fetchAssessment(byId: g.assessmentId) {
                        items.append(StudentGradeItem(grade: g, assessment: assessment))
                    }
                }
                self.studentGradeItems = items.sorted(by: { $0.assessment.date < $1.assessment.date })
            }

            // 3. Tải Bài tập
            if let assignRepo = assignmentRepository {
                let records = try await assignRepo.fetchRecordsForStudent(studentId: student.id)
                var pairs: [(record: AssignmentRecordEntity, assignment: AssignmentEntity)] = []
                for r in records {
                    if let assignment = try await assignRepo.fetchAssignment(byId: r.assignmentId) {
                        pairs.append((record: r, assignment: assignment))
                    }
                }
                self.studentAssignmentPairs = pairs
            }

            // 4. Tải Học phí (Charges, Payments, Allocations)
            var chargesBySessionId: [UUID: ChargeEntity] = [:]
            if let finRepo = financeRepository {
                let charges = try await finRepo.fetchChargesForStudent(studentId: student.id)
                let payments = try await finRepo.fetchPaymentsForStudent(studentId: student.id)
                self.studentCharges = charges
                self.studentPayments = payments

                var allAllocations: [PaymentAllocationEntity] = []
                for c in charges {
                    chargesBySessionId[c.sessionId] = c
                    let allocs = try await finRepo.fetchAllocationsForCharge(chargeId: c.id)
                    allAllocations.append(contentsOf: allocs)
                }
                self.studentAllocations = allAllocations

                let accrued = charges.reduce(0 as Int64) { $0 + $1.amount }
                let collected = payments.reduce(0 as Int64) { $0 + $1.amount }
                self.studentFinanceSummary = FinanceSummaryEntity(accruedTuition: accrued, collectedTuition: collected)
            }

            // 5. Tải Lịch dạy, Điểm danh, Buổi học tiếp theo & Danh sách buổi đã dạy kèm minh chứng
            if let schRepo = scheduleRepository {
                let atts = try await schRepo.fetchAttendancesForStudent(studentId: student.id)
                var records: [StudentAttendanceRecord] = []
                var tuitionItems: [StudentSessionTuitionItem] = []
                let now = Date()
                let calendar = Calendar.current
                var completedThisMonth = 0
                var upcomingCandidates: [(session: TeachingSessionEntity, className: String)] = []

                for a in atts {
                    if let session = try await schRepo.fetchSession(byId: a.sessionId) {
                        let cGroup = classesById[session.classId]
                        let className = cGroup?.name ?? "Lớp học"

                        records.append(StudentAttendanceRecord(
                            id: a.id,
                            sessionDate: session.startTime,
                            sessionTitle: session.title,
                            status: a.status,
                            notes: a.note
                        ))

                        // Đếm số buổi đã hoàn thành trong tháng hiện tại (học sinh có mặt hoặc buổi đã completed)
                        if session.status == .completed {
                            if calendar.isDate(session.startTime, equalTo: now, toGranularity: .month) && a.status == .present {
                                completedThisMonth += 1
                            }

                            let attachments = (try? await schRepo.fetchAttachments(forSessionId: session.id)) ?? []
                            let charge = chargesBySessionId[session.id]
                            let unitPrice = cGroup.map { effectivePriceUseCase.execute(student: student, classGroup: $0) }
                                ?? (student.defaultPricePerSession ?? 0)

                            tuitionItems.append(
                                StudentSessionTuitionItem(
                                    id: session.id,
                                    session: session,
                                    classGroup: cGroup,
                                    attendance: a,
                                    charge: charge,
                                    attachments: attachments,
                                    effectiveUnitPrice: unitPrice
                                )
                            )
                        } else if session.status == .scheduled && session.endTime >= now {
                            upcomingCandidates.append((session: session, className: className))
                        }
                    } else {
                        records.append(StudentAttendanceRecord(
                            id: a.id,
                            sessionDate: a.markedAt ?? Date(),
                            sessionTitle: "Buổi học",
                            status: a.status,
                            notes: a.note
                        ))
                    }
                }

                // Kiểm tra thêm các buổi học sắp tới của các lớp mà học sinh đang tham gia (nếu chưa khởi tạo điểm danh)
                for cGroup in activeClasses {
                    let classSessions = (try? await schRepo.fetchSessionsForClass(classId: cGroup.id)) ?? []
                    for s in classSessions where s.status == .scheduled && s.endTime >= now {
                        if !upcomingCandidates.contains(where: { $0.session.id == s.id }) {
                            upcomingCandidates.append((session: s, className: cGroup.name))
                        }
                    }
                }

                self.studentAttendances = records.sorted(by: { $0.sessionDate > $1.sessionDate })
                self.studentSessionTuitionItems = tuitionItems.sorted(by: { $0.session.startTime > $1.session.startTime })
                self.completedSessionsThisMonthCount = completedThisMonth
                self.nextUpcomingSession = upcomingCandidates
                    .sorted(by: { $0.session.startTime < $1.session.startTime })
                    .first
            }
        } catch {
            self.errorMessage = "Không thể tải dữ liệu học sinh: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func refreshStudent() async {
        if let updated = try? await studentRepository.fetchStudent(byId: student.id) {
            self.student = updated
        }
    }

    // MARK: - 1. Cập nhật thông tin học sinh (Header Edit)

    public func saveUpdatedStudent(_ updated: StudentEntity) async {
        do {
            try await studentRepository.saveStudent(updated)
            self.student = updated
            await loadEnrolledClasses()
        } catch {
            self.errorMessage = "Không thể lưu thông tin học sinh: \(error.localizedDescription)"
        }
    }

    // MARK: - 2. Quản lý Điểm số (Thêm / Sửa điểm, kiểm tra hợp lệ)

    public func saveOrUpdateGrade(
        existingItem: StudentGradeItem? = nil,
        classId: UUID,
        title: String,
        score: Double,
        maxScore: Double,
        weight: Double,
        date: Date,
        notes: String
    ) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NSError(domain: "GradeInput", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vui lòng nhập tên bài kiểm tra."])
        }
        guard weight > 0 else {
            throw NSError(domain: "GradeInput", code: 2, userInfo: [NSLocalizedDescriptionKey: "Hệ số điểm phải lớn hơn 0."])
        }

        // Kiểm tra điểm số theo quy tắc 0 <= score <= maxScore và maxScore > 0
        try validateGradeUseCase.execute(score: score, maxScore: maxScore)

        guard let gradeRepo = gradeRepository else {
            throw NSError(domain: "GradeInput", code: 3, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối kho dữ liệu điểm số."])
        }

        let assessmentId = existingItem?.assessment.id ?? UUID()
        let assessment = AssessmentEntity(
            id: assessmentId,
            classId: classId,
            title: trimmedTitle,
            maxScore: maxScore,
            weight: weight,
            date: date,
            createdAt: existingItem?.assessment.createdAt ?? Date()
        )
        try await gradeRepo.saveAssessment(assessment)

        let grade = GradeEntity(
            id: existingItem?.grade.id ?? UUID(),
            assessmentId: assessmentId,
            studentId: student.id,
            score: score,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            recordedAt: Date()
        )
        try await gradeRepo.saveGrade(grade)
        await loadEnrolledClasses()
    }

    // MARK: - 3. Quản lý Học phí (Ghi nhận thu tiền trực tiếp từ Chi tiết học sinh)

    /// Danh sách các khoản còn nợ của học sinh kèm thông tin buổi học để chọn thanh toán
    public var unpaidChargeSessionDetails: [StudentChargeSessionDetailItem] {
        studentCharges.compactMap { charge in
            let paid = studentAllocations
                .filter { $0.chargeId == charge.id }
                .reduce(0 as Int64) { $0 + $1.allocatedAmount }
            let effectivePaid = paid > 0 ? min(charge.amount, paid) : (charge.status == .paid ? charge.amount : 0)
            let rem = max(0, charge.amount - effectivePaid)
            guard rem > 0 else { return nil }

            let matchItem = studentSessionTuitionItems.first(where: { $0.session.id == charge.sessionId })
            let sTitle = matchItem?.session.title ?? "Buổi học"
            let sDate = matchItem?.session.startTime ?? charge.createdAt
            let cName = matchItem?.classGroup?.name ?? "Lớp học"
            let cColor = matchItem?.classGroup?.colorHex ?? "#F48FB1"
            let proofs = matchItem?.attachments ?? []

            return StudentChargeSessionDetailItem(
                charge: charge,
                session: matchItem?.session,
                sessionTitle: sTitle,
                sessionDate: sDate,
                className: cName,
                classColorHex: cColor,
                unitPriceSnapshot: charge.unitPriceSnapshot,
                allocatedPaidAmount: effectivePaid,
                remainingAmount: rem,
                attachments: proofs,
                isInSelectedPeriod: true
            )
        }
        .sorted { $0.charge.createdAt < $1.charge.createdAt }
    }

    public func recordPayment(
        amount: Int64,
        paidAt: Date,
        paymentMethod: String,
        note: String,
        selectedChargeIds: Set<UUID>? = nil
    ) async throws {
        guard let finRepo = financeRepository else { return }

        let charges = try await finRepo.fetchChargesForStudent(studentId: student.id)
        var existingAllocations: [PaymentAllocationEntity] = []
        for charge in charges {
            let allocs = try await finRepo.fetchAllocationsForCharge(chargeId: charge.id)
            existingAllocations.append(contentsOf: allocs)
        }

        let result = try recordPaymentUseCase.execute(
            studentId: student.id,
            amount: amount,
            paidAt: paidAt,
            paymentMethod: paymentMethod,
            note: note,
            studentCharges: charges,
            existingAllocations: existingAllocations,
            selectedChargeIds: selectedChargeIds
        )

        try await finRepo.savePayment(result.payment)
        try await finRepo.saveAllocations(result.allocations)
        try await finRepo.saveCharges(result.updatedCharges)

        await loadEnrolledClasses()
    }

    // MARK: - 4. Quản lý Lớp học & Thiết lập Lịch tháng (Thêm vào lớp -> Lịch tháng -> Xem trước -> Lưu)

    /// Xem trước danh sách các buổi học hiện có của một lớp từ ngày tham gia (Chưacompleted và chưa hủy)
    public func fetchEligibleExistingSessions(forClassId classId: UUID, from enrolledAt: Date) async -> [TeachingSessionEntity] {
        guard let schRepo = scheduleRepository else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: enrolledAt)
        let classSessions = (try? await schRepo.fetchSessionsForClass(classId: classId)) ?? []
        return classSessions
            .filter { $0.status == .scheduled && $0.startTime >= startOfDay }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Xem trước tất cả các buổi học hiện có của một lớp (bao gồm cả đã hoàn thành để giáo viên nắm rõ)
    public func fetchAllClassSessions(forClassId classId: UUID) async -> [TeachingSessionEntity] {
        guard let schRepo = scheduleRepository else { return [] }
        let classSessions = (try? await schRepo.fetchSessionsForClass(classId: classId)) ?? []
        return classSessions.sorted { $0.startTime < $1.startTime }
    }

    /// Xem trước tất cả các buổi học của toàn bộ các lớp trong khoảng ngày để kiểm tra trùng lịch
    public func fetchAllSessionsForOverlapCheck(from startDate: Date, to endDate: Date) async -> [TeachingSessionEntity] {
        guard let schRepo = scheduleRepository else { return [] }
        let cal = Calendar.current
        let paddedStart = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: startDate)) ?? startDate
        let paddedEnd = cal.date(byAdding: .day, value: 2, to: endDate) ?? endDate
        return (try? await schRepo.fetchSessions(from: paddedStart, to: paddedEnd)) ?? []
    }

    /// Thực hiện trọn vẹn luồng: Ghi danh học sinh vào lớp + Thiết lập đơn giá + Tạo các buổi lịch tháng mới (nếu có) + Thêm học sinh vào các buổi phù hợp từ ngày tham gia
    /// Cam kết:
    /// - Không tạo bản sao của buổi đã tồn tại.
    /// - Không tự thêm vào buổi đã hoàn thành hoặc trước ngày tham gia.
    /// - Không phát sinh học phí khi mới thêm vào lớp hoặc tạo lịch.
    public func enrollStudentInClass(
        classId: UUID,
        enrolledAt: Date,
        useCustomPrice: Bool,
        customPrice: Int64?,
        newMonthlySessionsToCreate: [TeachingSessionEntity] = []
    ) async throws {
        let cal = Calendar.current
        let startOfEnrollmentDay = cal.startOfDay(for: enrolledAt)

        // 1. Kiểm tra giờ kết thúc sau giờ bắt đầu cho tất cả buổi mới (nếu có)
        for s in newMonthlySessionsToCreate {
            guard s.endTime > s.startTime else {
                throw NSError(
                    domain: "ScheduleValidation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Giờ kết thúc phải sau giờ bắt đầu."]
                )
            }
        }

        // 2. Thực hiện ghi danh vào lớp (nếu học sinh chưa active trong lớp này)
        let isAlreadyEnrolled = try await classRepository.isStudentEnrolled(studentId: student.id, classId: classId)
        if !isAlreadyEnrolled {
            var effectiveEnrolledAt = enrolledAt
            let pastEnrollments = try await classRepository.fetchEnrollments(forStudentId: student.id, activeOnly: false)
            for past in pastEnrollments where past.classId == classId && !past.isActive {
                if let leftAt = past.leftAt, cal.isDate(effectiveEnrolledAt, inSameDayAs: leftAt), effectiveEnrolledAt < leftAt {
                    effectiveEnrolledAt = leftAt.addingTimeInterval(1)
                }
            }
            try await classRepository.enrollStudent(
                studentId: student.id,
                classId: classId,
                enrolledAt: effectiveEnrolledAt
            )
        }

        // 3. Cập nhật đơn giá riêng nếu giáo viên thiết lập
        if useCustomPrice, let customPrice, customPrice > 0 {
            var updatedStudent = student
            updatedStudent.defaultPricePerSession = customPrice
            updatedStudent.updatedAt = Date()
            try await studentRepository.saveStudent(updatedStudent)
            self.student = updatedStudent
        } else if !useCustomPrice && student.defaultPricePerSession != nil {
            var updatedStudent = student
            updatedStudent.defaultPricePerSession = nil
            updatedStudent.updatedAt = Date()
            try await studentRepository.saveStudent(updatedStudent)
            self.student = updatedStudent
        }

        // 4. Lưu các buổi học mới (nếu giáo viên vừa thiết lập lịch tháng) & đồng bộ điểm danh
        if let schRepo = scheduleRepository {
            let existingClassSessions = try await schRepo.fetchSessionsForClass(classId: classId)
            let activeEnrollments = try await classRepository.fetchEnrollments(forClassId: classId, activeOnly: true)
            var activeClassStudentIds = Set(activeEnrollments.map { $0.studentId })
            activeClassStudentIds.insert(student.id)

            // 4a. Lưu các buổi lịch tháng mới (chống tạo trùng với buổi đã tồn tại của lớp)
            for newSession in newMonthlySessionsToCreate {
                let isDuplicate = existingClassSessions.contains { existing in
                    existing.status != .cancelled &&
                    cal.isDate(existing.startTime, inSameDayAs: newSession.startTime) &&
                    abs(existing.startTime.timeIntervalSince(newSession.startTime)) < 120
                }
                if !isDuplicate {
                    try await schRepo.saveSession(newSession)
                    await LocalNotificationService.shared.scheduleSessionReminder(for: newSession)

                    // Khởi tạo điểm danh .pending cho các học sinh đang tham gia lớp (trong đó có học sinh này nếu buổi >= ngày tham gia)
                    var initialAttendances: [AttendanceEntity] = []
                    for sid in activeClassStudentIds {
                        if sid == student.id && newSession.startTime < startOfEnrollmentDay {
                            continue
                        }
                        initialAttendances.append(
                            AttendanceEntity(
                                sessionId: newSession.id,
                                studentId: sid,
                                status: .pending
                            )
                        )
                    }
                    if !initialAttendances.isEmpty {
                        try await schRepo.saveAttendances(initialAttendances)
                    }
                }
            }

            // 4b. Với các buổi học hiện có của lớp: Chỉ thêm học sinh vào các buổi .scheduled từ ngày bắt đầu tham gia trở đi
            // Tuyệt đối không thêm vào buổi .completed, .cancelled hoặc trước ngày tham gia
            let allUpdatedClassSessions = try await schRepo.fetchSessionsForClass(classId: classId)
            for session in allUpdatedClassSessions {
                guard session.status == .scheduled && session.startTime >= startOfEnrollmentDay else {
                    continue
                }
                let existingAtts = try await schRepo.fetchAttendances(forSessionId: session.id)
                if !existingAtts.contains(where: { $0.studentId == student.id }) {
                    let newAtt = AttendanceEntity(
                        sessionId: session.id,
                        studentId: student.id,
                        status: .pending
                    )
                    try await schRepo.saveAttendance(newAtt)
                }
            }
        }

        await loadEnrolledClasses()
    }

    public func endClassParticipation(classId: UUID, leftAt: Date = Date()) async {
        do {
            try await classRepository.unenrollStudent(
                studentId: student.id,
                classId: classId,
                leftAt: leftAt
            )
            await loadEnrolledClasses()
        } catch {
            self.errorMessage = "Không thể kết thúc tham gia lớp: \(error.localizedDescription)"
        }
    }

    // MARK: - 5. Lưu trữ & Xóa vĩnh viễn an toàn

    public func archiveStudent() async {
        do {
            try await studentRepository.archiveStudent(id: student.id)
            student.isArchived = true
            await loadEnrolledClasses()
        } catch {
            self.errorMessage = "Không thể lưu trữ: \(error.localizedDescription)"
        }
    }

    public func restoreStudent() async {
        do {
            try await studentRepository.restoreStudent(id: student.id)
            student.isArchived = false
            await loadEnrolledClasses()
        } catch {
            self.errorMessage = "Không thể khôi phục: \(error.localizedDescription)"
        }
    }

    public func requestDelete() async {
        let outstanding = studentFinanceSummary.outstandingBalance
        let hasUnpaid = studentCharges.contains { $0.status != .paid }
        let hasFinancialHistory = !studentCharges.isEmpty || !studentPayments.isEmpty

        if outstanding > 0 || hasUnpaid || hasFinancialHistory {
            self.debtAmount = max(outstanding, 0)
            self.hasFinancialHistoryBlock = hasFinancialHistory && outstanding == 0
            self.isDeleteBlockedShowing = true
        } else {
            self.isDeleteConfirmationShowing = true
        }
    }

    public func executeDelete() async {
        do {
            try await studentRepository.deleteStudent(id: student.id)
            self.isDismissRequired = true
        } catch {
            self.errorMessage = "Không thể xóa học sinh: \(error.localizedDescription)"
        }
    }
}
