import Foundation

/// Giao thức truy xuất dữ liệu Bài tập & Bản ghi nộp bài (Domain Repository Protocol)
@MainActor
public protocol AssignmentRepositoryProtocol: AnyObject {
    func fetchAssignments(forClassId classId: UUID) async throws -> [AssignmentEntity]
    func fetchAssignment(byId id: UUID) async throws -> AssignmentEntity?
    func saveAssignment(_ assignment: AssignmentEntity) async throws
    func deleteAssignment(id: UUID) async throws

    // Assignment Records
    func fetchRecords(forAssignmentId assignmentId: UUID) async throws -> [AssignmentRecordEntity]
    func fetchRecordsForStudent(studentId: UUID) async throws -> [AssignmentRecordEntity]
    func saveRecord(_ record: AssignmentRecordEntity) async throws
    func saveRecords(_ records: [AssignmentRecordEntity]) async throws
}

