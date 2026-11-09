import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Bài tập
@Model
public final class AssignmentModel {
    @Attribute(.unique) public var id: UUID
    public var classId: UUID
    public var title: String
    public var descriptionText: String
    public var dueDate: Date
    public var maxScore: Double
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AssignmentRecordModel.assignment)
    public var records: [AssignmentRecordModel] = []

    public init(
        id: UUID = UUID(),
        classId: UUID,
        title: String,
        descriptionText: String = "",
        dueDate: Date = Date(),
        maxScore: Double = 10.0,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.classId = classId
        self.title = title
        self.descriptionText = descriptionText
        self.dueDate = dueDate
        self.maxScore = maxScore
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.records = []
    }
}

