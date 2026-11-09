import Foundation

/// Bộ chuyển đổi giữa StudentModel (SwiftData) và StudentEntity (Domain)
public enum StudentMapper {
    public static func toEntity(_ model: StudentModel) -> StudentEntity {
        StudentEntity(
            id: model.id,
            fullName: model.fullName,
            phoneNumber: model.phoneNumber,
            parentPhone: model.parentPhone,
            email: model.email,
            defaultPricePerSession: model.defaultPricePerSession,
            notes: model.notes,
            isArchived: model.isArchived,
            avatarPath: model.avatarPath,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateModel(_ model: StudentModel, from entity: StudentEntity) {
        model.fullName = entity.fullName
        model.phoneNumber = entity.phoneNumber
        model.parentPhone = entity.parentPhone
        model.email = entity.email
        model.defaultPricePerSession = entity.defaultPricePerSession
        model.notes = entity.notes
        model.isArchived = entity.isArchived
        model.avatarPath = entity.avatarPath
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toModel(_ entity: StudentEntity) -> StudentModel {
        StudentModel(
            id: entity.id,
            fullName: entity.fullName,
            phoneNumber: entity.phoneNumber,
            parentPhone: entity.parentPhone,
            email: entity.email,
            defaultPricePerSession: entity.defaultPricePerSession,
            notes: entity.notes,
            isArchived: entity.isArchived,
            avatarPath: entity.avatarPath,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }
}

