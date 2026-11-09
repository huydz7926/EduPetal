import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho việc Ghi danh học sinh vào lớp học
@Model
public final class EnrollmentModel {
    @Attribute(.unique) public var id: UUID
    public var enrolledAt: Date
    public var leftAt: Date?
    public var isActive: Bool

    public var student: StudentModel?
    public var classGroup: ClassGroupModel?

    public init(
        id: UUID = UUID(),
        student: StudentModel? = nil,
        classGroup: ClassGroupModel? = nil,
        enrolledAt: Date = Date(),
        leftAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.student = student
        self.classGroup = classGroup
        self.enrolledAt = enrolledAt
        self.leftAt = leftAt
        self.isActive = isActive
    }
}

