import Foundation
import Observation

/// Thông tin yêu cầu xác nhận khi sửa nhầm trạng thái hoàn thành của học sinh sau khi buổi học đã chốt
public struct PostCompletionAttendanceAdjustment: Identifiable, Sendable {
    public var id: UUID { student.id }
    public let student: StudentEntity
    public let currentStatus: AttendanceStatus
    public let newStatus: AttendanceStatus
    public let existingCharge: ChargeEntity?
    public let unitPrice: Int64

    public init(
        student: StudentEntity,
        currentStatus: AttendanceStatus,
        newStatus: AttendanceStatus,
        existingCharge: ChargeEntity?,
        unitPrice: Int64
    ) {
        self.student = student
        self.currentStatus = currentStatus
        self.newStatus = newStatus
        self.existingCharge = existingCharge
        self.unitPrice = unitPrice
    }
}

/// ViewModel quản lý Chi tiết Buổi học & Quy trình Điểm danh / Hoàn thành (Presentation Layer)
@Observable
@MainActor
public final class SessionDetailViewModel {
    public var session: TeachingSessionEntity
    public var classGroup: ClassGroupEntity?
    public var students: [StudentEntity] = []
    public var attendances: [AttendanceEntity] = []
    public var attachments: [SessionAttachmentEntity] = []
    public var sessionCharges: [ChargeEntity] = []
    public var availableStudentsForEnrollment: [StudentEntity] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var validationAlertMessage: String? = nil
    public var isCompletedSuccess: Bool = false
    public var allClasses: [ClassGroupEntity] = []
    public var existingSessions: [TeachingSessionEntity] = []
    public var isShowingCompletionSummary: Bool = false
    public var isPhotoRequiredAlertShowing: Bool = false
    public var isCompleting: Bool = false
    public var pendingPostCompletionAdjustment: PostCompletionAttendanceAdjustment? = nil

    public let scheduleRepository: ScheduleRepositoryProtocol
    public let classRepository: ClassRepositoryProtocol
    public let studentRepository: StudentRepositoryProtocol
    public let financeRepository: FinanceRepositoryProtocol?
    public let notificationService: NotificationServiceProtocol
    private let completeSessionUseCase = CompleteTeachingSessionUseCase()
    private let initAttendanceUseCase = InitializeSessionAttendanceUseCase()
    private let generateChargesUseCase = GenerateSessionChargesUseCase()
    private let priceUseCase = GetEffectiveStudentPriceUseCase()

    public init(
        session: TeachingSessionEntity,
        scheduleRepository: ScheduleRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        studentRepository: StudentRepositoryProtocol,
        financeRepository: FinanceRepositoryProtocol? = nil,
        notificationService: NotificationServiceProtocol = LocalNotificationService.shared
    ) {
        self.session = session
        self.scheduleRepository = scheduleRepository
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.financeRepository = financeRepository
        self.notificationService = notificationService
    }

    public var isAllMarked: Bool {
        guard !students.isEmpty else { return false }
        let pending = attendances.filter { $0.status == .pending }
        return pending.isEmpty && attendances.count >= students.count
    }

    public var markedCount: Int {
        attendances.filter { $0.status != .pending }.count
    }

    public var pendingCount: Int {
        max(0, students.count - markedCount)
    }

    public var presentCount: Int {
        attendances.filter { $0.status == .present }.count
    }

    public var absentCount: Int {
        attendances.filter { $0.status == .absent || $0.status == .excused }.count
    }

    public var excusedCount: Int {
        attendances.filter { $0.status == .excused }.count
    }

    public var completionProgress: Double {
        guard !students.isEmpty else { return 0.0 }
        return min(1.0, max(0.0, Double(markedCount) / Double(students.count)))
    }

    /// Tính tổng học phí phát sinh của buổi học (chỉ tính cho học sinh Có mặt)
    public var totalAccruedTuition: Int64 {
        guard let classGroup = classGroup else { return 0 }
        let studentMap = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        var total: Int64 = 0
        for att in attendances where att.status == .present {
            if let student = studentMap[att.studentId] {
                total += priceUseCase.execute(student: student, classGroup: classGroup)
            }
        }
        return total
    }

