import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Tệp đính kèm buổi học
@Model
public final class SessionAttachmentModel {
    @Attribute(.unique) public var id: UUID
    public var filePath: String
    public var fileType: String
    public var caption: String
    public var createdAt: Date

    public var session: TeachingSessionModel?

    public init(
        id: UUID = UUID(),
        session: TeachingSessionModel? = nil,
        filePath: String,
        fileType: String = "image/jpeg",
        caption: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.filePath = filePath
        self.fileType = fileType
        self.caption = caption
        self.createdAt = createdAt
    }
}

