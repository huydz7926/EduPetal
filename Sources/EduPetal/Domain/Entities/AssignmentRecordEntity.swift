import Foundation

/// Thực thể thuần Swift theo dõi trạng thái bài tập của từng học sinh (Domain Entity)
public struct AssignmentRecordEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let assignmentId: UUID
    public let studentId: UUID
    public var status: AssignmentStatus
    public var score: Double?
    public var feedback: String
    public var submittedAt: Date?
    public var gradedAt: Date?

    public init(
        id: UUID = UUID(),
        assignmentId: UUID,
        studentId: UUID,
        status: AssignmentStatus = .notStarted,
        score: Double? = nil,
        feedback: String = "",
        submittedAt: Date? = nil,
        gradedAt: Date? = nil
    ) {
        self.id = id
        self.assignmentId = assignmentId
        self.studentId = studentId
        self.status = status
        self.score = score
        self.feedback = feedback
        self.submittedAt = submittedAt
        self.gradedAt = gradedAt
    }
}

