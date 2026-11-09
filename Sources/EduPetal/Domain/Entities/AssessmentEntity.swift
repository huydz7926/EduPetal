import Foundation

/// Thực thể thuần Swift đại diện cho Bài kiểm tra / Cột điểm đánh giá (Domain Entity)
public struct AssessmentEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var classId: UUID
    public var title: String
    public var maxScore: Double
    public var weight: Double
    public var date: Date
    public var ownerId: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        classId: UUID,
        title: String,
        maxScore: Double = 10.0,
        weight: Double = 1.0,
        date: Date = Date(),
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.classId = classId
        self.title = title
        self.maxScore = maxScore
        self.weight = weight
        self.date = date
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

