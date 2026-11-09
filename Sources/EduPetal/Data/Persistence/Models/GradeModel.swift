import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Điểm số học sinh
@Model
public final class GradeModel {
    @Attribute(.unique) public var id: UUID
    public var studentId: UUID
    public var score: Double
    public var notes: String
    public var recordedAt: Date

    public var assessment: AssessmentModel?

    public init(
        id: UUID = UUID(),
        assessment: AssessmentModel? = nil,
        studentId: UUID,
        score: Double,
        notes: String = "",
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.assessment = assessment
        self.studentId = studentId
        self.score = score
        self.notes = notes
        self.recordedAt = recordedAt
    }
}

