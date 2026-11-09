import Foundation

/// Thực thể thuần Swift đại diện cho Tệp / Hình ảnh đính kèm buổi học (Domain Entity)
/// Quy tắc: Chỉ lưu đường dẫn tương đối (File Path), tuyệt đối không lưu binary ảnh lớn vào database
public struct SessionAttachmentEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sessionId: UUID
    public var filePath: String
    public var fileType: String
    public var caption: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        filePath: String,
        fileType: String = "image/jpeg",
        caption: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.filePath = filePath
        self.fileType = fileType
        self.caption = caption
        self.createdAt = createdAt
    }
}

