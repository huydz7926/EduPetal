import Foundation

/// Trạng thái điểm danh của từng học sinh trong buổi học
public enum AttendanceStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"   // Chưa điểm danh
    case present = "present"   // Có mặt
    case absent = "absent"     // Vắng mặt (học phí = 0)
    case excused = "excused"   // Vắng có phép (học phí = 0)

    public var displayName: String {
        switch self {
        case .pending: return "Chưa điểm danh"
        case .present: return "Có mặt"
        case .absent: return "Vắng mặt"
        case .excused: return "Có phép"
        }
    }
}

/// Thực thể thuần Swift đại diện cho Bản ghi Điểm danh (Domain Entity)
public struct AttendanceEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sessionId: UUID
    public let studentId: UUID
    public var status: AttendanceStatus
    public var note: String
    public var markedAt: Date?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        studentId: UUID,
        status: AttendanceStatus = .pending,
        note: String = "",
        markedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.studentId = studentId
        self.status = status
        self.note = note
        self.markedAt = markedAt
    }
}

