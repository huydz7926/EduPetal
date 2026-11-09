import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Bản ghi Điểm danh
@Model
public final class AttendanceModel {
    @Attribute(.unique) public var id: UUID
    public var studentId: UUID
    public var statusRaw: String
    public var note: String
    public var markedAt: Date?

    public var session: TeachingSessionModel?

    public init(
        id: UUID = UUID(),
        session: TeachingSessionModel? = nil,
        studentId: UUID,
        statusRaw: String = AttendanceStatus.pending.rawValue,
        note: String = "",
        markedAt: Date? = nil
    ) {
        self.id = id
        self.session = session
        self.studentId = studentId
        self.statusRaw = statusRaw
        self.note = note
        self.markedAt = markedAt
    }
}

