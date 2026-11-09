import Foundation
import SwiftData

/// Hiện thực hóa GradeRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class GradeRepository: GradeRepositoryProtocol {
    private let modelContext: ModelContext
    private let explicitOwnerId: String?

    public var activeOwnerId: String {
        explicitOwnerId ?? UserSessionManager.shared.currentOwnerId
    }

    public init(modelContainer: ModelContainer, ownerId: String? = nil) {
        self.modelContext = modelContainer.mainContext
        self.explicitOwnerId = ownerId
    }

    public init(modelContext: ModelContext, ownerId: String? = nil) {
        self.modelContext = modelContext
        self.explicitOwnerId = ownerId
    }

    // MARK: - Assessment Operations

    public func fetchAssessments(forClassId classId: UUID) async throws -> [AssessmentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.classId == classId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { GradeMapper.toEntity($0) }
    }

    public func fetchAssessment(byId id: UUID) async throws -> AssessmentEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first,
              model.ownerId == currentOwner else { return nil }
        return GradeMapper.toEntity(model)
    }

    public func saveAssessment(_ assessment: AssessmentEntity) async throws {
        let currentOwner = activeOwnerId
        if !assessment.ownerId.isEmpty && assessment.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: assessment.ownerId,
                currentUserId: currentOwner
            )
        }

        let assessmentId = assessment.id
        let descriptor = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.id == assessmentId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            var owned = assessment
            owned.ownerId = currentOwner
            GradeMapper.updateModel(existing, from: owned)
        } else {
            var owned = assessment
            owned.ownerId = currentOwner
            let newModel = GradeMapper.toModel(owned)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func deleteAssessment(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Grade Operations

    public func fetchGrades(forAssessmentId assessmentId: UUID) async throws -> [GradeEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.id == assessmentId }
        )
        guard let assessmentModel = try modelContext.fetch(descriptor).first,
              assessmentModel.ownerId == currentOwner else { return [] }
        return assessmentModel.grades.map { GradeMapper.toGradeEntity($0) }
    }

    public func fetchGradesForStudent(studentId: UUID) async throws -> [GradeEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<GradeModel>()
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { $0.studentId == studentId && $0.assessment?.ownerId == currentOwner }
        return filtered.map { GradeMapper.toGradeEntity($0) }
    }

    public func saveGrade(_ grade: GradeEntity) async throws {
        try await saveGrades([grade])
    }

    public func saveGrades(_ grades: [GradeEntity]) async throws {
        let currentOwner = activeOwnerId
        guard let first = grades.first else { return }
        let assessmentId = first.assessmentId

        let desc = FetchDescriptor<AssessmentModel>(
            predicate: #Predicate<AssessmentModel> { $0.id == assessmentId }
        )
        guard let assessmentModel = try modelContext.fetch(desc).first else { return }
        guard assessmentModel.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: assessmentModel.ownerId,
                currentUserId: currentOwner
            )
        }

        for item in grades {
            if let existing = assessmentModel.grades.first(where: { $0.studentId == item.studentId }) {
                existing.score = item.score
                existing.notes = item.notes
                existing.recordedAt = item.recordedAt
            } else {
                let newGrade = GradeModel(
                    id: item.id,
                    assessment: assignmentOrAssessment(assessmentModel),
                    studentId: item.studentId,
                    score: item.score,
                    notes: item.notes,
                    recordedAt: item.recordedAt
                )
                modelContext.insert(newGrade)
                assessmentModel.grades.append(newGrade)
            }
        }
        try modelContext.save()
    }

    private func assignmentOrAssessment(_ model: AssessmentModel) -> AssessmentModel {
        model
    }
}
