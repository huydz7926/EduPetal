import Foundation

/// Bộ chuyển đổi giữa ClassGroupModel / EnrollmentModel (SwiftData) và ClassGroupEntity / EnrollmentEntity (Domain)
public enum ClassMapper {
    public static func toEntity(_ model: ClassGroupModel) -> ClassGroupEntity {
        ClassGroupEntity(
            id: model.id,
            name: model.name,
            subject: model.subject,
            defaultPricePerSession: model.defaultPricePerSession,
            sessionDurationMinutes: model.sessionDurationMinutes,
            colorHex: model.colorHex,
            notes: model.notes,
            isArchived: model.isArchived,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateModel(_ model: ClassGroupModel, from entity: ClassGroupEntity) {
        model.name = entity.name
        model.subject = entity.subject
        model.defaultPricePerSession = entity.defaultPricePerSession
        model.sessionDurationMinutes = entity.sessionDurationMinutes
        model.colorHex = entity.colorHex
        model.notes = entity.notes
        model.isArchived = entity.isArchived
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toModel(_ entity: ClassGroupEntity) -> ClassGroupModel {
        ClassGroupModel(
            id: entity.id,
            name: entity.name,
            subject: entity.subject,
            defaultPricePerSession: entity.defaultPricePerSession,
            sessionDurationMinutes: entity.sessionDurationMinutes,
            colorHex: entity.colorHex,
            notes: entity.notes,
            isArchived: entity.isArchived,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    public static func toEnrollmentEntity(_ model: EnrollmentModel) -> EnrollmentEntity {
        EnrollmentEntity(
            id: model.id,
            studentId: model.student?.id ?? UUID(),
            classId: model.classGroup?.id ?? UUID(),
            enrolledAt: model.enrolledAt,
            leftAt: model.leftAt,
            isActive: model.isActive
        )
    }
}

