import Foundation

/// Thực thể thuần Swift đại diện cho việc Ghi danh học sinh vào lớp học (Domain Entity)
public struct EnrollmentEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let studentId: UUID
    public let classId: UUID
    public var enrolledAt: Date
    public var leftAt: Date?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        studentId: UUID,
        classId: UUID,
        enrolledAt: Date = Date(),
        leftAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.studentId = studentId
        self.classId = classId
        self.enrolledAt = enrolledAt
        self.leftAt = leftAt
        self.isActive = isActive
    }
}