    /// Lấy đơn giá hiệu dụng riêng cho từng học sinh
    public func effectivePrice(for student: StudentEntity) -> Int64 {
        guard let classGroup = classGroup else { return student.defaultPricePerSession ?? 0 }
        return priceUseCase.execute(student: student, classGroup: classGroup)
    }

    /// Kiểm tra học sinh có đang áp dụng đơn giá riêng hay không
    public func isCustomPrice(for student: StudentEntity) -> Bool {
        if let custom = student.defaultPricePerSession, custom > 0 {
            return true
        }
        return false
    }

    /// Lấy khoản thu học phí (nếu buổi học đã hoàn thành) của học sinh
    public func charge(for studentId: UUID) -> ChargeEntity? {
        sessionCharges.first { $0.studentId == studentId }
    }

    /// Ghi danh nhanh một học sinh vào lớp và khởi tạo điểm danh cho buổi học hiện tại
    public func enrollStudentToSessionClass(_ student: StudentEntity) async {
        do {
            try await classRepository.enrollStudent(studentId: student.id, classId: session.classId)
            let newAtt = AttendanceEntity(
                sessionId: session.id,
                studentId: student.id,
                status: .pending,
                note: ""
            )
            try await scheduleRepository.saveAttendance(newAtt)
            await loadData()
        } catch {
            self.errorMessage = "Không thể thêm học sinh vào lớp: \(error.localizedDescription)"
        }
    }

    /// Đánh dấu nhanh tất cả học sinh chưa điểm danh thành Có mặt
    public func markAllPresent() async {
        guard session.status != .cancelled else { return }
        for index in attendances.indices {
            attendances[index].status = .present
            attendances[index].markedAt = Date()
        }
        do {
            try await scheduleRepository.saveAttendances(attendances)
        } catch {
            self.errorMessage = "Không thể lưu điểm danh hàng loạt: \(error.localizedDescription)"
        }
    }

    /// Thêm ảnh minh chứng cho buổi dạy
    public func addPhotoAttachment(filePath: String, caption: String = "") async throws {
        let attachment = SessionAttachmentEntity(
            sessionId: session.id,
            filePath: filePath,
            caption: caption
        )
        try await scheduleRepository.addAttachment(attachment)
        self.attachments = try await scheduleRepository.fetchAttachments(forSessionId: session.id)
    }

    /// Thẩm định đầy đủ trước khi mở màn hình tổng kết hoàn thành:
    /// 1. Tất cả học sinh phải được điểm danh (không còn ai ở trạng thái pending).
    /// 2. Nếu có học sinh đi học (presentCount > 0), bắt buộc phải có ít nhất 1 ảnh minh chứng.
    ///    Nếu tất cả học sinh nghỉ (presentCount == 0), ghi nhận tổng tiền = 0 và không ép chụp ảnh.
    public func validateBeforeCompletion() -> Bool {
        guard isAllMarked else {
            let pending = attendances.filter { $0.status == .pending }.count
            self.validationAlertMessage = "Còn \(pending) học sinh chưa được đánh dấu điểm danh. Vui lòng điểm danh đầy đủ trước khi hoàn thành."
            return false
        }

        if presentCount > 0 && attachments.isEmpty {
            self.isPhotoRequiredAlertShowing = true
            return false
        }

        return true
    }

    /// Bắt đầu quy trình hoàn thành: kiểm tra và mở Sheet Tổng kết
    public func requestCompleteSession() {
        if validateBeforeCompletion() {
            self.isShowingCompletionSummary = true
        }
    }

    public func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            // Tải thông tin lớp học
            self.classGroup = try await classRepository.fetchClass(byId: session.classId)

            // Tải danh sách điểm danh hiện có của buổi học
            let existingAttendances = try await scheduleRepository.fetchAttendances(forSessionId: session.id)

            // Tải danh sách thành viên active của lớp
            let enrollments = try await classRepository.fetchEnrollments(forClassId: session.classId, activeOnly: true)
            var loadedStudents: [StudentEntity] = []
            for e in enrollments {
                if let student = try await studentRepository.fetchStudent(byId: e.studentId) {
                    loadedStudents.append(student)
                }
            }

