import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Câu hỏi (Giữ lại trong Schema V1 để tương thích ngược cơ sở dữ liệu, không reset DB)
@Model
public final class QuestionModel {
    @Attribute(.unique) public var id: UUID
    public var content: String
    public var typeRaw: String
    public var subject: String
    public var topic: String
    public var difficultyRaw: String
    public var defaultScore: Double
    public var explanation: String
    public var gradingGuide: String
    public var imagePath: String?
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AnswerOptionModel.question)
    public var options: [AnswerOptionModel] = []

    public init(
        id: UUID = UUID(),
        content: String,
        typeRaw: String = "multipleChoice",
        subject: String = "",
        topic: String = "",
        difficultyRaw: String = "medium",
        defaultScore: Double = 1.0,
        explanation: String = "",
        gradingGuide: String = "",
        imagePath: String? = nil,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.typeRaw = typeRaw
        self.subject = subject
        self.topic = topic
        self.difficultyRaw = difficultyRaw
        self.defaultScore = defaultScore
        self.explanation = explanation
        self.gradingGuide = gradingGuide
        self.imagePath = imagePath
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.options = []
    }
}

