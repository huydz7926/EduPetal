import Foundation

/// Giao thức truy xuất dữ liệu Đánh giá & Điểm số (Domain Repository Protocol)
@MainActor
public protocol GradeRepositoryProtocol: AnyObject {
    // Assessment Operations
    func fetchAssessments(forClassId classId: UUID) async throws -> [AssessmentEntity]
    func fetchAssessment(byId id: UUID) async throws -> AssessmentEntity?
    func saveAssessment(_ assessment: AssessmentEntity) async throws
    func deleteAssessment(id: UUID) async throws

    // Grade Operations
    func fetchGrades(forAssessmentId assessmentId: UUID) async throws -> [GradeEntity]
    func fetchGradesForStudent(studentId: UUID) async throws -> [GradeEntity]
    func saveGrade(_ grade: GradeEntity) async throws
    func saveGrades(_ grades: [GradeEntity]) async throws
}

