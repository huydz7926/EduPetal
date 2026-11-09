import Foundation

/// Trạng thái làm bài tập của học sinh
public enum AssignmentStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "not_started"   // Chưa làm
    case inProgress = "in_progress"   // Đang làm
    case submitted = "submitted"       // Đã nộp
    case graded = "graded"             // Đã chấm

    public var displayName: String {
        switch self {
        case .notStarted: return "Chưa làm"
        case .inProgress: return "Đang làm"
        case .submitted: return "Đã nộp"
        case .graded: return "Đã chấm"
        }
    }
}

/// Thực thể thuần Swift đại diện cho Bài tập được giao (Domain Entity)
public struct AssignmentEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var classId: UUID
    public var title: String
    public var descriptionText: String
    public var dueDate: Date
    public var maxScore: Double
    public var ownerId: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        classId: UUID,
        title: String,
        descriptionText: String = "",
        dueDate: Date = Date().addingTimeInterval(7 * 24 * 3600),
        maxScore: Double = 10.0,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.classId = classId
        self.title = title
        self.descriptionText = descriptionText
        self.dueDate = dueDate
        self.maxScore = maxScore
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

