import Foundation
import Observation

/// Mục lọc thời gian (kỳ) cho báo cáo và danh sách học phí
public enum FinanceTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case allTime = "Tất cả"
    case thisMonth = "Tháng này"
    case lastMonth = "Tháng trước"
    case customMonth = "Chọn tháng"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .allTime: return L("Tất cả", "All")
        case .thisMonth: return L("Tháng này", "This Month")
        case .lastMonth: return L("Tháng trước", "Last Month")
        case .customMonth: return L("Chọn tháng", "Custom")
        }
    }
}

/// Trạng thái thanh toán học phí của học sinh
public enum StudentTuitionPaymentStatus: String, CaseIterable, Identifiable, Sendable {
    case unpaid = "Chưa thanh toán"
    case partiallyPaid = "Thanh toán một phần"
    case paid = "Đã hoàn tất"
    case noCharges = "Chưa phát sinh"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .unpaid: return L("Chưa thanh toán", "Unpaid")
        case .partiallyPaid: return L("Thanh toán một phần", "Partially Paid")
        case .paid: return L("Đã hoàn tất", "Paid")
        case .noCharges: return L("Chưa phát sinh", "No Charges")
        }
    }
}

/// Bộ lọc trạng thái thanh toán trên danh sách học phí học sinh
public enum StudentTuitionStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Tất cả"
    case hasOutstanding = "Còn nợ"
    case partiallyPaid = "Một phần"
    case unpaid = "Chưa thu"
    case paid = "Đã thu đủ"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .all: return L("Tất cả", "All")
        case .hasOutstanding: return L("Còn nợ", "Outstanding")
        case .partiallyPaid: return L("Một phần", "Partial")
        case .unpaid: return L("Chưa thu", "Unpaid")
        case .paid: return L("Đã thu đủ", "Paid")
        }
    }
}

/// Mục lọc loại giao dịch trong lịch sử tài chính
public enum TransactionTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Tất cả"
    case payments = "Phiếu thu (+)"
    case charges = "Phát sinh (-)"

    public var id: String { rawValue }
}

/// DTO thống nhất cho lịch sử giao dịch tài chính
public enum FinancialTransactionItem: Identifiable, Sendable {
    case payment(PaymentEntity)
    case charge(ChargeEntity)

    public var id: UUID {
        switch self {
        case .payment(let p): return p.id
        case .charge(let c): return c.id
        }
    }

    public var date: Date {
        switch self {
        case .payment(let p): return p.paidAt
        case .charge(let c): return c.createdAt
        }
    }
}

/// DTO chi tiết từng buổi học đã phát sinh học phí kèm ảnh minh chứng và số tiền đã phân bổ
public struct StudentChargeSessionDetailItem: Identifiable, Sendable {
    public let charge: ChargeEntity
    public let session: TeachingSessionEntity?
    public let sessionTitle: String
    public let sessionDate: Date
    public let className: String
    public let classColorHex: String
    public let unitPriceSnapshot: Int64
    public let allocatedPaidAmount: Int64
    public let remainingAmount: Int64
    public let attachments: [SessionAttachmentEntity]
    public let isInSelectedPeriod: Bool

    public var id: UUID { charge.id }

    public init(
        charge: ChargeEntity,
        session: TeachingSessionEntity?,
        sessionTitle: String,
        sessionDate: Date,
        className: String,
        classColorHex: String = "#F48FB1",
        unitPriceSnapshot: Int64,
        allocatedPaidAmount: Int64,
        remainingAmount: Int64,
        attachments: [SessionAttachmentEntity] = [],
        isInSelectedPeriod: Bool = true
    ) {
        self.charge = charge
        self.session = session
        self.sessionTitle = sessionTitle
        self.sessionDate = sessionDate
        self.className = className
        self.classColorHex = classColorHex
        self.unitPriceSnapshot = unitPriceSnapshot
        self.allocatedPaidAmount = allocatedPaidAmount
        self.remainingAmount = remainingAmount
        self.attachments = attachments
        self.isInSelectedPeriod = isInSelectedPeriod
    }
}

/// DTO hiển thị đầy đủ thông tin học phí của từng học sinh theo mục 5 (/duan):
/// - Avatar & Họ tên
/// - Số buổi đã dạy trong kỳ & Tổng số buổi
/// - Học phí phát sinh trong kỳ
/// - Số tiền đã thu trong kỳ (xác định theo ngày thu trên phiếu thu)
/// - Tổng còn nợ đến hiện tại (bao gồm nợ cũ nếu có)
/// - Trạng thái thanh toán & Ảnh minh chứng
public struct StudentFinanceItem: Identifiable, Sendable {
    public let student: StudentEntity
    /// Tổng học phí phát sinh lũy kế đến hiện tại
    public let accrued: Int64
    /// Tổng số tiền đã thu lũy kế đến hiện tại
    public let collected: Int64
    /// Tổng còn nợ đến hiện tại (bao gồm nợ cũ từ các kỳ trước nếu có)
    public let outstanding: Int64
    /// Số buổi đã hoàn thành phát sinh học phí trong kỳ đang chọn
    public let completedSessionsInPeriodCount: Int
    /// Tổng số buổi đã hoàn thành phát sinh học phí lũy kế
    public let totalCompletedSessionsCount: Int
    /// Học phí phát sinh trong kỳ đang chọn (tính theo ngày buổi học thuộc kỳ)
    public let accruedInPeriod: Int64
    /// Số tiền đã thu trong kỳ đang chọn (tính theo ngày thu tiền `paidAt` trên phiếu thu thuộc kỳ)
    public let collectedInPeriod: Int64
    /// Công nợ tồn đọng từ các buổi học thuộc các kỳ trước
    public let priorPeriodDebt: Int64
    /// Phần còn nợ của riêng các buổi học trong kỳ đang chọn
    public let outstandingInPeriod: Int64
    /// Trạng thái thanh toán tổng thể đến hiện tại
    public let paymentStatus: StudentTuitionPaymentStatus
    /// Danh sách tên lớp học sinh tham gia
    public let enrolledClassNames: [String]
    /// Danh sách ID lớp học sinh tham gia
    public let enrolledClassIds: [UUID]
    /// Số ảnh minh chứng của các buổi trong kỳ
    public let proofAttachmentsInPeriodCount: Int
    /// Tổng số ảnh minh chứng của học sinh
    public let totalProofAttachmentsCount: Int

