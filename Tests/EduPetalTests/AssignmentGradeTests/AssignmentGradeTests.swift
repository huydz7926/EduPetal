import Testing
import Foundation
import SwiftData
@testable import EduPetal

@Suite("Assignments & Grade Management Test Suite")
struct AssignmentGradeTests {

    @MainActor
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self,
            SessionAttachmentModel.self,
            AssignmentModel.self,
            AssignmentRecordModel.self,
            AssessmentModel.self,
            GradeModel.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Grade Input Validation Tests

    @Test("Điểm số hợp lệ trong khoảng 0 đến maxScore được chấp nhận")
    func testValidateGradeInput_Success() throws {
        let useCase = ValidateGradeInputUseCase()
        #expect(throws: Never.self) {
            try useCase.execute(score: 8.5, maxScore: 10.0)
            try useCase.execute(score: 0.0, maxScore: 10.0)
            try useCase.execute(score: 10.0, maxScore: 10.0)
        }
    }

    @Test("Chặn nhập điểm âm (score < 0) với lỗi GradeValidationError.negativeScore")
    func testValidateGradeInput_NegativeScoreThrows() {
        let useCase = ValidateGradeInputUseCase()
        #expect(throws: GradeValidationError.negativeScore) {
            try useCase.execute(score: -0.5, maxScore: 10.0)
        }
    }

    @Test("Chặn nhập điểm vượt điểm tối đa (score > maxScore) với lỗi scoreExceedsMax")
    func testValidateGradeInput_ScoreExceedsMaxThrows() {
        let useCase = ValidateGradeInputUseCase()
        #expect(throws: GradeValidationError.self) {
            try useCase.execute(score: 10.5, maxScore: 10.0)
        }
    }

    @Test("Chặn điểm tối đa <= 0 với lỗi invalidMaxScore")
    func testValidateGradeInput_InvalidMaxScoreThrows() {
        let useCase = ValidateGradeInputUseCase()
        #expect(throws: GradeValidationError.invalidMaxScore) {
            try useCase.execute(score: 5.0, maxScore: 0.0)
        }
    }

    // MARK: - Weighted Average Calculation Tests

    @Test("Tính điểm trung bình chuẩn xác cho 1 bài đánh giá")
    func testCalculateWeightedAverage_SingleAssessment() {
        let useCase = CalculateWeightedAverageUseCase()
        let assessment = AssessmentEntity(classId: UUID(), title: "Kiểm tra 15p", maxScore: 10.0, weight: 1.0)
        let grade = GradeEntity(assessmentId: assessment.id, studentId: UUID(), score: 8.0)

        let avg = useCase.execute(items: [StudentGradeItem(grade: grade, assessment: assessment)])
        #expect(avg == 8.0)
    }

    @Test("Tính điểm trung bình trọng số chuẩn xác với các hệ số khác nhau")
    func testCalculateWeightedAverage_MultipleWeights() {
        let useCase = CalculateWeightedAverageUseCase()
        // Bài 1: 7.0/10 hệ số 1.0
        let a1 = AssessmentEntity(classId: UUID(), title: "15p", maxScore: 10.0, weight: 1.0)
        let g1 = GradeEntity(assessmentId: a1.id, studentId: UUID(), score: 7.0)

        // Bài 2: 9.0/10 hệ số 2.0
        let a2 = AssessmentEntity(classId: UUID(), title: "1 tiết", maxScore: 10.0, weight: 2.0)
        let g2 = GradeEntity(assessmentId: a2.id, studentId: UUID(), score: 9.0)

        // (7*1 + 9*2) / 3 = 25 / 3 = 8.33 -> 8.3
        let avg = useCase.execute(items: [
            StudentGradeItem(grade: g1, assessment: a1),
            StudentGradeItem(grade: g2, assessment: a2)
        ])
        #expect(avg == 8.3)
    }

    @Test("Quy đổi chuẩn xác về thang điểm 10 khi các bài kiểm tra có maxScore khác nhau")
    func testCalculateWeightedAverage_DifferentMaxScores() {
        let useCase = CalculateWeightedAverageUseCase()
        // Bài 1: 40/50 (tương đương 8.0/10), hệ số 1.0
        let a1 = AssessmentEntity(classId: UUID(), title: "Bài tập lớn", maxScore: 50.0, weight: 1.0)
        let g1 = GradeEntity(assessmentId: a1.id, studentId: UUID(), score: 40.0)

        // Bài 2: 9.0/10, hệ số 1.0
        let a2 = AssessmentEntity(classId: UUID(), title: "Giữa kỳ", maxScore: 10.0, weight: 1.0)
        let g2 = GradeEntity(assessmentId: a2.id, studentId: UUID(), score: 9.0)

        // (8.0*1 + 9.0*1) / 2 = 8.5
        let avg = useCase.execute(items: [
            StudentGradeItem(grade: g1, assessment: a1),
            StudentGradeItem(grade: g2, assessment: a2)
        ])
        #expect(avg == 8.5)
    }

    @Test("Trả về nil khi danh sách điểm trống")
    func testCalculateWeightedAverage_EmptyList() {
        let useCase = CalculateWeightedAverageUseCase()
        let avg = useCase.execute(items: [])
        #expect(avg == nil)
    }

    // MARK: - Assignment CRUD & Tracking Tests

    @Test("Tạo mới và truy xuất bài tập theo lớp thành công")
    @MainActor
    func testSaveAndFetchAssignment() async throws {
        let container = try createTestContainer()
        let repository = AssignmentRepository(modelContainer: container)

        let classId = UUID()
        let assignment = AssignmentEntity(
            classId: classId,
            title: "Bài tập Đạo hàm cơ bản",
            descriptionText: "Làm bài 1, 2, 3 trang 45",
            maxScore: 10.0
        )

        try await repository.saveAssignment(assignment)
        let list = try await repository.fetchAssignments(forClassId: classId)

        #expect(list.count == 1)
        #expect(list.first?.title == "Bài tập Đạo hàm cơ bản")
        #expect(list.first?.maxScore == 10.0)
    }

    @Test("Theo dõi trạng thái nộp và chấm điểm bài tập của học sinh")
    @MainActor
    func testAssignmentRecordTracking() async throws {
        let container = try createTestContainer()
        let repository = AssignmentRepository(modelContainer: container)

        let assignment = AssignmentEntity(classId: UUID(), title: "Bài tập Phương trình")
        try await repository.saveAssignment(assignment)

        let studentId = UUID()
        let initialRecord = AssignmentRecordEntity(
            assignmentId: assignment.id,
            studentId: studentId,
            status: .notStarted
        )
        try await repository.saveRecord(initialRecord)

        var records = try await repository.fetchRecords(forAssignmentId: assignment.id)
        #expect(records.count == 1)
        #expect(records.first?.status == .notStarted)

        // Cập nhật sang Đã nộp và Đã chấm
        let gradedRecord = AssignmentRecordEntity(
            id: initialRecord.id,
            assignmentId: assignment.id,
            studentId: studentId,
            status: .graded,
            score: 9.5,
            feedback: "Trình bày rất tốt và đầy đủ các bước"
        )
        try await repository.saveRecord(gradedRecord)

        records = try await repository.fetchRecords(forAssignmentId: assignment.id)
        #expect(records.first?.status == .graded)
        #expect(records.first?.score == 9.5)
        #expect(records.first?.feedback == "Trình bày rất tốt và đầy đủ các bước")
    }

    // MARK: - Assessment & Grade Repository Tests

    @Test("Tạo bài đánh giá và lưu điểm số học sinh thành công")
    @MainActor
    func testSaveAndFetchAssessmentAndGrades() async throws {
        let container = try createTestContainer()
        let repository = GradeRepository(modelContainer: container)

        let classId = UUID()
        let assessment = AssessmentEntity(
            classId: classId,
            title: "Kiểm tra 1 tiết Đại số",
            maxScore: 10.0,
            weight: 2.0
        )
        try await repository.saveAssessment(assessment)

        let studentId = UUID()
        let grade = GradeEntity(
            assessmentId: assessment.id,
            studentId: studentId,
            score: 8.5,
            notes: "Cần chú ý câu hỏi phụ số 3"
        )
        try await repository.saveGrade(grade)

        let grades = try await repository.fetchGrades(forAssessmentId: assessment.id)
        #expect(grades.count == 1)
        #expect(grades.first?.score == 8.5)
        #expect(grades.first?.notes == "Cần chú ý câu hỏi phụ số 3")

        let studentGrades = try await repository.fetchGradesForStudent(studentId: studentId)
        #expect(studentGrades.count == 1)
        #expect(studentGrades.first?.assessmentId == assessment.id)
    }
}

