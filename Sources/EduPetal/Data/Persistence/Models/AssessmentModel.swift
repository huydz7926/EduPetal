import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Bài đánh giá / Cột điểm
@Model
public final class AssessmentModel {
    @Attribute(.unique) public var id: UUID
    public var classId: UUID
    public var title: String
    public var maxScore: Double
    public var weight: Double
    public var date: Date
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \GradeModel.assessment)
    public var grades: [GradeModel] = []

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
        self.grades = []
    }
}