    public var id: UUID { student.id }

    public init(
        student: StudentEntity,
        accrued: Int64,
        collected: Int64,
        outstanding: Int64,
        completedSessionsInPeriodCount: Int = 0,
        totalCompletedSessionsCount: Int = 0,
        accruedInPeriod: Int64? = nil,
        collectedInPeriod: Int64? = nil,
        priorPeriodDebt: Int64 = 0,
        outstandingInPeriod: Int64? = nil,
        paymentStatus: StudentTuitionPaymentStatus? = nil,
        enrolledClassNames: [String] = [],
        enrolledClassIds: [UUID] = [],
        proofAttachmentsInPeriodCount: Int = 0,
        totalProofAttachmentsCount: Int = 0
    ) {
        self.student = student
        self.accrued = accrued
        self.collected = collected
        self.outstanding = outstanding
        self.completedSessionsInPeriodCount = completedSessionsInPeriodCount
        self.totalCompletedSessionsCount = totalCompletedSessionsCount
        self.accruedInPeriod = accruedInPeriod ?? accrued
        self.collectedInPeriod = collectedInPeriod ?? collected
        self.priorPeriodDebt = priorPeriodDebt
        self.outstandingInPeriod = outstandingInPeriod ?? outstanding
        if let paymentStatus {
            self.paymentStatus = paymentStatus
        } else if accrued <= 0 {
            self.paymentStatus = .noCharges
        } else if outstanding <= 0 {
            self.paymentStatus = .paid
        } else if collected > 0 {
            self.paymentStatus = .partiallyPaid
        } else {
            self.paymentStatus = .unpaid
        }
        self.enrolledClassNames = enrolledClassNames
        self.enrolledClassIds = enrolledClassIds
        self.proofAttachmentsInPeriodCount = proofAttachmentsInPeriodCount
        self.totalProofAttachmentsCount = totalProofAttachmentsCount
    }
}

/// ViewModel điều phối màn hình Quản lý Tài chính & Học phí toàn ứng dụng (Presentation Layer)
@Observable
@MainActor
public final class FinanceViewModel {
    public var charges: [ChargeEntity] = [] {
        didSet {
            chargesById = Dictionary(uniqueKeysWithValues: charges.map { ($0.id, $0) })
            chargesByStudentId = Dictionary(grouping: charges, by: { $0.studentId })
        }
    }
    public var payments: [PaymentEntity] = [] {
        didSet {
            paymentsByStudentId = Dictionary(grouping: payments, by: { $0.studentId })
        }
    }
    public var students: [StudentEntity] = [] {
        didSet {
            studentsById = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        }
    }
    public var sessions: [TeachingSessionEntity] = [] {
        didSet {
            sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        }
    }
    public var classes: [ClassGroupEntity] = [] {
        didSet {
            classesById = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
        }
    }
    public var enrollmentsByStudentId: [UUID: [EnrollmentEntity]] = [:]
    public var attachmentsBySessionId: [UUID: [SessionAttachmentEntity]] = [:]
    public var allocationsByChargeId: [UUID: [PaymentAllocationEntity]] = [:]

    // Bảng chỉ mục O(1) giảm tải truy vấn lặp trên main thread khi render danh sách dài
    private var chargesById: [UUID: ChargeEntity] = [:]
    private var chargesByStudentId: [UUID: [ChargeEntity]] = [:]
    private var paymentsByStudentId: [UUID: [PaymentEntity]] = [:]
    private var studentsById: [UUID: StudentEntity] = [:]
    private var sessionsById: [UUID: TeachingSessionEntity] = [:]
    private var classesById: [UUID: ClassGroupEntity] = [:]

    /// Tổng kết toàn bộ công nợ lũy kế (Single-Source Invariant: Accrued - Collected = Outstanding)
    public var summary: FinanceSummaryEntity = .zero

    /// Bộ lọc kỳ/tháng (Mặc định mở vào "Tất cả" đầu tiên)
    public var selectedTimeFilter: FinanceTimeFilter = .allTime
    /// Tháng tùy chọn khi `selectedTimeFilter == .customMonth`
    public var selectedCustomMonth: Date = Date()
    /// Bộ lọc lớp học (`nil` = Tất cả các lớp)
    public var selectedClassFilterId: UUID? = nil
    /// Bộ lọc trạng thái thanh toán của học sinh
    public var selectedStatusFilter: StudentTuitionStatusFilter = .all
    /// Tương thích ngược với cờ lọc chỉ còn nợ
    public var showOnlyOutstanding: Bool = false {
        didSet {
            if showOnlyOutstanding && selectedStatusFilter == .all {
                selectedStatusFilter = .hasOutstanding
            } else if !showOnlyOutstanding && selectedStatusFilter == .hasOutstanding {
                selectedStatusFilter = .all
            }
        }
    }

    public var transactionTypeFilter: TransactionTypeFilter = .all
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    public let financeRepository: FinanceRepositoryProtocol
    public let studentRepository: StudentRepositoryProtocol
    public let scheduleRepository: ScheduleRepositoryProtocol?
    public let classRepository: ClassRepositoryProtocol?
    private let summaryUseCase = CalculateFinanceSummaryUseCase()
    private let recordPaymentUseCase = RecordPaymentUseCase()

