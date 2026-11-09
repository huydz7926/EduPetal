import Foundation
import SwiftData

/// Hiện thực hóa StudentRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class StudentRepository: StudentRepositoryProtocol {
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

    public func fetchStudents(includeArchived: Bool) async throws -> [StudentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<StudentModel>(
            sortBy: [SortDescriptor(\.fullName, order: .forward)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { model in
                model.ownerId == currentOwner && (includeArchived || !model.isArchived)
            }
            .map { StudentMapper.toEntity($0) }
    }

    public func fetchStudent(byId id: UUID) async throws -> StudentEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<StudentModel>(
            predicate: #Predicate<StudentModel> { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first,
              model.ownerId == currentOwner else {
            return nil
        }
        return StudentMapper.toEntity(model)
    }

    public func saveStudent(_ student: StudentEntity) async throws {
        let currentOwner = activeOwnerId
        if !student.ownerId.isEmpty && student.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: student.ownerId,
                currentUserId: currentOwner
            )
        }

        let studentId = student.id
        let descriptor = FetchDescriptor<StudentModel>(
            predicate: #Predicate<StudentModel> { $0.id == studentId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            var ownedStudent = student
            ownedStudent.ownerId = currentOwner
            StudentMapper.updateModel(existing, from: ownedStudent)
        } else {
            var ownedStudent = student
            ownedStudent.ownerId = currentOwner
            let newModel = StudentMapper.toModel(ownedStudent)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func archiveStudent(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<StudentModel>(
            predicate: #Predicate<StudentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            existing.isArchived = true
            existing.updatedAt = Date()
            try modelContext.save()
        }
    }

    public func restoreStudent(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<StudentModel>(
            predicate: #Predicate<StudentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            existing.isArchived = false
            existing.updatedAt = Date()
            try modelContext.save()
        }
    }

    public func deleteStudent(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<StudentModel>(
            predicate: #Predicate<StudentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            if let avatar = existing.avatarPath {
                AvatarStorageService.shared.deleteAvatar(named: avatar)
            }
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    public func searchStudents(query: String, classId: UUID?, includeArchived: Bool) async throws -> [StudentEntity] {
        let allStudents = try await fetchStudents(includeArchived: includeArchived)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return allStudents.filter { student in
            let matchesQuery = trimmed.isEmpty ||
                student.fullName.lowercased().contains(trimmed) ||
                student.phoneNumber.contains(trimmed) ||
                student.email.lowercased().contains(trimmed)

            return matchesQuery
        }
    }
}
