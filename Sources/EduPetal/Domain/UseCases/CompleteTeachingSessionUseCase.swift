import Foundation

/// Lỗi phát sinh trong quy trình hoàn thành buổi học
public enum CompleteSessionError: Error, LocalizedError, Equatable {
    case unmarkedStudentsExist(pendingCount: Int)
    case missingStudents(missingCount: Int)
    case invalidTimeRange
    case alreadyCancelled

    public var errorDescription: String? {
        switch self {
        case .unmarkedStudentsExist(let count):
            return "Còn \(count) học sinh chưa được xác nhận điểm danh. Hãy điểm danh 100% học sinh trước khi hoàn thành buổi học."
        case .missingStudents(let count):
            return "Còn \(count) học sinh trong danh sách lớp chưa có bản ghi điểm danh."
        case .invalidTimeRange:
            return "Thời gian kết thúc buổi học phải sau thời gian bắt đầu."
        case .alreadyCancelled:
            return "Không thể hoàn thành một buổi học đã bị hủy."
        }
    }
}

/// Ca sử dụng Hoàn thành Buổi học (Complete Session Flow)
/// Bắt buộc xác nhận điểm danh 100% học sinh trước khi chuyển trạng thái sang .completed
public struct CompleteTeachingSessionUseCase: Sendable {
    public init() {}

    public func execute(
        session: TeachingSessionEntity,
        attendances: [AttendanceEntity],
        expectedStudentIds: [UUID]
    ) throws -> TeachingSessionEntity {
        // Kiểm tra trạng thái đã hủy
        guard session.status != .cancelled else {
            throw CompleteSessionError.alreadyCancelled
        }

        // Kiểm tra khoảng thời gian hợp lệ
        guard session.endTime > session.startTime else {
            throw CompleteSessionError.invalidTimeRange
        }

        // Kiểm tra danh sách học sinh mong đợi có đầy đủ bản ghi điểm danh không
        let recordedStudentIds = Set(attendances.map { $0.studentId })
        let missing = expectedStudentIds.filter { !recordedStudentIds.contains($0) }
        if !missing.isEmpty {
            throw CompleteSessionError.missingStudents(missingCount: missing.count)
        }

        // Kiểm tra xem còn học sinh nào ở trạng thái pending (chưa điểm danh) không
        let pending = attendances.filter { $0.status == .pending }
        if !pending.isEmpty {
            throw CompleteSessionError.unmarkedStudentsExist(pendingCount: pending.count)
        }

        // Tạo bản copy buổi học với trạng thái completed
        var updated = session
        updated.status = .completed
        updated.updatedAt = Date()
        return updated
    }
}

