import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Lựa chọn đáp án trắc nghiệm
@Model
public final class AnswerOptionModel {
    @Attribute(.unique) public var id: UUID
    public var content: String
    public var isCorrect: Bool
    public var orderIndex: Int

    public var question: QuestionModel?

    public init(
        id: UUID = UUID(),
        question: QuestionModel? = nil,
        content: String,
        isCorrect: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.question = question
        self.content = content
        self.isCorrect = isCorrect
        self.orderIndex = orderIndex
    }
}

