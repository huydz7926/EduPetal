import Foundation

/// Ca sử dụng kiểm tra giao thoa / trùng lịch dạy (Overlap Check)
/// Quy tắc: Hai khoảng thời gian [startA, endA) và [startB, endB) trùng nhau khi max(startA, startB) < min(endA, endB)
/// Các buổi học có trạng thái .cancelled bị bỏ qua không tính trùng
public struct CheckScheduleOverlapUseCase: Sendable {
    public init() {}

    public func execute(
        newStartTime: Date,
        newEndTime: Date,
        existingSessions: [TeachingSessionEntity],
        excludeSessionId: UUID? = nil
    ) -> TeachingSessionEntity? {
        guard newEndTime > newStartTime else { return nil }

        for session in existingSessions {
            // Bỏ qua chính buổi học đang sửa (nếu có)
            if let excludeId = excludeSessionId, session.id == excludeId {
                continue
            }
            // Bỏ qua các buổi đã hủy
            if session.status == .cancelled {
                continue
            }

            let startMax = max(newStartTime, session.startTime)
            let endMin = min(newEndTime, session.endTime)

            if startMax < endMin {
                return session // Tìm thấy buổi học bị trùng
            }
        }

        return nil
    }
}