    public init(
        financeRepository: FinanceRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        classRepository: ClassRepositoryProtocol? = nil
    ) {
        self.financeRepository = financeRepository
        self.studentRepository = studentRepository
        self.scheduleRepository = scheduleRepository
        self.classRepository = classRepository
    }

    // MARK: - Data Loading

    /// Tải toàn bộ dữ liệu tài chính, học sinh, lớp học, buổi dạy, phân bổ và ảnh minh chứng
    public func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            self.charges = try await financeRepository.fetchCharges()
            self.payments = try await financeRepository.fetchPayments()
            self.students = try await studentRepository.fetchStudents(includeArchived: true)

            if let classRepo = classRepository {
                self.classes = (try? await classRepo.fetchClasses(includeArchived: true)) ?? []
                var enrollmentMap: [UUID: [EnrollmentEntity]] = [:]
                for student in students {
                    let list = (try? await classRepo.fetchEnrollments(forStudentId: student.id, activeOnly: false)) ?? []
                    enrollmentMap[student.id] = list
                }
                self.enrollmentsByStudentId = enrollmentMap
            }

            if let schRepo = scheduleRepository {
                let pastDate = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
                let futureDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
                var fetchedSessions = (try? await schRepo.fetchSessions(from: pastDate, to: futureDate)) ?? []
                let existingIds = Set(fetchedSessions.map { $0.id })

                // Đảm bảo mọi buổi học đã phát sinh khoản thu (dù quá 1 năm trước) đều được tải đầy đủ
                let missingSessionIds = Set(charges.map { $0.sessionId }).subtracting(existingIds)
                for sid in missingSessionIds {
                    if let s = try? await schRepo.fetchSession(byId: sid) {
                        fetchedSessions.append(s)
                    }
                }
                self.sessions = fetchedSessions

                // Tải ảnh minh chứng cho các buổi học có phát sinh học phí hoặc đã hoàn thành
                var attachmentMap: [UUID: [SessionAttachmentEntity]] = [:]
                let relevantSessionIds = Set(charges.map { $0.sessionId }).union(
                    fetchedSessions.filter { $0.status == .completed }.map { $0.id }
                )
                for sid in relevantSessionIds {
                    let atts = (try? await schRepo.fetchAttachments(forSessionId: sid)) ?? []
                    attachmentMap[sid] = atts
                }
                self.attachmentsBySessionId = attachmentMap
            }

            // Tải các phân bổ thanh toán cho từng khoản phải thu
            var allocMap: [UUID: [PaymentAllocationEntity]] = [:]
            for charge in charges {
                let allocs = (try? await financeRepository.fetchAllocationsForCharge(chargeId: charge.id)) ?? []
                allocMap[charge.id] = allocs
            }
            self.allocationsByChargeId = allocMap

