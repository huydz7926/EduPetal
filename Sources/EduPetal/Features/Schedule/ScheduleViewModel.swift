import Foundation
import Observation

/// ViewModel quản lý Lịch dạy (Module 4 — Schedule)
@Observable
@MainActor
public final class ScheduleViewModel {
    public var selectedDate: Date = Date()
    public var sessions: [TeachingSessionEntity] = []
    public var classes: [ClassGroupEntity] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    public let scheduleRepository: ScheduleRepositoryProtocol
    public let classRepository: ClassRepositoryProtocol
    public let notificationService: NotificationServiceProtocol

    public init(
        scheduleRepository: ScheduleRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        notificationService: NotificationServiceProtocol = LocalNotificationService.shared
    ) {
        self.scheduleRepository = scheduleRepository
        self.classRepository = classRepository
        self.notificationService = notificationService
    }

    /// Lọc các buổi học diễn ra trong ngày đang được chọn
    public var sessionsForSelectedDate: [TeachingSessionEntity] {
        let calendar = Calendar.current
        return sessions.filter { session in
            calendar.isDate(session.startTime, inSameDayAs: selectedDate)
        }
    }

    /// Lưu hoặc cập nhật một buổi học, đồng thời snapshot danh sách điểm danh ban đầu và điều hướng lịch đến ngày của buổi học
    public func saveSession(_ session: TeachingSessionEntity, participantStudentIds: [UUID] = []) async throws {
        isLoading = true
        errorMessage = nil
        do {
            try await scheduleRepository.saveSession(session)

            if !participantStudentIds.isEmpty {
                let existingAttendances = try await scheduleRepository.fetchAttendances(forSessionId: session.id)
                let existingStudentIds = Set(existingAttendances.map { $0.studentId })
                let newAttendances = participantStudentIds
                    .filter { !existingStudentIds.contains($0) }
                    .map { studentId in
                        AttendanceEntity(
                            sessionId: session.id,
                            studentId: studentId,
                            status: .pending,
                            note: ""
                        )
                    }
                if !newAttendances.isEmpty {
                    try await scheduleRepository.saveAttendances(newAttendances)
                }
            }

            // Đồng bộ thông báo nhắc nhở trước 60 phút
            if session.status == .scheduled {
                await notificationService.scheduleSessionReminder(for: session)
            } else {
                await notificationService.cancelSessionReminder(sessionId: session.id)
            }

            // Tự động nhảy lịch sang ngày của buổi học vừa tạo/sửa để người dùng thấy ngay
            self.selectedDate = session.startTime
            await loadData()
        } catch {
            self.errorMessage = "Không thể lưu buổi học: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }

    /// Lưu hàng loạt các buổi học được sinh ra từ lịch lặp và khởi tạo danh sách điểm danh cho từng buổi
    public func saveRecurringSessions(_ sessions: [TeachingSessionEntity], participantStudentIds: [UUID] = []) async throws {
        guard !sessions.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            for session in sessions {
                try await scheduleRepository.saveSession(session)
                if session.status == .scheduled {
                    await notificationService.scheduleSessionReminder(for: session)
                }

                if !participantStudentIds.isEmpty {
                    let existingAttendances = try await scheduleRepository.fetchAttendances(forSessionId: session.id)
                    let existingStudentIds = Set(existingAttendances.map { $0.studentId })
                    let newAttendances = participantStudentIds
                        .filter { !existingStudentIds.contains($0) }
                        .map { studentId in
                            AttendanceEntity(
                                sessionId: session.id,
                                studentId: studentId,
                                status: .pending,
                                note: ""
                            )
                        }
                    if !newAttendances.isEmpty {
                        try await scheduleRepository.saveAttendances(newAttendances)
                    }
                }
            }

            if let first = sessions.first {
                self.selectedDate = first.startTime
            }
            await loadData()
        } catch {
            self.errorMessage = "Không thể lưu chuỗi buổi học: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }

    /// Cập nhật buổi học hiện tại và tất cả các buổi học tương lai trong cùng chuỗi lặp (status == .scheduled)
    /// Đảm bảo không đụng đến các buổi trong quá khứ đã hoàn thành (.completed)
    public func updateSeriesFutureSessions(from updatedSession: TeachingSessionEntity, originalStartTime: Date) async throws {
        isLoading = true
        errorMessage = nil
        do {
            guard let seriesId = updatedSession.seriesId else {
                try await scheduleRepository.saveSession(updatedSession)
                if updatedSession.status == .scheduled {
                    await notificationService.scheduleSessionReminder(for: updatedSession)
                } else {
                    await notificationService.cancelSessionReminder(sessionId: updatedSession.id)
                }
                self.selectedDate = updatedSession.startTime
                await loadData()
                return
            }

            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute], from: updatedSession.startTime)
            let newHour = startComponents.hour ?? 17
            let newMinute = startComponents.minute ?? 30
            let durationMinutes = max(15, updatedSession.durationMinutes)

            let classSessions = try await scheduleRepository.fetchSessionsForClass(classId: updatedSession.classId)
            let futureSeriesSessions = classSessions.filter { s in
                s.seriesId == seriesId &&
                s.startTime >= originalStartTime &&
                s.status == .scheduled
            }

            for var s in futureSeriesSessions {
                if s.id == updatedSession.id {
                    try await scheduleRepository.saveSession(updatedSession)
                    await notificationService.scheduleSessionReminder(for: updatedSession)
                } else {
                    var comp = calendar.dateComponents([.year, .month, .day], from: s.startTime)
                    comp.hour = newHour
                    comp.minute = newMinute
                    comp.second = 0
                    if let newStart = calendar.date(from: comp) {
                        s.startTime = newStart
                        s.endTime = newStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
                    }
                    s.title = updatedSession.title
                    s.setSeriesId(seriesId)
                    s.lessonNotes = "\(TeachingSessionEntity.seriesPrefix)\(seriesId.uuidString)\(TeachingSessionEntity.seriesSuffix)\n\(updatedSession.userDisplayNotes)".trimmingCharacters(in: .whitespacesAndNewlines)
                    s.homeworkAssigned = updatedSession.homeworkAssigned
                    s.updatedAt = Date()
                    try await scheduleRepository.saveSession(s)
                    await notificationService.scheduleSessionReminder(for: s)
                }
            }

            self.selectedDate = updatedSession.startTime
            await loadData()
        } catch {
            self.errorMessage = "Không thể cập nhật chuỗi lịch dạy: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }

    /// Tách một buổi học ra khỏi chuỗi lịch lặp (biến thành ngoại lệ đơn lẻ)
    public func detachSessionFromSeries(_ session: TeachingSessionEntity) async throws {
        var detached = session
        detached.setSeriesId(nil)
        detached.updatedAt = Date()
        try await scheduleRepository.saveSession(detached)
        if detached.status == .scheduled {
            await notificationService.scheduleSessionReminder(for: detached)
        } else {
            await notificationService.cancelSessionReminder(sessionId: detached.id)
        }
        self.selectedDate = detached.startTime
        await loadData()
    }

    public func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let calendar = Calendar.current
            let now = Date()
            let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
            // Tải các buổi học trong khoảng 180 ngày trước và 180 ngày tới để hỗ trợ lịch tháng mượt mà
            let start = calendar.date(byAdding: .day, value: -180, to: selectedDate) ?? selectedDate
            let end = calendar.date(byAdding: .day, value: 180, to: selectedDate) ?? selectedDate

            async let loadedSessions = scheduleRepository.fetchSessions(from: start, to: end)
            async let loadedClasses = classRepository.fetchClasses(includeArchived: false)

            self.sessions = try await loadedSessions
            self.classes = try await loadedClasses

            // Đảm bảo đồng bộ lời nhắc luôn dựa trên cửa sổ 30 ngày tính từ thời điểm hiện tại (now),
            // ngay cả khi người dùng đang lật xem một tháng quá khứ/tương lai xa trên lịch
            let sessionsForReminderSync: [TeachingSessionEntity]
            if start <= now && end >= thirtyDaysFromNow {
                sessionsForReminderSync = self.sessions
            } else {
                sessionsForReminderSync = (try? await scheduleRepository.fetchSessions(from: now, to: thirtyDaysFromNow)) ?? self.sessions
            }
            await notificationService.syncSessionReminders(for: sessionsForReminderSync)
        } catch {
            self.errorMessage = "Không thể tải lịch dạy: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func deleteSession(id: UUID) async {
        do {
            try await scheduleRepository.deleteSession(id: id)
            await notificationService.cancelSessionReminder(sessionId: id)
            await loadData()
        } catch {
            self.errorMessage = "Không thể xóa buổi học: \(error.localizedDescription)"
        }
    }

    public func cancelSession(id: UUID) async {
        do {
            if var session = try await scheduleRepository.fetchSession(byId: id) {
                session.status = .cancelled
                session.updatedAt = Date()
                try await scheduleRepository.saveSession(session)
                await notificationService.cancelSessionReminder(sessionId: id)
                await loadData()
            }
        } catch {
            self.errorMessage = "Không thể hủy buổi học: \(error.localizedDescription)"
        }
    }

    public func classGroup(for classId: UUID) -> ClassGroupEntity? {
        classes.first { $0.id == classId }
    }
}

