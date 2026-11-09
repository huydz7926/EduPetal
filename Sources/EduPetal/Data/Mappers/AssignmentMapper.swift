import Foundation

/// Bộ chuyển đổi giữa AssignmentModel / AssignmentRecordModel và Domain Entities
public enum AssignmentMapper {
    public static func toEntity(_ model: AssignmentModel) -> AssignmentEntity {
        AssignmentEntity(
            id: model.id,
            classId: model.classId,
            title: model.title,
            descriptionText: model.descriptionText,
            dueDate: model.dueDate,
            maxScore: model.maxScore,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateModel(_ model: AssignmentModel, from entity: AssignmentEntity) {
        model.classId = entity.classId
        model.title = entity.title
        model.descriptionText = entity.descriptionText
        model.dueDate = entity.dueDate
        model.maxScore = entity.maxScore
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toModel(_ entity: AssignmentEntity) -> AssignmentModel {
        AssignmentModel(
            id: entity.id,
            classId: entity.classId,
            title: entity.title,
            descriptionText: entity.descriptionText,
            dueDate: entity.dueDate,
            maxScore: entity.maxScore,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    public static func toRecordEntity(_ model: AssignmentRecordModel) -> AssignmentRecordEntity {
        AssignmentRecordEntity(
            id: model.id,
            assignmentId: model.assignment?.id ?? UUID(),
            studentId: model.studentId,
            status: AssignmentStatus(rawValue: model.statusRaw) ?? .notStarted,
            score: model.score,
            feedback: model.feedback,
            submittedAt: model.submittedAt,
            gradedAt: model.gradedAt
        )
    }
}

