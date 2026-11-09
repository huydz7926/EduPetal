import Foundation

/// Lỗi nghiệp vụ khi ghi danh học sinh vào lớp học
public enum EnrollmentValidationError: Error, LocalizedError, Equatable, Sendable {
    case alreadyActiveInClass
    case overlappingEnrollmentPeriod
    case studentArchived
    case classNotFound

    public var errorDescription: String? {
        switch self {
        case .alreadyActiveInClass:
            return "Học sinh hiện đang tham gia lớp học này."
        case .overlappingEnrollmentPeriod:
            return "Ngày bắt đầu tham gia bị chồng lấn với giai đoạn đã học trước đó của lớp này."
        case .studentArchived:
            return "Học sinh đang ở trạng thái Lưu trữ. Vui lòng khôi phục học sinh trước khi thêm vào lớp."
        case .classNotFound:
            return "Không tìm thấy thông tin lớp học."
        }
    }
}

/// Giao thức truy xuất dữ liệu Lớp học & Thành viên (Domain Repository Protocol)
@MainActor
public protocol ClassRepositoryProtocol: AnyObject {
    func fetchClasses(includeArchived: Bool) async throws -> [ClassGroupEntity]
    func fetchClass(byId id: UUID) async throws -> ClassGroupEntity?
    func saveClass(_ classGroup: ClassGroupEntity) async throws
    func archiveClass(id: UUID) async throws
    func restoreClass(id: UUID) async throws
    func deleteClass(id: UUID) async throws

    // Enrollment Management
    func fetchEnrollments(forClassId classId: UUID, activeOnly: Bool) async throws -> [EnrollmentEntity]
    func fetchEnrollments(forStudentId studentId: UUID, activeOnly: Bool) async throws -> [EnrollmentEntity]
    func enrollStudent(studentId: UUID, classId: UUID) async throws
    func enrollStudent(studentId: UUID, classId: UUID, enrolledAt: Date) async throws
    func unenrollStudent(studentId: UUID, classId: UUID) async throws
    func unenrollStudent(studentId: UUID, classId: UUID, leftAt: Date) async throws
    func isStudentEnrolled(studentId: UUID, classId: UUID) async throws -> Bool
}

public extension ClassRepositoryProtocol {
    func enrollStudent(studentId: UUID, classId: UUID, enrolledAt: Date) async throws {
        try await enrollStudent(studentId: studentId, classId: classId)
    }

    func unenrollStudent(studentId: UUID, classId: UUID, leftAt: Date) async throws {
        try await unenrollStudent(studentId: studentId, classId: classId)
    }
}
