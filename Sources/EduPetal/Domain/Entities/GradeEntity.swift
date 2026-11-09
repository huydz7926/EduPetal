import Foundation

/// Thực thể thuần Swift đại diện cho Điểm số của học sinh trong bài đánh giá (Domain Entity)
public struct GradeEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let assessmentId: UUID
    public let studentId: UUID
    public var score: Double
    public var notes: String
    public var recordedAt: Date

    public init(
        id: UUID = UUID(),
        assessmentId: UUID,
        studentId: UUID,
        score: Double,
        notes: String = "",
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.assessmentId = assessmentId
        self.studentId = studentId
        self.score = score
        self.notes = notes
        self.recordedAt = recordedAt
    }
}