            updateSummary()
            isLoading = false
        } catch {
            errorMessage = "Không thể tải dữ liệu tài chính: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Cập nhật bảng tổng kết tài chính toàn thời gian (Accrued, Collected, Outstanding)
    private func updateSummary() {
        self.summary = summaryUseCase.execute(charges: charges, payments: payments)
    }

    // MARK: - Period / Month Helpers

    /// Nhãn hiển thị kỳ đang chọn
    public var periodDisplayLabel: String {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case .allTime:
            return L("Tất cả thời gian", "All Time")
        case .thisMonth:
            let m = cal.component(.month, from: Date())
            let y = cal.component(.year, from: Date())
            return L(String(format: "Tháng %02d/%d", m, y), String(format: "%02d/%d", m, y))
        case .lastMonth:
            let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let m = cal.component(.month, from: lastMonthDate)
            let y = cal.component(.year, from: lastMonthDate)
            return L(String(format: "Tháng %02d/%d", m, y), String(format: "%02d/%d", m, y))
        case .customMonth:
            let m = cal.component(.month, from: selectedCustomMonth)
            let y = cal.component(.year, from: selectedCustomMonth)
            return L(String(format: "Tháng %02d/%d", m, y), String(format: "%02d/%d", m, y))
        }
    }

    /// Giải thích rõ cách xác định kỳ cho các con số trên giao diện
    public var periodExplanationLabel: String {
        switch selectedTimeFilter {
        case .allTime:
            return "Số liệu lũy kế toàn bộ các buổi đã hoàn thành và phiếu thu."
        case .thisMonth, .lastMonth, .customMonth:
            return "Kỳ \(periodDisplayLabel): Phát sinh tính theo ngày buổi học; Đã thu tính theo ngày lập phiếu thu; Tổng còn nợ tính đến hiện tại (gồm cả nợ kỳ trước nếu có)."
        }
    }

    /// Lùi hoặc tiến tháng khi đang ở chế độ `.customMonth`
    public func shiftCustomMonth(by months: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: months, to: selectedCustomMonth) {
            selectedCustomMonth = newDate
        }
    }

    /// Kiểm tra một ngày bất kỳ có nằm trong kỳ đang lọc hay không
    public func isDateInSelectedPeriod(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case .allTime:
            return true
        case .thisMonth:
            return cal.isDate(date, equalTo: Date(), toGranularity: .month)
        case .lastMonth:
            guard let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) else { return false }
            return cal.isDate(date, equalTo: lastMonthDate, toGranularity: .month)
        case .customMonth:
            return cal.isDate(date, equalTo: selectedCustomMonth, toGranularity: .month)
        }
    }

    /// Ngày diễn ra buổi học tương ứng với một khoản thu (ưu tiên `session.startTime`, dự phòng `charge.createdAt`)
    public func effectiveSessionDate(for charge: ChargeEntity) -> Date {
        sessionsById[charge.sessionId]?.startTime ?? charge.createdAt
    }

    /// Số tiền đã phân bổ thanh toán cho một khoản phải thu cụ thể
    public func allocatedPaidAmount(for charge: ChargeEntity) -> Int64 {
        let allocs = allocationsByChargeId[charge.id] ?? []
        let sum = allocs.reduce(0 as Int64) { $0 + $1.allocatedAmount }
        if sum > 0 {
            return min(charge.amount, sum)
        }
        return charge.status == .paid ? charge.amount : 0
    }

    /// Số tiền còn nợ của một khoản phải thu cụ thể
    public func remainingAmount(for charge: ChargeEntity) -> Int64 {
        max(0, charge.amount - allocatedPaidAmount(for: charge))
    }

    // MARK: - Period KPI Totals (Tách bạch rõ Trong kỳ vs Tổng nợ đến hiện tại)

    /// Tổng học phí phát sinh trong kỳ đang lọc (và theo lớp nếu có lọc lớp)
    public var periodAccruedTuition: Int64 {
        filteredChargesInPeriod.reduce(0) { $0 + $1.amount }
    }

    /// Số buổi học hoàn thành phát sinh học phí trong kỳ đang lọc
    public var periodCompletedSessionsCount: Int {
        Set(filteredChargesInPeriod.map { $0.sessionId }).count
    }

    /// Tập ID học sinh thuộc lớp đang lọc (không bị ảnh hưởng bởi bộ lọc trạng thái thanh toán)
    private func studentIdsBelongingToClass(_ classId: UUID) -> Set<UUID> {
        Set(students.compactMap { student in
            let enrollments = enrollmentsByStudentId[student.id] ?? []
            if enrollments.contains(where: { $0.classId == classId }) {
                return student.id
            }
            let studentCharges = chargesByStudentId[student.id] ?? []
            let hasChargeInClass = studentCharges.contains { c in
                sessionsById[c.sessionId]?.classId == classId
            }
            return hasChargeInClass ? student.id : nil
        })
    }

    /// Tổng số tiền đã thu trong kỳ đang lọc (tính theo ngày thu `paidAt` thuộc kỳ)
    public var periodCollectedTuition: Int64 {
        let relevantStudentIds: Set<UUID>? = selectedClassFilterId.map { studentIdsBelongingToClass($0) }
        return payments.filter { payment in
            guard isDateInSelectedPeriod(payment.paidAt) else { return false }
            if let allowedIds = relevantStudentIds {
                return allowedIds.contains(payment.studentId)
            }
            return true
        }.reduce(0) { $0 + $1.amount }
    }

    /// Tổng còn nợ đến hiện tại (bao gồm nợ cũ từ các kỳ trước) của danh sách đang lọc
    public var totalOutstandingToDate: Int64 {
        guard let classId = selectedClassFilterId else {
            return summary.outstandingBalance
        }
        let allowedIds = studentIdsBelongingToClass(classId)
        return allowedIds.reduce(0 as Int64) { $0 + outstandingBalance(for: $1) }
    }

    private var filteredChargesInPeriod: [ChargeEntity] {
        charges.filter { charge in
            let sDate = effectiveSessionDate(for: charge)
            guard isDateInSelectedPeriod(sDate) else { return false }
            if let classId = selectedClassFilterId {
                guard let session = sessionsById[charge.sessionId] else { return false }
                return session.classId == classId
            }
            return true
        }
    }

    // MARK: - Student Finance List (Mục 5 /duan)

    /// Danh sách học sinh kèm đầy đủ số buổi trong kỳ, phát sinh trong kỳ, đã thu trong kỳ, tổng nợ hiện tại và trạng thái
    public var studentFinanceItems: [StudentFinanceItem] {
        buildStudentFinanceItems(searchQuery: "")
    }

    /// Lấy đầy đủ thông tin học phí của một học sinh bất kỳ (không bị ẩn bởi bộ lọc trạng thái)
    public func studentFinanceItem(for studentId: UUID) -> StudentFinanceItem? {
        guard let student = studentsById[studentId] else { return nil }
        let enrollments = enrollmentsByStudentId[student.id] ?? []
        let activeOrHistoricalClassIds = Set(enrollments.map { $0.classId })
        let studentChargesAll = chargesByStudentId[student.id] ?? []
        let chargeClassIds = Set(studentChargesAll.compactMap { c in
            sessionsById[c.sessionId]?.classId
        })
        let allStudentClassIds = Array(activeOrHistoricalClassIds.union(chargeClassIds))
        let classNames = allStudentClassIds.compactMap { classesById[$0]?.name }.sorted()

        let studentPaymentsAll = paymentsByStudentId[student.id] ?? []
        let fullSummary = summaryUseCase.execute(charges: studentChargesAll, payments: studentPaymentsAll)

        let chargesInPeriod = studentChargesAll.filter { isDateInSelectedPeriod(effectiveSessionDate(for: $0)) }
        let completedSessionsInPeriod = Set(chargesInPeriod.map { $0.sessionId }).count
        let totalCompletedSessions = Set(studentChargesAll.map { $0.sessionId }).count
        let accruedInPeriod = chargesInPeriod.reduce(0 as Int64) { $0 + $1.amount }

        let paymentsInPeriod = studentPaymentsAll.filter { isDateInSelectedPeriod($0.paidAt) }
        let collectedInPeriod = paymentsInPeriod.reduce(0 as Int64) { $0 + $1.amount }

        let outstandingInPeriod = chargesInPeriod.reduce(0 as Int64) { $0 + remainingAmount(for: $1) }
        let chargesBeforeOrOutsidePeriod = studentChargesAll.filter { !isDateInSelectedPeriod(effectiveSessionDate(for: $0)) }
        let priorPeriodDebt = chargesBeforeOrOutsidePeriod.reduce(0 as Int64) { $0 + remainingAmount(for: $1) }

        let periodProofCount = chargesInPeriod.reduce(0) { count, ch in
            count + (attachmentsBySessionId[ch.sessionId]?.count ?? 0)
        }
        let totalProofCount = studentChargesAll.reduce(0) { count, ch in
            count + (attachmentsBySessionId[ch.sessionId]?.count ?? 0)
        }

        let status: StudentTuitionPaymentStatus
        if fullSummary.accruedTuition <= 0 {
            status = .noCharges
        } else if fullSummary.outstandingBalance <= 0 {
            status = .paid
        } else if fullSummary.collectedTuition > 0 {
            status = .partiallyPaid
        } else {
            status = .unpaid
        }

        return StudentFinanceItem(
            student: student,
            accrued: fullSummary.accruedTuition,
            collected: fullSummary.collectedTuition,
            outstanding: fullSummary.outstandingBalance,
            completedSessionsInPeriodCount: completedSessionsInPeriod,
            totalCompletedSessionsCount: totalCompletedSessions,
            accruedInPeriod: accruedInPeriod,
            collectedInPeriod: collectedInPeriod,
            priorPeriodDebt: priorPeriodDebt,
            outstandingInPeriod: outstandingInPeriod,
            paymentStatus: status,
            enrolledClassNames: classNames,
            enrolledClassIds: allStudentClassIds,
            proofAttachmentsInPeriodCount: periodProofCount,
            totalProofAttachmentsCount: totalProofCount
        )
    }

    /// Danh sách học sinh đã áp dụng bộ lọc tìm kiếm, kỳ/tháng, lớp và trạng thái thanh toán
    public func buildStudentFinanceItems(searchQuery: String) -> [StudentFinanceItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return students.compactMap { student -> StudentFinanceItem? in
            // 1. Xác định các lớp học sinh tham gia (hoặc có khoản thu trong lớp đó)
            let enrollments = enrollmentsByStudentId[student.id] ?? []
            let activeOrHistoricalClassIds = Set(enrollments.map { $0.classId })
            let studentChargesAll = chargesByStudentId[student.id] ?? []
            let chargeClassIds = Set(studentChargesAll.compactMap { c in
                sessionsById[c.sessionId]?.classId
            })
            let allStudentClassIds = Array(activeOrHistoricalClassIds.union(chargeClassIds))
            let classNames = allStudentClassIds.compactMap { classesById[$0]?.name }.sorted()

            // 2. Nếu đang lọc theo Lớp học, kiểm tra học sinh có thuộc lớp đó không
            if let classFilterId = selectedClassFilterId {
                guard allStudentClassIds.contains(classFilterId) else { return nil }
            }

            // 3. Nếu đang tìm kiếm theo từ khóa
            if !trimmedQuery.isEmpty {
                let matchesName = student.fullName.lowercased().contains(trimmedQuery)
                let matchesPhone = student.phoneNumber.lowercased().contains(trimmedQuery) || student.parentPhone.lowercased().contains(trimmedQuery)
                let matchesClass = classNames.contains { $0.lowercased().contains(trimmedQuery) }
                guard matchesName || matchesPhone || matchesClass else { return nil }
            }

            // 4. Tính toán toàn bộ công nợ đến hiện tại (Single-Source Invariant)
            let studentCharges: [ChargeEntity]
            if let classFilterId = selectedClassFilterId {
                studentCharges = studentChargesAll.filter { c in
                    sessionsById[c.sessionId]?.classId == classFilterId
                }
            } else {
                studentCharges = studentChargesAll
            }

            let studentPaymentsAll = paymentsByStudentId[student.id] ?? []
            let fullSummary = summaryUseCase.execute(charges: studentChargesAll, payments: studentPaymentsAll)

            // 5. Tính số buổi đã dạy & học phí phát sinh TRONG KỲ đang chọn
            let chargesInPeriod = studentCharges.filter { isDateInSelectedPeriod(effectiveSessionDate(for: $0)) }
            let completedSessionsInPeriod = Set(chargesInPeriod.map { $0.sessionId }).count
            let totalCompletedSessions = Set(studentCharges.map { $0.sessionId }).count
            let accruedInPeriod = chargesInPeriod.reduce(0 as Int64) { $0 + $1.amount }

            // 6. Số tiền đã thu TRONG KỲ (xác định theo ngày thu tiền `paidAt` thuộc kỳ)
            let paymentsInPeriod = studentPaymentsAll.filter { isDateInSelectedPeriod($0.paidAt) }
            let collectedInPeriod = paymentsInPeriod.reduce(0 as Int64) { $0 + $1.amount }

            // 7. Phần còn nợ của kỳ hiện tại vs Nợ cũ từ các kỳ trước
            let outstandingInPeriod = chargesInPeriod.reduce(0 as Int64) { $0 + remainingAmount(for: $1) }
            let chargesBeforeOrOutsidePeriod = studentChargesAll.filter { !isDateInSelectedPeriod(effectiveSessionDate(for: $0)) }
            let priorPeriodDebt = chargesBeforeOrOutsidePeriod.reduce(0 as Int64) { $0 + remainingAmount(for: $1) }

            // 8. Đếm số ảnh minh chứng của các buổi học đã phát sinh học phí cho học sinh này
            let periodProofCount = chargesInPeriod.reduce(0) { count, ch in
                count + (attachmentsBySessionId[ch.sessionId]?.count ?? 0)
            }
            let totalProofCount = studentCharges.reduce(0) { count, ch in
                count + (attachmentsBySessionId[ch.sessionId]?.count ?? 0)
            }

            // 9. Xác định trạng thái thanh toán của học sinh
            let status: StudentTuitionPaymentStatus
            if fullSummary.accruedTuition <= 0 {
                status = .noCharges
            } else if fullSummary.outstandingBalance <= 0 {
                status = .paid
            } else if fullSummary.collectedTuition > 0 {
                status = .partiallyPaid
            } else {
                status = .unpaid
            }

            // Ẩn học sinh đã lưu trữ nếu không còn nợ và không có phát sinh trong kỳ
            if student.isArchived && fullSummary.outstandingBalance <= 0 && accruedInPeriod <= 0 {
                return nil
            }

            // 10. Lọc theo trạng thái thanh toán
            let effectiveFilter: StudentTuitionStatusFilter = showOnlyOutstanding ? .hasOutstanding : selectedStatusFilter
            switch effectiveFilter {
            case .all:
                break
            case .hasOutstanding:
                guard fullSummary.outstandingBalance > 0 else { return nil }
            case .partiallyPaid:
                guard status == .partiallyPaid else { return nil }
            case .unpaid:
                guard status == .unpaid else { return nil }
            case .paid:
                guard status == .paid else { return nil }
            }

            return StudentFinanceItem(
                student: student,
                accrued: fullSummary.accruedTuition,
                collected: fullSummary.collectedTuition,
                outstanding: fullSummary.outstandingBalance,
                completedSessionsInPeriodCount: completedSessionsInPeriod,
                totalCompletedSessionsCount: totalCompletedSessions,
                accruedInPeriod: accruedInPeriod,
                collectedInPeriod: collectedInPeriod,
                priorPeriodDebt: priorPeriodDebt,
                outstandingInPeriod: outstandingInPeriod,
                paymentStatus: status,
                enrolledClassNames: classNames,
                enrolledClassIds: allStudentClassIds,
                proofAttachmentsInPeriodCount: periodProofCount,
                totalProofAttachmentsCount: totalProofCount
            )
        }
        .sorted { item1, item2 in
            if item1.outstanding != item2.outstanding {
                return item1.outstanding > item2.outstanding
            }
            if item1.accruedInPeriod != item2.accruedInPeriod {
                return item1.accruedInPeriod > item2.accruedInPeriod
            }
            return item1.student.fullName.localizedStandardCompare(item2.student.fullName) == .orderedAscending
        }
    }

    // MARK: - Per-Student Session & Proof Detail Lookup

    /// Lấy danh sách chi tiết từng buổi học phát sinh học phí kèm ảnh minh chứng của một học sinh
    public func chargeSessionDetails(for studentId: UUID, onlySelectedPeriod: Bool = false) -> [StudentChargeSessionDetailItem] {
        let studentChargesAll = chargesByStudentId[studentId] ?? []
        let studentCharges = studentChargesAll.filter { charge in
            if let classFilterId = selectedClassFilterId {
                guard sessionsById[charge.sessionId]?.classId == classFilterId else { return false }
            }
            if onlySelectedPeriod {
                return isDateInSelectedPeriod(effectiveSessionDate(for: charge))
            }
            return true
        }

        return studentCharges.map { charge in
            let session = sessionsById[charge.sessionId]
            let sDate = session?.startTime ?? charge.createdAt
            let sTitle = session?.title ?? "Buổi học"
            let classGroup = session.flatMap { s in classesById[s.classId] }
            let cName = classGroup?.name ?? "Lớp học"
            let cColor = classGroup?.colorHex ?? "#F48FB1"
            let paid = allocatedPaidAmount(for: charge)
            let rem = max(0, charge.amount - paid)
            let proofs = attachmentsBySessionId[charge.sessionId] ?? []
            let inPeriod = isDateInSelectedPeriod(sDate)

            return StudentChargeSessionDetailItem(
                charge: charge,
                session: session,
                sessionTitle: sTitle,
                sessionDate: sDate,
                className: cName,
                classColorHex: cColor,
                unitPriceSnapshot: charge.unitPriceSnapshot,
                allocatedPaidAmount: paid,
                remainingAmount: rem,
                attachments: proofs,
                isInSelectedPeriod: inPeriod
            )
        }
        .sorted { $0.sessionDate > $1.sessionDate }
    }

    /// Lấy chi tiết buổi học & ảnh minh chứng cho một khoản phải thu đơn lẻ
    public func chargeSessionDetail(for charge: ChargeEntity) -> StudentChargeSessionDetailItem {
        let session = sessionsById[charge.sessionId]
        let sDate = session?.startTime ?? charge.createdAt
        let sTitle = session?.title ?? "Buổi học"
        let classGroup = session.flatMap { s in classesById[s.classId] }
        let cName = classGroup?.name ?? "Lớp học"
        let cColor = classGroup?.colorHex ?? "#F48FB1"
        let paid = allocatedPaidAmount(for: charge)
        let rem = max(0, charge.amount - paid)
        let proofs = attachmentsBySessionId[charge.sessionId] ?? []
        let inPeriod = isDateInSelectedPeriod(sDate)

        return StudentChargeSessionDetailItem(
            charge: charge,
            session: session,
            sessionTitle: sTitle,
            sessionDate: sDate,
            className: cName,
            classColorHex: cColor,
            unitPriceSnapshot: charge.unitPriceSnapshot,
            allocatedPaidAmount: paid,
            remainingAmount: rem,
            attachments: proofs,
            isInSelectedPeriod: inPeriod
        )
    }

    /// Danh sách phiếu thu của một học sinh (sắp xếp mới nhất lên đầu)
    public func paymentsForStudent(_ studentId: UUID) -> [PaymentEntity] {
        (paymentsByStudentId[studentId] ?? []).sorted { $0.paidAt > $1.paidAt }
    }

    /// Tính dư nợ hiện tại của một học sinh
    public func outstandingBalance(for studentId: UUID) -> Int64 {
        let studentCharges = chargesByStudentId[studentId] ?? []
        let studentPayments = paymentsByStudentId[studentId] ?? []
        let studentSummary = summaryUseCase.execute(charges: studentCharges, payments: studentPayments)
        return studentSummary.outstandingBalance
    }

    /// Danh sách giao dịch được lọc theo loại (Tất cả, Phiếu thu, Phát sinh)
    public var filteredTransactions: [FinancialTransactionItem] {
        var items: [FinancialTransactionItem] = []
        if transactionTypeFilter == .all || transactionTypeFilter == .payments {
            items.append(contentsOf: payments.map { .payment($0) })
        }
        if transactionTypeFilter == .all || transactionTypeFilter == .charges {
            items.append(contentsOf: charges.map { .charge($0) })
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Lấy họ tên học sinh theo ID
    public func studentName(for studentId: UUID) -> String {
        studentsById[studentId]?.fullName ?? "Học sinh"
    }

    /// Lấy thực thể học sinh theo ID
    public func student(for studentId: UUID) -> StudentEntity? {
        studentsById[studentId]
    }

    /// Lấy tiêu đề buổi học theo ID
    public func sessionTitle(for sessionId: UUID) -> String {
        sessionsById[sessionId]?.title ?? "Buổi học"
    }

    /// Lấy thực thể buổi học theo ID
    public func session(for sessionId: UUID) -> TeachingSessionEntity? {
        sessionsById[sessionId]
    }

    /// Lấy danh sách ảnh minh chứng của một buổi học
    public func attachments(for sessionId: UUID) -> [SessionAttachmentEntity] {
        attachmentsBySessionId[sessionId] ?? []
    }

    /// Lấy tên lớp theo ID
    public func className(for classId: UUID) -> String {
        classesById[classId]?.name ?? "Lớp học"
    }

    /// Lấy thông tin một khoản học phí theo ID
    public func charge(for chargeId: UUID) -> ChargeEntity? {
        chargesById[chargeId]
    }

    /// Danh sách các buổi học còn nợ của học sinh (sắp xếp từ cũ nhất đến mới nhất theo thứ tự FIFO)
    public func unpaidChargeSessionDetails(for studentId: UUID) -> [StudentChargeSessionDetailItem] {
        let studentCharges = chargesByStudentId[studentId] ?? []
        return studentCharges.compactMap { charge in
            let paid = allocatedPaidAmount(for: charge)
            let rem = max(0, charge.amount - paid)
            guard rem > 0 else { return nil }

            let session = sessionsById[charge.sessionId]
            let sDate = session?.startTime ?? charge.createdAt
            let sTitle = session?.title ?? "Buổi học"
            let classGroup = session.flatMap { s in classesById[s.classId] }
            let cName = classGroup?.name ?? "Lớp học"
            let cColor = classGroup?.colorHex ?? "#F48FB1"
            let proofs = attachmentsBySessionId[charge.sessionId] ?? []
            let inPeriod = isDateInSelectedPeriod(sDate)

            return StudentChargeSessionDetailItem(
                charge: charge,
                session: session,
                sessionTitle: sTitle,
                sessionDate: sDate,
                className: cName,
                classColorHex: cColor,
                unitPriceSnapshot: charge.unitPriceSnapshot,
                allocatedPaidAmount: paid,
                remainingAmount: rem,
                attachments: proofs,
                isInSelectedPeriod: inPeriod
            )
        }
        .sorted { $0.charge.createdAt < $1.charge.createdAt }
    }

    /// Tải danh sách các phân bổ cấn trừ công nợ của một phiếu thu (FIFO)
    public func fetchAllocations(for paymentId: UUID) async -> [PaymentAllocationEntity] {
        (try? await financeRepository.fetchAllocationsForPayment(paymentId: paymentId)) ?? []
    }

    /// Tính số dư nợ snapshot tại thời điểm ngay sau khi phát hành một phiếu thu
    public func snapshotRemainingBalanceAfterPayment(_ payment: PaymentEntity) -> Int64 {
        let studentChargesUpToPayment = charges.filter {
            $0.studentId == payment.studentId && $0.createdAt <= payment.paidAt.addingTimeInterval(60)
        }
        let studentPaymentsUpToPayment = payments.filter {
            $0.studentId == payment.studentId && ($0.paidAt < payment.paidAt || $0.id == payment.id)
        }
        if studentChargesUpToPayment.isEmpty {
            return outstandingBalance(for: payment.studentId)
        }
        let accruedUpTo = studentChargesUpToPayment.reduce(0 as Int64) { $0 + $1.amount }
        let collectedUpTo = studentPaymentsUpToPayment.reduce(0 as Int64) { $0 + $1.amount }
        return max(0, accruedUpTo - collectedUpTo)
    }

    /// Ghi nhận thu học phí từ học sinh với phân bổ FIFO (hỗ trợ chọn các buổi cụ thể cần thanh toán) và cập nhật trạng thái
    @discardableResult
    public func recordPayment(
        paymentId: UUID = UUID(),
        studentId: UUID,
        amount: Int64,
        paidAt: Date = Date(),
        paymentMethod: String = "Tiền mặt",
        note: String = "",
        selectedChargeIds: Set<UUID>? = nil
    ) async throws -> PaymentEntity {
        let studentCharges = try await financeRepository.fetchChargesForStudent(studentId: studentId)

        // Thu thập toàn bộ các phân bổ hiện có của các khoản phí này
        var existingAllocations: [PaymentAllocationEntity] = []
        for charge in studentCharges {
            let allocs = try await financeRepository.fetchAllocationsForCharge(chargeId: charge.id)
            existingAllocations.append(contentsOf: allocs)
        }

        // Thực thi Use Case phân bổ tiền thanh toán
        let result = try recordPaymentUseCase.execute(
            paymentId: paymentId,
            studentId: studentId,
            amount: amount,
            paidAt: paidAt,
            paymentMethod: paymentMethod,
            note: note,
            studentCharges: studentCharges,
            existingAllocations: existingAllocations,
            selectedChargeIds: selectedChargeIds
        )

        // Lưu bản ghi Payment
        try await financeRepository.savePayment(result.payment)

        // Lưu các bản ghi Allocation
        try await financeRepository.saveAllocations(result.allocations)

        // Lưu cập nhật trạng thái các Charges
        try await financeRepository.saveCharges(result.updatedCharges)

        // Tải lại dữ liệu cập nhật
        await loadData()

        return result.payment
    }

    /// Kết xuất file PDF Bản nháp Bản kê yêu cầu nộp học phí khổ A4 (chưa thu tiền, không làm thay đổi công nợ)
    public func generateDraftStatementPDF(
        draftCode: String,
        studentId: UUID,
        selectedItems: [StudentChargeSessionDetailItem],
        requestedAmount: Int64,
        paymentMethod: String,
        note: String
    ) -> Data? {
        let studentName = self.studentName(for: studentId)
        let currentTotalDebt = self.outstandingBalance(for: studentId)
        let remainingAfter = max(0, currentTotalDebt - requestedAmount)

        var remainingToSimulate = requestedAmount
        let simulatedItems: [(title: String, date: Date, amount: Int64)] = selectedItems.compactMap { sItem in
            guard remainingToSimulate > 0 else { return nil }
            let allocAmount = min(remainingToSimulate, sItem.remainingAmount)
            remainingToSimulate -= allocAmount
            return (title: "\(sItem.sessionTitle) (\(sItem.className))", date: sItem.sessionDate, amount: allocAmount)
        }

        let pdfData = ReceiptPDFData(
            receiptCode: draftCode,
            studentName: studentName,
            amount: requestedAmount,
            paidAt: Date(),
            paymentMethod: "\(paymentMethod) (BẢN NHÁP - YÊU CẦU NỘP HỌC PHÍ)",
            note: note.isEmpty ? "Bản kê tạm tính gửi phụ huynh đối chiếu (Chưa thu tiền)" : note,
            remainingBalance: remainingAfter,
            items: simulatedItems
        )

        return try? ReceiptPDFRenderer().renderReceiptPDF(data: pdfData)
    }

    /// Hủy một phiếu thu học phí:
    /// - Xóa bản ghi Payment & các PaymentAllocation tương ứng
    /// - Hoàn trả trạng thái các khoản học phí liên quan về unpaid hoặc partiallyPaid
    /// - Không ảnh hưởng đến dữ liệu buổi học, điểm danh hay ảnh minh chứng
    public func cancelPayment(paymentId: UUID) async throws {
        // 1. Tìm các phân bổ của khoản thanh toán này để xác định các charge bị ảnh hưởng
        let paymentAllocations = (try? await financeRepository.fetchAllocationsForPayment(paymentId: paymentId)) ?? []
        let affectedChargeIds = Set(paymentAllocations.map { $0.chargeId })

        // 2. Xóa khoản thanh toán (SwiftData deleteRule cascade sẽ xóa các allocations tương ứng)
        try await financeRepository.deletePayment(id: paymentId)

        // 3. Cập nhật lại trạng thái của từng khoản nợ bị ảnh hưởng
        for chargeId in affectedChargeIds {
            guard var charge = self.charge(for: chargeId) else { continue }
            let remainingAllocations = (try? await financeRepository.fetchAllocationsForCharge(chargeId: chargeId)) ?? []
            let totalPaid = remainingAllocations.reduce(0 as Int64) { $0 + $1.allocatedAmount }

            if totalPaid <= 0 {
                charge.status = .unpaid
            } else if totalPaid < charge.amount {
                charge.status = .partiallyPaid
            } else {
                charge.status = .paid
            }
            charge.updatedAt = Date()
            try? await financeRepository.saveCharge(charge)
        }

        // 4. Tải lại toàn bộ dữ liệu tài chính cập nhật
        await loadData()
    }

    /// Kết xuất file PDF Bản kê / Biên nhận học phí khổ A4 tiêu chuẩn
    public func generateReceiptPDF(payment: PaymentEntity, allocations: [PaymentAllocationEntity]) -> Data? {
        let studentName = self.studentName(for: payment.studentId)
        let receiptCode = "#REC-\(payment.id.uuidString.prefix(8).uppercased())"
        let remainingBalance = self.snapshotRemainingBalanceAfterPayment(payment)

        let items: [(title: String, date: Date, amount: Int64)] = allocations.map { alloc in
            let charge = self.charge(for: alloc.chargeId)
            let title = charge != nil ? self.sessionTitle(for: charge!.sessionId) : "Buổi dạy học phí"
            let date = charge != nil ? self.effectiveSessionDate(for: charge!) : alloc.allocatedAt
            return (title: title, date: date, amount: alloc.allocatedAmount)
        }

        let pdfData = ReceiptPDFData(
            receiptCode: receiptCode,
            studentName: studentName,
            amount: payment.amount,
            paidAt: payment.paidAt,
            paymentMethod: payment.paymentMethod,
            note: payment.note,
            remainingBalance: remainingBalance,
            items: items
        )

        return try? ReceiptPDFRenderer().renderReceiptPDF(data: pdfData)
    }
}
