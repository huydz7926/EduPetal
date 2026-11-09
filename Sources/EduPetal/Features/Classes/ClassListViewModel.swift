import Foundation
import Observation

/// Thông tin cảnh báo khi xóa lớp đang còn học phí chưa thanh toán
public struct ClassUnpaidDeletionPrompt: Identifiable, Sendable {
    public var id: UUID { classGroup.id }
    public let classGroup: ClassGroupEntity
    public let unpaidAmount: Int64
    public let unpaidChargeCount: Int

    public init(classGroup: ClassGroupEntity, unpaidAmount: Int64, unpaidChargeCount: Int) {
        self.classGroup = classGroup
        self.unpaidAmount = unpaidAmount
        self.unpaidChargeCount = unpaidChargeCount
    }
}

/// ViewModel quản lý Danh sách Lớp học (Presentation Layer)
@Observable
@MainActor
public final class ClassListViewModel {
    public var classes: [ClassGroupEntity] = []
    public var studentCounts: [UUID: Int] = [:]
    public var nextUpcomingSessions: [UUID: TeachingSessionEntity] = [:]
    public var searchQuery: String = ""
    public var showArchived: Bool = false
    public var isLoading: Bool = false
    public private(set) var isSavingClass: Bool = false
    public var errorMessage: String? = nil

    /// Lớp đã lưu trữ đang chờ xác nhận xóa (khi không nợ học phí)
    public var classPendingSimpleDelete: ClassGroupEntity? = nil
    /// Lớp đã lưu trữ đang còn nợ học phí — yêu cầu xác nhận đã thanh toán mới cho xóa
    public var classPendingUnpaidDelete: ClassUnpaidDeletionPrompt? = nil

    private let classRepository: ClassRepositoryProtocol
    public var scheduleRepository: ScheduleRepositoryProtocol?
    public var financeRepository: FinanceRepositoryProtocol?

    public init(
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil
    ) {
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
    }

