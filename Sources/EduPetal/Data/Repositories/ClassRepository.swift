import Foundation
import SwiftData

/// Hiện thực hóa ClassRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class ClassRepository: ClassRepositoryProtocol {
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

    public func fetchClasses(includeArchived: Bool) async throws -> [ClassGroupEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ClassGroupModel>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { model in
                model.ownerId == currentOwner && (includeArchived || !model.isArchived)
            }
            .map { ClassMapper.toEntity($0) }
    }

    public func fetchClass(byId id: UUID) async throws -> ClassGroupEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ClassGroupModel>(
            predicate: #Predicate<ClassGroupModel> { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first,
              model.ownerId == currentOwner else {
            return nil
        }
        return ClassMapper.toEntity(model)
    }

    public func saveClass(_ classGroup: ClassGroupEntity) async throws {
        let currentOwner = activeOwnerId
        if !classGroup.ownerId.isEmpty && classGroup.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: classGroup.ownerId,
                currentUserId: currentOwner
            )
        }

        let classId = classGroup.id
        let descriptor = FetchDescriptor<ClassGroupModel>(
            predicate: #Predicate<ClassGroupModel> { $0.id == classId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            var owned = classGroup
            owned.ownerId = currentOwner
            ClassMapper.updateModel(existing, from: owned)
        } else {
            var owned = classGroup
            owned.ownerId = currentOwner
            let newModel = ClassMapper.toModel(owned)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func archiveClass(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ClassGroupModel>(
            predicate: #Predicate<ClassGroupModel> { $0.id == id }
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

    public func restoreClass(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ClassGroupModel>(
            predicate: #Predicate<ClassGroupModel> { $0.id == id }
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

    public func deleteClass(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ClassGroupModel>(
            predicate: #Predicate<ClassGroupModel> { $0.id == id }
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

    // MARK: - Enrollment Management

    public func fetchEnrollments(forClassId classId: UUID, activeOnly: Bool) async throws -> [EnrollmentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<EnrollmentModel>()
        let allEnrollments = try modelContext.fetch(descriptor)

        return allEnrollments.compactMap { enrollment in
            guard let cGroup = enrollment.classGroup,
                  cGroup.id == classId,
                  cGroup.ownerId == currentOwner else { return nil }
            if activeOnly && (!enrollment.isActive || enrollment.student?.isArchived == true) { return nil }
            return ClassMapper.toEnrollmentEntity(enrollment)
        }
    }

    public func fetchEnrollments(forStudentId studentId: UUID, activeOnly: Bool) async throws -> [EnrollmentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<EnrollmentModel>()
        let allEnrollments = try modelContext.fetch(descriptor)

        return allEnrollments
            .compactMap { enrollment -> EnrollmentEntity? in
                guard let student = enrollment.student,
                      student.id == studentId,
                      student.ownerId == currentOwner else { return nil }
                if activeOnly && !enrollment.isActive { return nil }
                return ClassMapper.toEnrollmentEntity(enrollment)
            }
            .sorted { $0.enrolledAt > $1.enrolledAt }
    }

    public func enrollStudent(studentId: UUID, classId: UUID) async throws {
        try await enrollStudent(studentId: studentId, classId: classId, enrolledAt: Date())
    }

    public func enrollStudent(studentId: UUID, classId: UUID, enrolledAt: Date) async throws {
        let currentOwner = activeOwnerId
        let studentDesc = FetchDescriptor<StudentModel>(predicate: #Predicate<StudentModel> { $0.id == studentId })
        let classDesc = FetchDescriptor<ClassGroupModel>(predicate: #Predicate<ClassGroupModel> { $0.id == classId })

        guard let student = try modelContext.fetch(studentDesc).first,
              let classGroup = try modelContext.fetch(classDesc).first else {
            return
        }

        guard student.ownerId == currentOwner && classGroup.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: student.ownerId != currentOwner ? student.ownerId : classGroup.ownerId,
                currentUserId: currentOwner
            )
        }

        if student.isArchived {
            throw EnrollmentValidationError.studentArchived
        }

        let enrollmentsDesc = FetchDescriptor<EnrollmentModel>()
        let all = try modelContext.fetch(enrollmentsDesc)
        let sameClassEnrollments = all.filter { $0.student?.id == studentId && $0.classGroup?.id == classId }

        if sameClassEnrollments.contains(where: { $0.isActive }) {
            throw EnrollmentValidationError.alreadyActiveInClass
        }

        for past in sameClassEnrollments where !past.isActive {
            if let leftAt = past.leftAt {
                if enrolledAt >= past.enrolledAt && enrolledAt < leftAt {
                    throw EnrollmentValidationError.overlappingEnrollmentPeriod
                }
            }
        }

        let newEnrollment = EnrollmentModel(
            student: student,
            classGroup: classGroup,
            enrolledAt: enrolledAt,
            leftAt: nil,
            isActive: true
        )
        modelContext.insert(newEnrollment)
        try modelContext.save()
    }

    public func unenrollStudent(studentId: UUID, classId: UUID) async throws {
        try await unenrollStudent(studentId: studentId, classId: classId, leftAt: Date())
    }

    public func unenrollStudent(studentId: UUID, classId: UUID, leftAt: Date) async throws {
        let currentOwner = activeOwnerId
        let enrollmentsDesc = FetchDescriptor<EnrollmentModel>()
        let all = try modelContext.fetch(enrollmentsDesc)
        if let activeEnrollment = all.first(where: {
            $0.student?.id == studentId &&
            $0.classGroup?.id == classId &&
            $0.isActive &&
            $0.classGroup?.ownerId == currentOwner
        }) {
            activeEnrollment.isActive = false
            activeEnrollment.leftAt = max(leftAt, activeEnrollment.enrolledAt)
            try modelContext.save()
        }
    }

    public func isStudentEnrolled(studentId: UUID, classId: UUID) async throws -> Bool {
        let currentOwner = activeOwnerId
        let enrollmentsDesc = FetchDescriptor<EnrollmentModel>()
        let all = try modelContext.fetch(enrollmentsDesc)
        return all.contains {
            $0.student?.id == studentId &&
            $0.classGroup?.id == classId &&
            $0.isActive &&
            $0.classGroup?.ownerId == currentOwner
        }
    }
}
