import Foundation
import Observation

/// Các mục trong màn hình Chi tiết Lớp học
public enum ClassDetailSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "Tổng quan"
    case students = "Học sinh"
    case schedule = "Lịch dạy"
    case finance = "Học phí"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .overview: return L("Tổng quan", "Overview")
        case .students: return L("Học sinh", "Students")
        case .schedule: return L("Lịch dạy", "Schedule")
        case .finance: return L("Học phí", "Tuition")
        }
    }

    public var iconName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .students: return "person.2.fill"
        case .schedule: return "calendar"
        case .finance: return "dollarsign.circle.fill"
        }
    }
}

/// Tổng hợp học phí theo từng học sinh trong phạm vi lớp học
public struct ClassStudentTuitionSummary: Identifiable, Sendable {
    public var id: UUID { student.id }
    public let student: StudentEntity
    public let completedSessionsCount: Int
    public let accruedAmount: Int64
    public let collectedAmount: Int64
    public let outstandingAmount: Int64
    public let unpaidSessionDetails: [StudentChargeSessionDetailItem]

    public init(
        student: StudentEntity,
        completedSessionsCount: Int,
        accruedAmount: Int64,
        collectedAmount: Int64,
        outstandingAmount: Int64,
        unpaidSessionDetails: [StudentChargeSessionDetailItem]
    ) {
        self.student = student
        self.completedSessionsCount = completedSessionsCount
        self.accruedAmount = accruedAmount
        self.collectedAmount = collectedAmount
        self.outstandingAmount = outstandingAmount
        self.unpaidSessionDetails = unpaidSessionDetails
    }
}

/// Lịch sử thu tiền liên quan đến lớp học
public struct ClassPaymentHistoryItem: Identifiable, Sendable {
    public let id: UUID
    public let student: StudentEntity
    public let amountAllocatedToClass: Int64
    public let paidAt: Date
    public let paymentMethod: String
    public let note: String

    public init(
        id: UUID,
        student: StudentEntity,
        amountAllocatedToClass: Int64,
        paidAt: Date,
        paymentMethod: String,
        note: String
    ) {
        self.id = id
        self.student = student
        self.amountAllocatedToClass = amountAllocatedToClass
        self.paidAt = paidAt
        self.paymentMethod = paymentMethod
        self.note = note
    }
}

/// ViewModel quản lý Chi tiết Lớp học: Tổng quan, Học sinh trong lớp, Lịch dạy & Học phí liên quan
@Observable
@MainActor
public final class ClassDetailViewModel {
    public var classGroup: ClassGroupEntity
    public var activeSection: ClassDetailSection = .overview
    public var enrolledStudents: [StudentEntity] = []
    public var availableStudentsToEnroll: [StudentEntity] = []
    public var classSessions: [TeachingSessionEntity] = []
    public var allSystemSessions: [TeachingSessionEntity] = []

    // Dữ liệu Học phí liên quan của lớp
    public var totalAccruedAmount: Int64 = 0
    public var totalCollectedAmount: Int64 = 0
    public var totalOutstandingAmount: Int64 = 0
    public var studentTuitionSummaries: [ClassStudentTuitionSummary] = []
    public var classPaymentHistory: [ClassPaymentHistoryItem] = []

    public var isLoading: Bool = false
    public private(set) var isSavingEnrollment: Bool = false
    public private(set) var isSavingSchedule: Bool = false
    public var errorMessage: String? = nil

    public var isShowingSimpleDeleteAlert: Bool = false
    public var unpaidDeletePrompt: ClassUnpaidDeletionPrompt? = nil
    public var didDeleteClass: Bool = false

    public let classRepository: ClassRepositoryProtocol
    public let studentRepository: StudentRepositoryProtocol
    public var scheduleRepository: ScheduleRepositoryProtocol?
    public var financeRepository: FinanceRepositoryProtocol?

    private let recurringUseCase = GenerateRecurringSessionsUseCase()
    private let overlapUseCase = CheckScheduleOverlapUseCase()
    private let recordPaymentUseCase = RecordPaymentUseCase()

    public init(
        classGroup: ClassGroupEntity,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil
    ) {
        self.classGroup = classGroup
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
    }