    public var filteredClasses: [ClassGroupEntity] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return classes.filter { classGroup in
            let matchesArchive = showArchived ? classGroup.isArchived : !classGroup.isArchived
            guard matchesArchive else { return false }

            if trimmed.isEmpty { return true }
            return classGroup.name.lowercased().contains(trimmed) ||
                   classGroup.subject.lowercased().contains(trimmed)
        }
    }

    public func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedClasses = try await classRepository.fetchClasses(includeArchived: true)
            self.classes = loadedClasses

            // Đếm số lượng học sinh đang tham gia và tìm buổi dạy tiếp theo của từng lớp
            let now = Date()
            var counts: [UUID: Int] = [:]
            var nextSessions: [UUID: TeachingSessionEntity] = [:]
            for c in loadedClasses {
                let enrollments = try await classRepository.fetchEnrollments(forClassId: c.id, activeOnly: true)
                counts[c.id] = enrollments.count

                if let schRepo = scheduleRepository {
                    let classSessions = try await schRepo.fetchSessionsForClass(classId: c.id)
                    if let earliestUpcoming = classSessions
                        .filter({ $0.status == .scheduled && $0.endTime >= now })
                        .min(by: { $0.startTime < $1.startTime }) {
                        nextSessions[c.id] = earliestUpcoming
                    }
                }
            }
            self.studentCounts = counts
            self.nextUpcomingSessions = nextSessions
        } catch {
            self.errorMessage = "Không thể tải danh sách lớp học: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Lưu lớp học mới hoặc cập nhật lớp học hiện có:
    /// - Bắt buộc: Tên lớp không rỗng và Đơn giá mỗi buổi > 0.
    /// - Chống lưu trùng khi người dùng bấm Lưu nhiều lần liên tiếp.
    @discardableResult
    public func saveClass(_ classGroup: ClassGroupEntity) async -> Bool {
        guard !isSavingClass else { return false }

        let trimmedName = classGroup.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            self.errorMessage = "Vui lòng nhập tên lớp học."
            return false
        }
        guard classGroup.defaultPricePerSession > 0 else {
            self.errorMessage = "Vui lòng nhập đơn giá hợp lệ lớn hơn 0 đ."
            return false
        }

        isSavingClass = true
        defer { isSavingClass = false }
        errorMessage = nil

        var sanitized = classGroup
        sanitized.name = trimmedName
        sanitized.subject = classGroup.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.notes = classGroup.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.updatedAt = Date()

        do {
            try await classRepository.saveClass(sanitized)
            await loadData()
            return true
        } catch {
            self.errorMessage = "Không thể lưu thông tin lớp học: \(error.localizedDescription)"
            return false
        }
    }

    public func archiveClass(id: UUID) async {
        do {
            try await classRepository.archiveClass(id: id)
            await loadData()
        } catch {
            self.errorMessage = "Không thể lưu trữ lớp học: \(error.localizedDescription)"
        }
    }

    public func restoreClass(id: UUID) async {
        do {
            try await classRepository.restoreClass(id: id)
            await loadData()
        } catch {
            self.errorMessage = "Không thể khôi phục lớp học: \(error.localizedDescription)"
        }
    }

    /// Kiểm tra các khoản học phí chưa thanh toán thuộc về lớp học
    public func fetchUnpaidClassCharges(forClassId classId: UUID) async throws -> [(charge: ChargeEntity, remaining: Int64)] {
        guard let finRepo = financeRepository else { return [] }

        var classSessionIds = Set<UUID>()
        if let schRepo = scheduleRepository {
            let sessions = try await schRepo.fetchSessionsForClass(classId: classId)
            classSessionIds = Set(sessions.map { $0.id })
        }

        let enrollments = try await classRepository.fetchEnrollments(forClassId: classId, activeOnly: false)
        let enrolledStudentIds = Set(enrollments.map { $0.studentId })

        let allCharges = try await finRepo.fetchCharges()
        var unpaidItems: [(charge: ChargeEntity, remaining: Int64)] = []

        for charge in allCharges where charge.status != .paid {
            var belongsToClass = false
            if classSessionIds.contains(charge.sessionId) {
                belongsToClass = true
            } else if enrolledStudentIds.contains(charge.studentId) {
                if let schRepo = scheduleRepository {
                    if let session = try await schRepo.fetchSession(byId: charge.sessionId) {
                        belongsToClass = (session.classId == classId)
                    } else {
                        belongsToClass = true
                    }
                } else {
                    belongsToClass = true
                }
            }

            if belongsToClass {
                let allocs = try await finRepo.fetchAllocationsForCharge(chargeId: charge.id)
                let paid = allocs.reduce(Int64(0)) { $0 + $1.allocatedAmount }
                let remaining = max(0, charge.amount - paid)
                if remaining > 0 {
                    unpaidItems.append((charge, remaining))
                }
            }
        }

        return unpaidItems
    }

    /// Bấm xóa lớp ở phần lưu trữ:
    /// - Nếu không có học phí nợ -> hiện hộp thoại "Chắc chắn xóa không?"
    /// - Nếu có học phí chưa thanh toán -> nhắc chưa thanh toán và yêu cầu xác nhận đã thanh toán mới cho xóa
    public func requestDeleteArchivedClass(_ classGroup: ClassGroupEntity) async {
        errorMessage = nil
        do {
            let unpaidItems = try await fetchUnpaidClassCharges(forClassId: classGroup.id)
            let totalUnpaid = unpaidItems.reduce(Int64(0)) { $0 + $1.remaining }

            if totalUnpaid > 0 {
                classPendingSimpleDelete = nil
                classPendingUnpaidDelete = ClassUnpaidDeletionPrompt(
                    classGroup: classGroup,
                    unpaidAmount: totalUnpaid,
                    unpaidChargeCount: unpaidItems.count
                )
            } else {
                classPendingUnpaidDelete = nil
                classPendingSimpleDelete = classGroup
            }
        } catch {
            self.errorMessage = "Không thể kiểm tra học phí của lớp: \(error.localizedDescription)"
        }
    }

    /// Thực hiện xóa lớp sau khi người dùng xác nhận
    public func confirmDeleteClass(id: UUID, confirmPaidIfUnpaid: Bool = false) async {
        errorMessage = nil
        do {
            let unpaidItems = try await fetchUnpaidClassCharges(forClassId: id)
            let totalUnpaid = unpaidItems.reduce(Int64(0)) { $0 + $1.remaining }

            if totalUnpaid > 0 {
                guard confirmPaidIfUnpaid else {
                    self.errorMessage = "Lớp học còn \(totalUnpaid.formattedVND) học phí chưa thanh toán. Vui lòng xác nhận đã thanh toán trước khi xóa."
                    return
                }

                // Ghi nhận đã thanh toán đủ cho các khoản học phí còn nợ của lớp này trước khi xóa
                if let finRepo = financeRepository {
                    let groupedByStudent = Dictionary(grouping: unpaidItems, by: { $0.charge.studentId })
                    for (studentId, items) in groupedByStudent {
                        let studentTotal = items.reduce(Int64(0)) { $0 + $1.remaining }
                        guard studentTotal > 0 else { continue }

                        let payment = PaymentEntity(
                            studentId: studentId,
                            amount: studentTotal,
                            paidAt: Date(),
                            paymentMethod: "Tiền mặt",
                            note: "Xác nhận đã thanh toán khi xóa lớp lưu trữ"
                        )
                        try await finRepo.savePayment(payment)

                        var allocations: [PaymentAllocationEntity] = []
                        var updatedCharges: [ChargeEntity] = []
                        for item in items {
                            allocations.append(
                                PaymentAllocationEntity(
                                    paymentId: payment.id,
                                    chargeId: item.charge.id,
                                    allocatedAmount: item.remaining
                                )
                            )
                            var updated = item.charge
                            updated.status = .paid
                            updatedCharges.append(updated)
                        }
                        try await finRepo.saveAllocations(allocations)
                        try await finRepo.saveCharges(updatedCharges)
                    }
                }
            }

            if let schRepo = scheduleRepository {
                let sessions = try await schRepo.fetchSessionsForClass(classId: id)
                for s in sessions {
                    await LocalNotificationService.shared.cancelSessionReminder(sessionId: s.id)
                    // Không cascade xóa các buổi dạy đã hoàn thành (.completed) để bảo toàn lịch sử điểm danh và đối soát tài chính
                    if s.status != .completed {
                        try await schRepo.deleteSession(id: s.id)
                    }
                }
            }

            try await classRepository.deleteClass(id: id)
            classPendingSimpleDelete = nil
            classPendingUnpaidDelete = nil
            await loadData()
        } catch {
            self.errorMessage = "Không thể xóa lớp học: \(error.localizedDescription)"
        }
    }

    public func deleteClass(id: UUID) async {
        await confirmDeleteClass(id: id, confirmPaidIfUnpaid: false)
    }
}
