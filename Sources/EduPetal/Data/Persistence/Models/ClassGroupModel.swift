import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Lớp học
@Model
public final class ClassGroupModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var subject: String
    public var defaultPricePerSession: Int64
    public var sessionDurationMinutes: Int
    public var colorHex: String
    public var notes: String
    public var isArchived: Bool
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \EnrollmentModel.classGroup)
    public var enrollments: [EnrollmentModel] = []

    public init(
        id: UUID = UUID(),
        name: String,
        subject: String,
        defaultPricePerSession: Int64 = 0,
        sessionDurationMinutes: Int = 90,
        colorHex: String = "#E88FA8",
        notes: String = "",
        isArchived: Bool = false,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.defaultPricePerSession = defaultPricePerSession
        self.sessionDurationMinutes = sessionDurationMinutes
        self.colorHex = colorHex
        self.notes = notes
        self.isArchived = isArchived
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enrollments = []
    }
}

