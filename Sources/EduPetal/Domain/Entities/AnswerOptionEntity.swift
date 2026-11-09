import Foundation

/// Thực thể thuần Swift đại diện cho Lựa chọn đáp án trắc nghiệm (Domain Entity)
public struct AnswerOptionEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var questionId: UUID
    public var content: String
    public var isCorrect: Bool
    public var orderIndex: Int

    public init(
        id: UUID = UUID(),
        questionId: UUID = UUID(),
        content: String,
        isCorrect: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.questionId = questionId
        self.content = content
        self.isCorrect = isCorrect
        self.orderIndex = orderIndex
    }
}

