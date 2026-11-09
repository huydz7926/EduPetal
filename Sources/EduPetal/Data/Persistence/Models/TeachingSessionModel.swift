import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Buổi học
@Model
public final class TeachingSessionModel {
    @Attribute(.unique) public var id: UUID
    public var classId: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var statusRaw: String
    public var lessonNotes: String
    public var homeworkAssigned: String
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AttendanceModel.session)
    public var attendances: [AttendanceModel] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionAttachmentModel.session)
    public var attachments: [SessionAttachmentModel] = []

    public init(
        id: UUID = UUID(),
        classId: UUID,
        title: String,
        startTime: Date,
        endTime: Date,
        statusRaw: String = SessionStatus.scheduled.rawValue,
        lessonNotes: String = "",
        homeworkAssigned: String = "",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.classId = classId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.statusRaw = statusRaw
        self.lessonNotes = lessonNotes
        self.homeworkAssigned = homeworkAssigned
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attendances = []
        self.attachments = []
    }
}

