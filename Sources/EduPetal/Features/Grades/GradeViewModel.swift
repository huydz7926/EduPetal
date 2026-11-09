import Foundation
import Observation

/// ViewModel quản lý Cột điểm, Đánh giá và Biểu đồ Tiến bộ học tập (Module 6 — Grade Management)
@Observable
@MainActor
public final class GradeViewModel {
    public var classId: UUID
    public var assessments: [AssessmentEntity] = []
    public var selectedAssessmentGrades: [GradeEntity] = []
    public var studentGrades: [StudentGradeItem] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    private let gradeRepository: GradeRepositoryProtocol
    private let averageUseCase = CalculateWeightedAverageUseCase()
    private let validationUseCase = ValidateGradeInputUseCase()

    public init(
        classId: UUID,
        gradeRepository: GradeRepositoryProtocol
    ) {
        self.classId = classId
        self.gradeRepository = gradeRepository
    }

    /// Điểm trung bình trọng số hiện tại (thang 10)
    public var weightedAverage: Double? {
        averageUseCase.execute(items: studentGrades)
    }

    public func loadAssessments() async {
        isLoading = true
        errorMessage = nil
        do {
            self.assessments = try await gradeRepository.fetchAssessments(forClassId: classId)
        } catch {
            self.errorMessage = "Không thể tải cột điểm: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func loadStudentGrades(studentId: UUID) async {
        isLoading = true
        do {
            let grades = try await gradeRepository.fetchGradesForStudent(studentId: studentId)
            var items: [StudentGradeItem] = []
            for g in grades {
                if let assessment = try await gradeRepository.fetchAssessment(byId: g.assessmentId) {
                    items.append(StudentGradeItem(grade: g, assessment: assessment))
                }
            }
            // Sắp xếp theo ngày tăng dần để vẽ biểu đồ tiến bộ
            self.studentGrades = items.sorted(by: { $0.assessment.date < $1.assessment.date })
        } catch {
            self.errorMessage = "Không thể tải điểm của học sinh: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func saveAssessment(_ assessment: AssessmentEntity) async {
        do {
            try await gradeRepository.saveAssessment(assessment)
            await loadAssessments()
        } catch {
            self.errorMessage = "Không thể lưu cột điểm: \(error.localizedDescription)"
        }
    }

    public func recordGrade(assessmentId: UUID, studentId: UUID, score: Double, maxScore: Double, notes: String = "") async throws {
        try validationUseCase.execute(score: score, maxScore: maxScore)

        let grade = GradeEntity(
            assessmentId: assessmentId,
            studentId: studentId,
            score: score,
            notes: notes
        )
        try await gradeRepository.saveGrade(grade)
    }
}