            // Bổ sung cả những học sinh đã có trong bản ghi điểm danh của buổi học (trường hợp snapshot hoặc lịch sử)
            let enrolledIds = Set(loadedStudents.map { $0.id })
            for att in existingAttendances where !enrolledIds.contains(att.studentId) {
                if let student = try await studentRepository.fetchStudent(byId: att.studentId) {
                    loadedStudents.append(student)
                }
            }
            self.students = loadedStudents

            // Khởi tạo điểm danh cho các thành viên chưa có bản ghi
            let studentIds = loadedStudents.map { $0.id }
            let fullAttendances = initAttendanceUseCase.execute(
                sessionId: session.id,
                activeStudentIds: studentIds,
                existingAttendances: existingAttendances
            )
            self.attendances = fullAttendances

            // Tải danh sách học sinh chưa ghi danh vào lớp này để hỗ trợ thêm nhanh
            let allActiveStudents = (try? await studentRepository.fetchStudents(includeArchived: false)) ?? []
            let currentIds = Set(loadedStudents.map { $0.id })
            self.availableStudentsForEnrollment = allActiveStudents.filter { !currentIds.contains($0.id) }

            // Tải các khoản thu học phí của buổi học (nếu có)
            if let finRepo = financeRepository {
                self.sessionCharges = (try? await finRepo.fetchChargesForSession(sessionId: session.id)) ?? []
            }

            // Tải tệp đính kèm
            self.attachments = try await scheduleRepository.fetchAttachments(forSessionId: session.id)

