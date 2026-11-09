import Foundation

/// Trạng thái của Buổi học
public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case scheduled = "scheduled"   // Đã lên lịch
    case completed = "completed"   // Đã hoàn thành (đã điểm danh 100%)
    case cancelled = "cancelled"   // Đã hủy

    public var displayName: String {
        switch self {
        case .scheduled: return "Đã lên lịch"
        case .completed: return "Đã hoàn thành"
        case .cancelled: return "Đã hủy"
        }
    }
}

/// Thực thể thuần Swift đại diện cho Buổi học / Buổi dạy (Domain Entity)
public struct TeachingSessionEntity: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var classId: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var status: SessionStatus
    public var lessonNotes: String
    public var homeworkAssigned: String
    public var ownerId: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        classId: UUID,
        title: String,
        startTime: Date,
        endTime: Date,
        status: SessionStatus = .scheduled,
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
        self.status = status
        self.lessonNotes = lessonNotes
        self.homeworkAssigned = homeworkAssigned
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Thời lượng buổi học tính bằng phút
    public var durationMinutes: Int {
        let diff = endTime.timeIntervalSince(startTime)
        return max(0, Int(diff / 60))
    }

    // MARK: - Recurring Series Support (Metadata Tag in lessonNotes)

    public static let seriesPrefix = "[SERIES:"
    public static let seriesSuffix = "]"

    /// Mã định danh chuỗi lịch lặp (nếu buổi học thuộc chuỗi lặp cố định)
    public var seriesId: UUID? {
        guard let startRange = lessonNotes.range(of: Self.seriesPrefix),
              let endRange = lessonNotes.range(of: Self.seriesSuffix, range: startRange.upperBound..<lessonNotes.endIndex) else {
            return nil
        }
        let uuidString = String(lessonNotes[startRange.upperBound..<endRange.lowerBound])
        return UUID(uuidString: uuidString)
    }

    /// Nội dung ghi chú người dùng nhập (đã loại bỏ thẻ kỹ thuật [SERIES:...])
    public var userDisplayNotes: String {
        guard let startRange = lessonNotes.range(of: Self.seriesPrefix),
              let endRange = lessonNotes.range(of: Self.seriesSuffix, range: startRange.upperBound..<lessonNotes.endIndex) else {
            return lessonNotes
        }
        var copy = lessonNotes
        copy.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        return copy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cập nhật seriesId cho buổi học mà không làm mất nội dung ghi chú người dùng
    public mutating func setSeriesId(_ id: UUID?) {
        let clean = userDisplayNotes
        if let id = id {
            if clean.isEmpty {
                self.lessonNotes = "\(Self.seriesPrefix)\(id.uuidString)\(Self.seriesSuffix)"
            } else {
                self.lessonNotes = "\(Self.seriesPrefix)\(id.uuidString)\(Self.seriesSuffix)\n\(clean)"
            }
        } else {
            self.lessonNotes = clean
        }
    }

    /// Kiểm tra xem buổi học có thuộc chuỗi lịch dạy lặp không
    public var isRecurring: Bool {
        seriesId != nil
    }
}

