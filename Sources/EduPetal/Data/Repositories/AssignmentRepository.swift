import Foundation
import SwiftData

/// Hiện thực hóa AssignmentRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class AssignmentRepository: AssignmentRepositoryProtocol {
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

    public func fetchAssignments(forClassId classId: UUID) async throws -> [AssignmentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.classId == classId },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { AssignmentMapper.toEntity($0) }
    }

    public func fetchAssignment(byId id: UUID) async throws -> AssignmentEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first,
              model.ownerId == currentOwner else { return nil }
        return AssignmentMapper.toEntity(model)
    }

    public func saveAssignment(_ assignment: AssignmentEntity) async throws {
        let currentOwner = activeOwnerId
        if !assignment.ownerId.isEmpty && assignment.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: assignment.ownerId,
                currentUserId: currentOwner
            )
        }

        let assignmentId = assignment.id
        let descriptor = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.id == assignmentId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            var owned = assignment
            owned.ownerId = currentOwner
            AssignmentMapper.updateModel(existing, from: owned)
        } else {
            var owned = assignment
            owned.ownerId = currentOwner
            let newModel = AssignmentMapper.toModel(owned)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func deleteAssignment(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.id == id }
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

    public func fetchRecords(forAssignmentId assignmentId: UUID) async throws -> [AssignmentRecordEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.id == assignmentId }
        )
        guard let assignmentModel = try modelContext.fetch(descriptor).first,
              assignmentModel.ownerId == currentOwner else { return [] }
        return assignmentModel.records.map { AssignmentMapper.toRecordEntity($0) }
    }

    public func fetchRecordsForStudent(studentId: UUID) async throws -> [AssignmentRecordEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AssignmentRecordModel>()
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { $0.studentId == studentId && $0.assignment?.ownerId == currentOwner }
        return filtered.map { AssignmentMapper.toRecordEntity($0) }
    }

    public func saveRecord(_ record: AssignmentRecordEntity) async throws {
        try await saveRecords([record])
    }

    public func saveRecords(_ records: [AssignmentRecordEntity]) async throws {
        let currentOwner = activeOwnerId
        guard let first = records.first else { return }
        let assignmentId = first.assignmentId

        let desc = FetchDescriptor<AssignmentModel>(
            predicate: #Predicate<AssignmentModel> { $0.id == assignmentId }
        )
        guard let assignmentModel = try modelContext.fetch(desc).first else { return }
        guard assignmentModel.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: assignmentModel.ownerId,
                currentUserId: currentOwner
            )
        }

        for item in records {
            if let existing = assignmentModel.records.first(where: { $0.studentId == item.studentId }) {
                existing.statusRaw = item.status.rawValue
                existing.score = item.score
                existing.feedback = item.feedback
                existing.submittedAt = item.submittedAt
                existing.gradedAt = item.gradedAt
            } else {
                let newRecord = AssignmentRecordModel(
                    id: item.id,
                    assignment: assignmentModel,
                    studentId: item.studentId,
                    statusRaw: item.status.rawValue,
                    score: item.score,
                    feedback: item.feedback,
                    submittedAt: item.submittedAt,
                    gradedAt: item.gradedAt
                )
                modelContext.insert(newRecord)
                assignmentModel.records.append(newRecord)
            }
        }
        try modelContext.save()
    }
}