            // Tải danh sách tất cả lớp học & các buổi lân cận để hỗ trợ đổi lớp / kiểm tra trùng khi sửa
            self.allClasses = (try? await classRepository.fetchClasses(includeArchived: false)) ?? []
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -14, to: session.startTime) ?? session.startTime
            let end = calendar.date(byAdding: .day, value: 14, to: session.startTime) ?? session.startTime
            self.existingSessions = (try? await scheduleRepository.fetchSessions(from: start, to: end)) ?? []
        } catch {
            self.errorMessage = "Không thể tải dữ liệu buổi học: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func updateSession(_ updated: TeachingSessionEntity) async throws {
        try await scheduleRepository.saveSession(updated)
        if updated.status == .scheduled {
            await notificationService.scheduleSessionReminder(for: updated)
        } else {
            await notificationService.cancelSessionReminder(sessionId: updated.id)
        }
        self.session = updated
        await loadData()
    }

    /// Tách buổi học hiện tại ra khỏi chuỗi (ngoại lệ đơn lẻ) và cập nhật
    public func updateSingleSessionDetached(_ updated: TeachingSessionEntity) async throws {
        var detached = updated
        detached.setSeriesId(nil)
        detached.updatedAt = Date()
        try await scheduleRepository.saveSession(detached)
        if detached.status == .scheduled {
            await notificationService.scheduleSessionReminder(for: detached)
        }
        self.session = detached
        await loadData()
    }

    /// Cập nhật buổi học hiện tại cùng tất cả các buổi học tương lai trong cùng chuỗi lặp cố định
    public func updateSeriesFutureSessions(from updated: TeachingSessionEntity) async throws {
        let originalStart = session.startTime
        guard let seriesId = updated.seriesId else {
            try await updateSession(updated)
            return
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: updated.startTime)
        let newHour = startComponents.hour ?? 17
        let newMinute = startComponents.minute ?? 30
        let durationMinutes = max(15, updated.durationMinutes)

        let classSessions = try await scheduleRepository.fetchSessionsForClass(classId: updated.classId)
        let futureSeriesSessions = classSessions.filter { s in
            s.seriesId == seriesId &&
            s.startTime >= originalStart &&
            s.status == .scheduled
        }

        for var s in futureSeriesSessions {
            if s.id == updated.id {
                try await scheduleRepository.saveSession(updated)
                await notificationService.scheduleSessionReminder(for: updated)
            } else {
                var comp = calendar.dateComponents([.year, .month, .day], from: s.startTime)
                comp.hour = newHour
                comp.minute = newMinute
                comp.second = 0
                if let newStart = calendar.date(from: comp) {
                    s.startTime = newStart
                    s.endTime = newStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
                }
                s.title = updated.title
                s.setSeriesId(seriesId)
                s.lessonNotes = "\(TeachingSessionEntity.seriesPrefix)\(seriesId.uuidString)\(TeachingSessionEntity.seriesSuffix)\n\(updated.userDisplayNotes)".trimmingCharacters(in: .whitespacesAndNewlines)
                s.homeworkAssigned = updated.homeworkAssigned
                s.updatedAt = Date()
                try await scheduleRepository.saveSession(s)
                await notificationService.scheduleSessionReminder(for: s)
            }
        }
        self.session = updated
        await loadData()
    }

    public func markAttendance(studentId: UUID, status: AttendanceStatus, note: String = "") async {
        guard session.status != .cancelled else { return }

        // Nếu buổi học đã hoàn thành (.completed): bắt buộc qua luồng kiểm tra tài chính & xác nhận điều chỉnh
        if session.status == .completed {
            await requestPostCompletionStatusAdjustment(studentId: studentId, newStatus: status)
            return
        }

        if let idx = attendances.firstIndex(where: { $0.studentId == studentId }) {
            attendances[idx].status = status
            if !note.isEmpty {
                attendances[idx].note = note
            }
            attendances[idx].markedAt = Date()

            do {
                try await scheduleRepository.saveAttendance(attendances[idx])
            } catch {
                self.errorMessage = "Không thể lưu điểm danh: \(error.localizedDescription)"
            }
        }
    }

    /// Xử lý khi giáo viên bấm sửa nhầm trạng thái hoàn thành của một học sinh sau khi buổi học đã hoàn thành:
    /// - Chặn nếu khoản học phí của học sinh trong buổi đó đã thu tiền (.paid / .partiallyPaid).
    /// - Nếu chưa thu tiền (.unpaid) hoặc đang ở trạng thái Nghỉ: hiện hộp thoại xác nhận điều chỉnh rõ ràng.
    public func requestPostCompletionStatusAdjustment(studentId: UUID, newStatus: AttendanceStatus) async {
        guard session.status == .completed else { return }
        guard let student = students.first(where: { $0.id == studentId }),
              let att = attendances.first(where: { $0.studentId == studentId }) else { return }

        let currentStatus = att.status
        guard currentStatus != newStatus else { return }

        var existingCharge = charge(for: studentId)
        if existingCharge == nil, let finRepo = financeRepository {
            existingCharge = try? await finRepo.fetchCharge(sessionId: session.id, studentId: studentId)
        }

        // Nếu đổi từ Đã hoàn thành (.present) sang Nghỉ (.absent / .excused) mà khoản thu đã thanh toán -> Chặn và giải thích
        if let existingCharge, newStatus != .present {
            var hasAllocation = (existingCharge.status != .unpaid)
            if let finRepo = financeRepository {
                let allocs = (try? await finRepo.fetchAllocationsForCharge(chargeId: existingCharge.id)) ?? []
                if !allocs.isEmpty {
                    hasAllocation = true
                }
            }
            if hasAllocation {
                self.validationAlertMessage = "Khoản học phí của học sinh \(student.fullName) trong buổi học này đã được thu tiền (\(existingCharge.status.displayName)). Hệ thống chặn đổi sang Nghỉ để bảo toàn lịch sử thanh toán và công nợ."
                return
            }
        }

        self.pendingPostCompletionAdjustment = PostCompletionAttendanceAdjustment(
            student: student,
            currentStatus: currentStatus,
            newStatus: newStatus,
            existingCharge: existingCharge,
            unitPrice: effectivePrice(for: student)
        )
    }

    /// Thực thi điều chỉnh trạng thái hoàn thành của học sinh sau khi giáo viên đã xác nhận trên hộp thoại
    public func confirmPostCompletionAdjustment() async {
        guard let adjustment = pendingPostCompletionAdjustment else { return }
        defer { pendingPostCompletionAdjustment = nil }

        // Nếu đổi từ Nghỉ sang Đã hoàn thành (.present): kiểm tra ảnh minh chứng của buổi học
        if adjustment.newStatus == .present && attachments.isEmpty {
            self.isPhotoRequiredAlertShowing = true
            return
        }

        do {
            // 1. Điều chỉnh khoản phải thu học phí an toàn trước
            if let finRepo = financeRepository {
                if adjustment.newStatus == .present {
                    // Phát sinh khoản phải thu theo đơn giá snapshot (idempotent theo sessionId + studentId)
                    let existing = try await finRepo.fetchCharge(sessionId: session.id, studentId: adjustment.student.id)
                    if existing == nil && adjustment.unitPrice > 0 {
                        let newCharge = ChargeEntity(
                            sessionId: session.id,
                            studentId: adjustment.student.id,
                            amount: adjustment.unitPrice,
                            unitPriceSnapshot: adjustment.unitPrice,
                            status: .unpaid,
                            createdAt: Date()
                        )
                        try await finRepo.saveCharge(newCharge)
                    }
                } else {
                    // Đổi sang Nghỉ (.absent / .excused): hủy khoản phải thu chưa thanh toán (nếu có)
                    if let existing = try await finRepo.fetchCharge(sessionId: session.id, studentId: adjustment.student.id) {
                        try await finRepo.deleteUnpaidCharge(id: existing.id)
                    }
                }
            }

            // 2. Cập nhật bản ghi điểm danh của học sinh
            if let idx = attendances.firstIndex(where: { $0.studentId == adjustment.student.id }) {
                attendances[idx].status = adjustment.newStatus
                attendances[idx].markedAt = Date()
                try await scheduleRepository.saveAttendance(attendances[idx])
            }

            await loadData()
        } catch {
            self.errorMessage = "Không thể điều chỉnh trạng thái hoàn thành: \(error.localizedDescription)"
        }
    }

    public func completeSession() async {
        await confirmAndFinalizeCompletion()
    }

    /// Xác nhận hoàn thành buổi học: cập nhật trạng thái .completed và tự động sinh học phí idempotent
    /// Đảm bảo nguyên tử: nếu lưu khoản phải thu thất bại thì không chuyển trạng thái buổi học sang .completed
    public func confirmAndFinalizeCompletion() async {
        guard !isCompleting, session.status == .scheduled else { return }
        isCompleting = true
        errorMessage = nil

        do {
            let expectedStudentIds = students.map { $0.id }
            let updatedSession = try completeSessionUseCase.execute(
                session: session,
                attendances: attendances,
                expectedStudentIds: expectedStudentIds
            )

            // 1. Lưu điểm danh từng học sinh
            try await scheduleRepository.saveAttendances(attendances)

            // 2. Tự động sinh và lưu học phí idempotent TRƯỚC khi chốt trạng thái .completed của buổi học
            // (Đảm bảo nếu lưu học phí lỗi thì buổi học không bị chuyển sang .completed gây mâu thuẫn)
            if let finRepo = financeRepository, let classGroup = self.classGroup {
                let existingCharges = try await finRepo.fetchChargesForSession(sessionId: session.id)
                let newCharges = generateChargesUseCase.execute(
                    session: updatedSession,
                    attendances: attendances,
                    students: students,
                    classGroup: classGroup,
                    existingCharges: existingCharges
                )
                if !newCharges.isEmpty {
                    try await finRepo.saveCharges(newCharges)
                }
            }

            // 3. Lưu trạng thái buổi học .completed và hủy lời nhắc
            try await scheduleRepository.saveSession(updatedSession)
            await notificationService.cancelSessionReminder(sessionId: session.id)

            self.session = updatedSession
            self.isShowingCompletionSummary = false
            self.isCompletedSuccess = true
            await loadData()
        } catch let error as CompleteSessionError {
            self.validationAlertMessage = error.errorDescription
        } catch {
            self.errorMessage = "Lỗi khi hoàn thành buổi học: \(error.localizedDescription)"
        }
        isCompleting = false
    }

    public func updateNotes(lessonNotes: String, homeworkAssigned: String) async {
        let existingSeriesId = session.seriesId
        let trimmedNotes = lessonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.lessonNotes = trimmedNotes
        if let existingSeriesId {
            session.setSeriesId(existingSeriesId)
        }
        session.homeworkAssigned = homeworkAssigned.trimmingCharacters(in: .whitespacesAndNewlines)
        session.updatedAt = Date()
        do {
            try await scheduleRepository.saveSession(session)
        } catch {
            self.errorMessage = "Không thể lưu ghi chú: \(error.localizedDescription)"
        }
    }

    public func attendance(for studentId: UUID) -> AttendanceEntity? {
        attendances.first { $0.studentId == studentId }
    }
}
