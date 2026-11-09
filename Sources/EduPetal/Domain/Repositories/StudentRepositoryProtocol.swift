import Foundation

/// Giao thức truy xuất dữ liệu Học sinh (Domain Repository Protocol)
@MainActor
public protocol StudentRepositoryProtocol: AnyObject {
    func fetchStudents(includeArchived: Bool) async throws -> [StudentEntity]
    func fetchStudent(byId id: UUID) async throws -> StudentEntity?
    func saveStudent(_ student: StudentEntity) async throws
    func archiveStudent(id: UUID) async throws
    func restoreStudent(id: UUID) async throws
    func deleteStudent(id: UUID) async throws
    func searchStudents(query: String, classId: UUID?, includeArchived: Bool) async throws -> [StudentEntity]
}
