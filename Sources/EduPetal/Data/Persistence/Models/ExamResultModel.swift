import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Kết quả thi của học sinh
@Model
public final class ExamResultModel {
    @Attribute(.unique) public var id: UUID
    public var examId: UUID
    public var studentId: UUID
    public var score: Double
    public var feedback: String
    public var ownerId: String = ""
    public var completedDate: Date

    public var exam: ExamModel?

    public init(
        id: UUID = UUID(),
        exam: ExamModel? = nil,
        examId: UUID,
        studentId: UUID,
        score: Double,
        feedback: String = "",
        ownerId: String = "",
        completedDate: Date = Date()
    ) {
        self.id = id
        self.exam = exam
        self.examId = examId
        self.studentId = studentId
        self.score = score
        self.feedback = feedback
        self.ownerId = ownerId
        self.completedDate = completedDate
    }
}

