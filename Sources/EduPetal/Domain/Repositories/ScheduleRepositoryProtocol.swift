import Foundation

/// Giao thức truy xuất dữ liệu Lịch dạy & Điểm danh (Domain Repository Protocol)
@MainActor
public protocol ScheduleRepositoryProtocol: AnyObject {
    // Session Operations
    func fetchSessions(from startDate: Date, to endDate: Date) async throws -> [TeachingSessionEntity]
    func fetchSession(byId id: UUID) async throws -> TeachingSessionEntity?
    func fetchSessionsForClass(classId: UUID) async throws -> [TeachingSessionEntity]
    func saveSession(_ session: TeachingSessionEntity) async throws
    func deleteSession(id: UUID) async throws

    // Attendance Operations
    func fetchAttendances(forSessionId sessionId: UUID) async throws -> [AttendanceEntity]
    func fetchAttendancesForStudent(studentId: UUID) async throws -> [AttendanceEntity]
    func saveAttendance(_ attendance: AttendanceEntity) async throws
    func saveAttendances(_ attendances: [AttendanceEntity]) async throws

    // Attachment Operations
    func fetchAttachments(forSessionId sessionId: UUID) async throws -> [SessionAttachmentEntity]
    func addAttachment(_ attachment: SessionAttachmentEntity) async throws
    func deleteAttachment(id: UUID) async throws
}

