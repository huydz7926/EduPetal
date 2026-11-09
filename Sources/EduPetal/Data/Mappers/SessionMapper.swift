import Foundation

/// Bộ chuyển đổi giữa TeachingSessionModel / AttendanceModel / SessionAttachmentModel và các Domain Entities
public enum SessionMapper {
    public static func toEntity(_ model: TeachingSessionModel) -> TeachingSessionEntity {
        TeachingSessionEntity(
            id: model.id,
            classId: model.classId,
            title: model.title,
            startTime: model.startTime,
            endTime: model.endTime,
            status: SessionStatus(rawValue: model.statusRaw) ?? .scheduled,
            lessonNotes: model.lessonNotes,
            homeworkAssigned: model.homeworkAssigned,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateModel(_ model: TeachingSessionModel, from entity: TeachingSessionEntity) {
        model.classId = entity.classId
        model.title = entity.title
        model.startTime = entity.startTime
        model.endTime = entity.endTime
        model.statusRaw = entity.status.rawValue
        model.lessonNotes = entity.lessonNotes
        model.homeworkAssigned = entity.homeworkAssigned
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toModel(_ entity: TeachingSessionEntity) -> TeachingSessionModel {
        TeachingSessionModel(
            id: entity.id,
            classId: entity.classId,
            title: entity.title,
            startTime: entity.startTime,
            endTime: entity.endTime,
            statusRaw: entity.status.rawValue,
            lessonNotes: entity.lessonNotes,
            homeworkAssigned: entity.homeworkAssigned,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    public static func toAttendanceEntity(_ model: AttendanceModel) -> AttendanceEntity {
        AttendanceEntity(
            id: model.id,
            sessionId: model.session?.id ?? UUID(),
            studentId: model.studentId,
            status: AttendanceStatus(rawValue: model.statusRaw) ?? .pending,
            note: model.note,
            markedAt: model.markedAt
        )
    }

    public static func toAttachmentEntity(_ model: SessionAttachmentModel) -> SessionAttachmentEntity {
        SessionAttachmentEntity(
            id: model.id,
            sessionId: model.session?.id ?? UUID(),
            filePath: model.filePath,
            fileType: model.fileType,
            caption: model.caption,
            createdAt: model.createdAt
        )
    }
}

