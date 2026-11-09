import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Hồ sơ Học sinh
@Model
public final class StudentModel {
    @Attribute(.unique) public var id: UUID
    public var fullName: String
    public var phoneNumber: String
    public var parentPhone: String
    public var email: String
    public var defaultPricePerSession: Int64?
    public var notes: String
    public var isArchived: Bool
    public var avatarPath: String?
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \EnrollmentModel.student)
    public var enrollments: [EnrollmentModel] = []

    public init(
        id: UUID = UUID(),
        fullName: String,
        phoneNumber: String = "",
        parentPhone: String = "",
        email: String = "",
        defaultPricePerSession: Int64? = nil,
        notes: String = "",
        isArchived: Bool = false,
        avatarPath: String? = nil,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.phoneNumber = phoneNumber
        self.parentPhone = parentPhone
        self.email = email
        self.defaultPricePerSession = defaultPricePerSession
        self.notes = notes
        self.isArchived = isArchived
        self.avatarPath = avatarPath
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enrollments = []
    }
}

