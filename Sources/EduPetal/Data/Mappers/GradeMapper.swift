import Foundation

/// Bộ chuyển đổi giữa AssessmentModel / GradeModel và Domain Entities
public enum GradeMapper {
    public static func toEntity(_ model: AssessmentModel) -> AssessmentEntity {
        AssessmentEntity(
            id: model.id,
            classId: model.classId,
            title: model.title,
            maxScore: model.maxScore,
            weight: model.weight,
            date: model.date,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateModel(_ model: AssessmentModel, from entity: AssessmentEntity) {
        model.classId = entity.classId
        model.title = entity.title
        model.maxScore = entity.maxScore
        model.weight = entity.weight
        model.date = entity.date
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toModel(_ entity: AssessmentEntity) -> AssessmentModel {
        AssessmentModel(
            id: entity.id,
            classId: entity.classId,
            title: entity.title,
            maxScore: entity.maxScore,
            weight: entity.weight,
            date: entity.date,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    public static func toGradeEntity(_ model: GradeModel) -> GradeEntity {
        GradeEntity(
            id: model.id,
            assessmentId: model.assessment?.id ?? UUID(),
            studentId: model.studentId,
            score: model.score,
            notes: model.notes,
            recordedAt: model.recordedAt
        )
    }
}

