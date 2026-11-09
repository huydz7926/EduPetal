import Foundation
import Observation

/// ViewModel quản lý Bài tập (Module 5 — Assignment Management)
@Observable
@MainActor
public final class AssignmentViewModel {
    public var classId: UUID
    public var assignments: [AssignmentEntity] = []
    public var selectedAssignment: AssignmentEntity?
    public var assignmentRecords: [AssignmentRecordEntity] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    private let assignmentRepository: AssignmentRepositoryProtocol
    private let classRepository: ClassRepositoryProtocol

    public init(
        classId: UUID,
        assignmentRepository: AssignmentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol
    ) {
        self.classId = classId
        self.assignmentRepository = assignmentRepository
        self.classRepository = classRepository
    }

    public func loadAssignments() async {
        isLoading = true
        errorMessage = nil
        do {
            self.assignments = try await assignmentRepository.fetchAssignments(forClassId: classId)
        } catch {
            self.errorMessage = "Không thể tải danh sách bài tập: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func loadRecords(for assignmentId: UUID) async {
        do {
            self.assignmentRecords = try await assignmentRepository.fetchRecords(forAssignmentId: assignmentId)
        } catch {
            self.errorMessage = "Không thể tải bản ghi nộp bài: \(error.localizedDescription)"
        }
    }

    public func saveAssignment(_ assignment: AssignmentEntity) async {
        do {
            try await assignmentRepository.saveAssignment(assignment)

            // Tự động khởi tạo bản ghi cho tất cả học sinh trong lớp nếu là bài tập mới
            let enrollments = try await classRepository.fetchEnrollments(forClassId: classId, activeOnly: true)
            let existingRecords = try await assignmentRepository.fetchRecords(forAssignmentId: assignment.id)
            let existingStudentIds = Set(existingRecords.map { $0.studentId })

            var newRecords: [AssignmentRecordEntity] = []
            for e in enrollments {
                if !existingStudentIds.contains(e.studentId) {
                    newRecords.append(
                        AssignmentRecordEntity(
                            assignmentId: assignment.id,
                            studentId: e.studentId,
                            status: .notStarted
                        )
                    )
                }
            }
            if !newRecords.isEmpty {
                try await assignmentRepository.saveRecords(newRecords)
            }

            await loadAssignments()
        } catch {
            self.errorMessage = "Không thể lưu bài tập: \(error.localizedDescription)"
        }
    }

    public func updateRecordStatus(recordId: UUID, status: AssignmentStatus, score: Double?, feedback: String) async {
        if let idx = assignmentRecords.firstIndex(where: { $0.id == recordId }) {
            assignmentRecords[idx].status = status
            assignmentRecords[idx].score = score
            assignmentRecords[idx].feedback = feedback
            if status == .submitted && assignmentRecords[idx].submittedAt == nil {
                assignmentRecords[idx].submittedAt = Date()
            }
            if status == .graded {
                assignmentRecords[idx].gradedAt = Date()
            }
            try? await assignmentRepository.saveRecord(assignmentRecords[idx])
        }
    }
}

