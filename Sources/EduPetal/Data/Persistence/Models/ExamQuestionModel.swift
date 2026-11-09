import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho liên kết Câu hỏi trong Đề thi
@Model
public final class ExamQuestionModel {
    @Attribute(.unique) public var id: UUID
    public var questionId: UUID
    public var orderIndex: Int
    public var customScore: Double

    public var exam: ExamModel?

    public init(
        id: UUID = UUID(),
        exam: ExamModel? = nil,
        questionId: UUID,
        orderIndex: Int = 0,
        customScore: Double = 1.0
    ) {
        self.id = id
        self.exam = exam
        self.questionId = questionId
        self.orderIndex = orderIndex
        self.customScore = customScore
    }
}