    /// Các buổi dạy sắp tới (.scheduled và chưa kết thúc), sắp xếp gần nhất trước
    public var upcomingSessions: [TeachingSessionEntity] {
        let now = Date()
        return classSessions
            .filter { $0.status == .scheduled && $0.endTime >= now }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Buổi dạy tiếp theo gần nhất của lớp
    public var nextUpcomingSession: TeachingSessionEntity? {
        upcomingSessions.first
    }

    /// Các buổi dạy đã hoàn thành, đã qua hoặc đã hủy, sắp xếp mới nhất trước
    public var historySessions: [TeachingSessionEntity] {
        let now = Date()
        return classSessions
            .filter { $0.status != .scheduled || $0.endTime < now }
            .sorted { $0.startTime > $1.startTime }
    }

    public func loadMembers() async {
        isLoading = true
        errorMessage = nil
        do {
            if let latestClass = try await classRepository.fetchClass(byId: classGroup.id) {
                self.classGroup = latestClass
            }

            let enrollments = try await classRepository.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
            var members: [StudentEntity] = []
            for e in enrollments {
                if let student = try await studentRepository.fetchStudent(byId: e.studentId) {
                    members.append(student)
                }
            }
            self.enrolledStudents = members

            // Tải danh sách học sinh chưa ghi danh vào lớp này
            let allActiveStudents = try await studentRepository.fetchStudents(includeArchived: false)
            let memberIds = Set(members.map { $0.id })
            self.availableStudentsToEnroll = allActiveStudents.filter { !memberIds.contains($0.id) }

            if let schRepo = scheduleRepository {
                let sessions = try await schRepo.fetchSessionsForClass(classId: classGroup.id)
                self.classSessions = sessions.sorted(by: { $0.startTime > $1.startTime })

                let cal = Calendar.current
                let now = Date()
                let winStart = cal.date(byAdding: .day, value: -30, to: now) ?? now
                let winEnd = cal.date(byAdding: .day, value: 180, to: now) ?? now
                self.allSystemSessions = (try? await schRepo.fetchSessions(from: winStart, to: winEnd)) ?? sessions
            }

            await loadClassFinanceData()
        } catch {
            self.errorMessage = "Không thể tải dữ liệu lớp học: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Tính toán học phí liên quan của lớp:
    /// Đảm bảo quy tắc bất biến: Đã phát sinh (Accrued) - Đã thu (Collected) = Còn nợ (Outstanding)
    private func loadClassFinanceData() async {
        guard let finRepo = financeRepository else {
            self.totalAccruedAmount = 0
            self.totalCollectedAmount = 0
            self.totalOutstandingAmount = 0
            self.studentTuitionSummaries = []
            self.classPaymentHistory = []
            return
        }

        do {
            let sessionsById = Dictionary(uniqueKeysWithValues: classSessions.map { ($0.id, $0) })
            let classSessionIds = Set(sessionsById.keys)

            let allEnrollments = try await classRepository.fetchEnrollments(forClassId: classGroup.id, activeOnly: false)
            var studentsMap: [UUID: StudentEntity] = Dictionary(uniqueKeysWithValues: enrolledStudents.map { ($0.id, $0) })
            for e in allEnrollments where studentsMap[e.studentId] == nil {
                if let s = try await studentRepository.fetchStudent(byId: e.studentId) {
                    studentsMap[s.id] = s
                }
            }

            let allCharges = try await finRepo.fetchCharges()
            let classCharges = allCharges.filter { classSessionIds.contains($0.sessionId) }

            let allPayments = try await finRepo.fetchPayments()
            let paymentsById = Dictionary(uniqueKeysWithValues: allPayments.map { ($0.id, $0) })

            var totalAccrued: Int64 = 0
            var totalCollected: Int64 = 0

            var chargesByStudent: [UUID: [ChargeEntity]] = [:]
            var paidByChargeId: [UUID: Int64] = [:]
            var paymentAllocatedInClass: [UUID: (studentId: UUID, amount: Int64)] = [:]

            for charge in classCharges {
                totalAccrued += charge.amount
                chargesByStudent[charge.studentId, default: []].append(charge)

                let allocs = try await finRepo.fetchAllocationsForCharge(chargeId: charge.id)
                let paidForCharge = min(charge.amount, allocs.reduce(Int64(0)) { $0 + $1.allocatedAmount })
                paidByChargeId[charge.id] = paidForCharge
                totalCollected += paidForCharge

                for alloc in allocs where alloc.allocatedAmount > 0 {
                    let prev = paymentAllocatedInClass[alloc.paymentId]?.amount ?? 0
                    paymentAllocatedInClass[alloc.paymentId] = (charge.studentId, prev + alloc.allocatedAmount)
                }
            }

            self.totalAccruedAmount = totalAccrued
            self.totalCollectedAmount = totalCollected
            self.totalOutstandingAmount = max(0, totalAccrued - totalCollected)

            // Xây dựng bảng học phí theo từng học sinh trong lớp
            let allRelevantStudentIds = Set(enrolledStudents.map { $0.id }).union(chargesByStudent.keys)
            var summaries: [ClassStudentTuitionSummary] = []

            for studentId in allRelevantStudentIds {
                let student: StudentEntity
                if let cached = studentsMap[studentId] {
                    student = cached
                } else if let fetched = try await studentRepository.fetchStudent(byId: studentId) {
                    student = fetched
                    studentsMap[studentId] = fetched
                } else {
                    continue
                }

                let stuCharges = (chargesByStudent[studentId] ?? []).sorted { $0.createdAt > $1.createdAt }
                let stuAccrued = stuCharges.reduce(Int64(0)) { $0 + $1.amount }
                let stuCollected = stuCharges.reduce(Int64(0)) { $0 + (paidByChargeId[$1.id] ?? 0) }
                let stuOutstanding = max(0, stuAccrued - stuCollected)

                var unpaidDetails: [StudentChargeSessionDetailItem] = []
                for ch in stuCharges {
                    let paid = paidByChargeId[ch.id] ?? 0
                    let rem = max(0, ch.amount - paid)
                    if rem > 0 {
                        let sess = sessionsById[ch.sessionId]
                        unpaidDetails.append(
                            StudentChargeSessionDetailItem(
                                charge: ch,
                                session: sess,
                                sessionTitle: sess?.title ?? classGroup.name,
                                sessionDate: sess?.startTime ?? ch.createdAt,
                                className: classGroup.name,
                                classColorHex: classGroup.colorHex,
                                unitPriceSnapshot: ch.unitPriceSnapshot,
                                allocatedPaidAmount: paid,
                                remainingAmount: rem
                            )
                        )
                    }
                }

                summaries.append(
                    ClassStudentTuitionSummary(
                        student: student,
                        completedSessionsCount: stuCharges.count,
                        accruedAmount: stuAccrued,
                        collectedAmount: stuCollected,
                        outstandingAmount: stuOutstanding,
                        unpaidSessionDetails: unpaidDetails
                    )
                )
            }

            self.studentTuitionSummaries = summaries.sorted {
                if $0.outstandingAmount != $1.outstandingAmount {
                    return $0.outstandingAmount > $1.outstandingAmount
                }
                return $0.student.fullName < $1.student.fullName
            }

            // Xây dựng lịch sử thu tiền của lớp
            var historyItems: [ClassPaymentHistoryItem] = []
            for (paymentId, info) in paymentAllocatedInClass {
                if let payment = paymentsById[paymentId],
                   let student = studentsMap[info.studentId] {
                    historyItems.append(
                        ClassPaymentHistoryItem(
                            id: payment.id,
                            student: student,
                            amountAllocatedToClass: info.amount,
                            paidAt: payment.paidAt,
                            paymentMethod: payment.paymentMethod,
                            note: payment.note
                        )
                    )
                }
            }
            self.classPaymentHistory = historyItems.sorted { $0.paidAt > $1.paidAt }
        } catch {
            // Không chặn hiển thị lớp nếu tải thống kê học phí gặp lỗi phụ
        }
    }

    // MARK: - Thiết lập Lịch theo tháng & Tạo buổi dạy cho Lớp

    /// Xem trước các buổi học sẽ được tạo theo tháng cho lớp (tự động bỏ qua buổi đã tồn tại cùng khung giờ)
    public func previewMonthlySessions(
        selectedDays: Set<DayOfWeek>,
        startDate: Date,
        endDate: Date,
        sessionStartTime: Date,
        sessionEndTime: Date
    ) -> [TeachingSessionEntity] {
        guard !selectedDays.isEmpty, endDate >= startDate else { return [] }
        let cal = Calendar.current
        let startComp = cal.dateComponents([.hour, .minute], from: sessionStartTime)
        let endComp = cal.dateComponents([.hour, .minute], from: sessionEndTime)
        let startMins = (startComp.hour ?? 0) * 60 + (startComp.minute ?? 0)
        let endMins = (endComp.hour ?? 0) * 60 + (endComp.minute ?? 0)
        guard endMins > startMins else { return [] }
        let durationMins = max(15, endMins - startMins)

        var templateStartComp = cal.dateComponents([.year, .month, .day], from: startDate)
        templateStartComp.hour = startComp.hour
        templateStartComp.minute = startComp.minute
        let tStart = cal.date(from: templateStartComp) ?? startDate
        let tEnd = tStart.addingTimeInterval(TimeInterval(durationMins * 60))

        let template = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi học: \(classGroup.name)",
            startTime: tStart,
            endTime: tEnd,
            status: .scheduled
        )

        return recurringUseCase.execute(
            templateSession: template,
            selectedDays: selectedDays,
            startDate: cal.startOfDay(for: startDate),
            endDate: endDate,
            existingSessions: classSessions
        )
    }

    /// Kiểm tra trùng lịch với các lớp khác
    public func checkOverlaps(
        for candidates: [TeachingSessionEntity]
    ) -> [(newSession: TeachingSessionEntity, conflictWith: TeachingSessionEntity)] {
        var conflicts: [(TeachingSessionEntity, TeachingSessionEntity)] = []
        for candidate in candidates {
            if let hit = overlapUseCase.execute(
                newStartTime: candidate.startTime,
                newEndTime: candidate.endTime,
                existingSessions: allSystemSessions
            ) {
                conflicts.append((candidate, hit))
            }
        }
        return conflicts
    }

    /// Tạo lịch dạy theo tháng cho lớp học:
    /// - Chống bấm lưu trùng (`isSavingSchedule`).
    /// - Khởi tạo điểm danh `.pending` cho toàn bộ học sinh đang tham gia lớp.
    /// - Lên lịch thông báo nhắc trước 60 phút.
    /// - Tuyệt đối chưa phát sinh học phí khi mới tạo lịch.
    @discardableResult
    public func createMonthlySchedule(
        selectedDays: Set<DayOfWeek>,
        startDate: Date,
        endDate: Date,
        sessionStartTime: Date,
        sessionEndTime: Date
    ) async -> Int {
        guard !isSavingSchedule, let schRepo = scheduleRepository else { return 0 }
        let sessionsToCreate = previewMonthlySessions(
            selectedDays: selectedDays,
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: sessionStartTime,
            sessionEndTime: sessionEndTime
        )
        guard !sessionsToCreate.isEmpty else { return 0 }

        isSavingSchedule = true
        defer { isSavingSchedule = false }
        errorMessage = nil

        do {
            let activeEnrollments = try await classRepository.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
            let activeStudentIds = activeEnrollments.map { $0.studentId }

            var savedCount = 0
            for session in sessionsToCreate {
                try await schRepo.saveSession(session)
                await LocalNotificationService.shared.scheduleSessionReminder(for: session)

                if !activeStudentIds.isEmpty {
                    let initialAttendances = activeStudentIds.map { studentId in
                        AttendanceEntity(
                            sessionId: session.id,
                            studentId: studentId,
                            status: .pending
                        )
                    }
                    try await schRepo.saveAttendances(initialAttendances)
                }
                savedCount += 1
            }

            await loadMembers()
            return savedCount
        } catch {
            self.errorMessage = "Không thể lưu lịch dạy theo tháng: \(error.localizedDescription)"
            return 0
        }
    }

    /// Tạo một buổi dạy lẻ cho lớp học
    @discardableResult
    public func createSingleSession(_ session: TeachingSessionEntity, participantStudentIds: [UUID] = []) async -> Bool {
        guard !isSavingSchedule, let schRepo = scheduleRepository else { return false }
        isSavingSchedule = true
        defer { isSavingSchedule = false }
        errorMessage = nil

        do {
            try await schRepo.saveSession(session)
            if session.status == .scheduled {
                await LocalNotificationService.shared.scheduleSessionReminder(for: session)
            }

            let targetStudentIds = participantStudentIds.isEmpty
                ? enrolledStudents.map { $0.id }
                : participantStudentIds
            if !targetStudentIds.isEmpty {
                let attendances = targetStudentIds.map { sid in
                    AttendanceEntity(
                        sessionId: session.id,
                        studentId: sid,
                        status: .pending
                    )
                }
                try await schRepo.saveAttendances(attendances)
            }

            await loadMembers()
            return true
        } catch {
            self.errorMessage = "Không thể lưu buổi học: \(error.localizedDescription)"
            return false
        }
    }

    /// Ghi nhận thu học phí cho học sinh ngay trong màn hình Chi tiết Lớp học
    public func recordPaymentForStudent(
        studentId: UUID,
        amount: Int64,
        paidAt: Date,
        paymentMethod: String,
        note: String,
        selectedChargeIds: Set<UUID>? = nil
    ) async throws {
        guard let finRepo = financeRepository else { return }
        let charges = try await finRepo.fetchChargesForStudent(studentId: studentId)
        var existingAllocations: [PaymentAllocationEntity] = []
        for charge in charges {
            let allocs = try await finRepo.fetchAllocationsForCharge(chargeId: charge.id)
            existingAllocations.append(contentsOf: allocs)
        }

        // Mặc định ưu tiên phân bổ vào các khoản nợ thuộc lớp này nếu người dùng không truyền danh sách chọn riêng
        let classSessionIds = Set(classSessions.map { $0.id })
        let defaultClassChargeIds = Set(
            charges
                .filter { classSessionIds.contains($0.sessionId) && $0.status != .paid }
                .map { $0.id }
        )

        let targetChargeIds = (selectedChargeIds?.isEmpty == false)
            ? selectedChargeIds
            : (defaultClassChargeIds.isEmpty ? nil : defaultClassChargeIds)

        let result = try recordPaymentUseCase.execute(
            studentId: studentId,
            amount: amount,
            paidAt: paidAt,
            paymentMethod: paymentMethod,
            note: note,
            studentCharges: charges,
            existingAllocations: existingAllocations,
            selectedChargeIds: targetChargeIds
        )

        try await finRepo.savePayment(result.payment)
        try await finRepo.saveAllocations(result.allocations)
        try await finRepo.saveCharges(result.updatedCharges)

        await loadMembers()
    }

    public func enrollStudent(id: UUID, enrolledAt: Date = Date()) async {
        _ = await enrollStudents(ids: [id], enrolledAt: enrolledAt)
    }

    /// Ghi danh một hoặc nhiều học sinh có sẵn vào lớp (chống bấm trùng, không phát sinh học phí)
    @discardableResult
    public func enrollStudents(ids: [UUID], enrolledAt: Date = Date()) async -> Bool {
        guard !isSavingEnrollment, !ids.isEmpty else { return false }
        isSavingEnrollment = true
        defer { isSavingEnrollment = false }
        errorMessage = nil

        do {
            let uniqueIds = Array(Set(ids))
            for studentId in uniqueIds {
                let alreadyEnrolled = try await classRepository.isStudentEnrolled(studentId: studentId, classId: classGroup.id)
                if !alreadyEnrolled {
                    try await classRepository.enrollStudent(studentId: studentId, classId: classGroup.id, enrolledAt: enrolledAt)
                }
                await syncPendingAttendanceForFutureSessions(studentId: studentId, enrolledAt: enrolledAt)
            }
            await loadMembers()
            return true
        } catch {
            self.errorMessage = "Không thể thêm học sinh vào lớp: \(error.localizedDescription)"
            return false
        }
    }

    /// Tạo học sinh mới và thêm thẳng vào lớp hiện tại (chống bấm trùng, không phát sinh học phí)
    @discardableResult
    public func createAndEnrollStudent(_ student: StudentEntity, enrolledAt: Date = Date()) async -> Bool {
        guard !isSavingEnrollment else { return false }
        let trimmedName = student.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            self.errorMessage = "Vui lòng nhập họ và tên học sinh."
            return false
        }
        if let customPrice = student.defaultPricePerSession, customPrice <= 0 {
            self.errorMessage = "Đơn giá riêng mỗi buổi phải lớn hơn 0 đ."
            return false
        }

        isSavingEnrollment = true
        defer { isSavingEnrollment = false }
        errorMessage = nil

        do {
            var sanitized = student
            sanitized.fullName = trimmedName
            sanitized.phoneNumber = student.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.parentPhone = student.parentPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.email = student.email.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.notes = student.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            try await studentRepository.saveStudent(sanitized)
            try await classRepository.enrollStudent(studentId: sanitized.id, classId: classGroup.id, enrolledAt: enrolledAt)
            await syncPendingAttendanceForFutureSessions(studentId: sanitized.id, enrolledAt: enrolledAt)
            await loadMembers()
            return true
        } catch {
            self.errorMessage = "Không thể tạo và thêm học sinh vào lớp: \(error.localizedDescription)"
            return false
        }
    }

    private func syncPendingAttendanceForFutureSessions(studentId: UUID, enrolledAt: Date) async {
        guard let schRepo = scheduleRepository else { return }
        do {
            let classSessions = try await schRepo.fetchSessionsForClass(classId: classGroup.id)
            let startOfDay = Calendar.current.startOfDay(for: enrolledAt)
            for session in classSessions where session.status == .scheduled && session.startTime >= startOfDay {
                let existingAtts = try await schRepo.fetchAttendances(forSessionId: session.id)
                if !existingAtts.contains(where: { $0.studentId == studentId }) {
                    let newAtt = AttendanceEntity(
                        sessionId: session.id,
                        studentId: studentId,
                        status: .pending
                    )
                    try await schRepo.saveAttendance(newAtt)
                }
            }
        } catch {
            // Không chặn luồng ghi danh nếu đồng bộ điểm danh nháp gặp lỗi phụ
        }
    }

    public func unenrollStudent(id: UUID, leftAt: Date = Date()) async {
        do {
            try await classRepository.unenrollStudent(studentId: id, classId: classGroup.id, leftAt: leftAt)
            await loadMembers()
        } catch {
            self.errorMessage = "Không thể kết thúc học sinh khỏi lớp: \(error.localizedDescription)"
        }
    }

    public func archiveClass() async {
        do {
            try await classRepository.archiveClass(id: classGroup.id)
            await loadMembers()
        } catch {
            self.errorMessage = "Không thể lưu trữ lớp học: \(error.localizedDescription)"
        }
    }

    public func restoreClass() async {
        do {
            try await classRepository.restoreClass(id: classGroup.id)
            await loadMembers()
        } catch {
            self.errorMessage = "Không thể khôi phục lớp học: \(error.localizedDescription)"
        }
    }

    public func requestDeleteArchivedClass() async {
        let helper = ClassListViewModel(
            classRepository: classRepository,
            scheduleRepository: scheduleRepository,
            financeRepository: financeRepository
        )
        await helper.requestDeleteArchivedClass(classGroup)
        if let err = helper.errorMessage {
            self.errorMessage = err
        } else if let unpaid = helper.classPendingUnpaidDelete {
            self.isShowingSimpleDeleteAlert = false
            self.unpaidDeletePrompt = unpaid
        } else if helper.classPendingSimpleDelete != nil {
            self.unpaidDeletePrompt = nil
            self.isShowingSimpleDeleteAlert = true
        }
    }

    public func confirmDeleteArchivedClass(confirmPaidIfUnpaid: Bool) async {
        let helper = ClassListViewModel(
            classRepository: classRepository,
            scheduleRepository: scheduleRepository,
            financeRepository: financeRepository
        )
        await helper.confirmDeleteClass(id: classGroup.id, confirmPaidIfUnpaid: confirmPaidIfUnpaid)
        if let err = helper.errorMessage {
            self.errorMessage = err
        } else {
            self.isShowingSimpleDeleteAlert = false
            self.unpaidDeletePrompt = nil
            self.didDeleteClass = true
        }
    }
}
