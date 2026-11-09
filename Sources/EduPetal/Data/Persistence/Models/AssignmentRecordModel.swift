import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Bản ghi nộp bài tập của học sinh
@Model
public final class AssignmentRecordModel {
    @Attribute(.unique) public var id: UUID
    public var studentId: UUID
    public var statusRaw: String
    public var score: Double?
    public var feedback: String
    public var submittedAt: Date?
    public var gradedAt: Date?

    public var assignment: AssignmentModel?

    public init(
        id: UUID = UUID(),
        assignment: AssignmentModel? = nil,
        studentId: UUID,
        statusRaw: String = AssignmentStatus.notStarted.rawValue,
        score: Double? = nil,
        feedback: String = "",
        submittedAt: Date? = nil,
        gradedAt: Date? = nil
    ) {
        self.id = id
        self.assignment = assignment
        self.studentId = studentId
        self.statusRaw = statusRaw
        self.score = score
        self.feedback = feedback
        self.submittedAt = submittedAt
        self.gradedAt = gradedAt
    }
}

