import Foundation

/// Ngày trong tuần theo quy ước Calendar Gregorian (1: Chủ Nhật, 2: Thứ Hai, ..., 7: Thứ Bảy)
public enum DayOfWeek: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    public var id: Int { rawValue }

    public static func < (lhs: DayOfWeek, rhs: DayOfWeek) -> Bool {
        // Thứ tự hiển thị tự nhiên tại Việt Nam: T2 -> CN
        let order: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        let lIndex = order.firstIndex(of: lhs) ?? 0
        let rIndex = order.firstIndex(of: rhs) ?? 0
        return lIndex < rIndex
    }

    public var shortName: String {
        switch self {
        case .monday: return "T2"
        case .tuesday: return "T3"
        case .wednesday: return "T4"
        case .thursday: return "T5"
        case .friday: return "T6"
        case .saturday: return "T7"
        case .sunday: return "CN"
        }
    }

    public var fullName: String {
        switch self {
        case .monday: return "Thứ Hai"
        case .tuesday: return "Thứ Ba"
        case .wednesday: return "Thứ Tư"
        case .thursday: return "Thứ Năm"
        case .friday: return "Thứ Sáu"
        case .saturday: return "Thứ Bảy"
        case .sunday: return "Chủ Nhật"
        }
    }
}

/// Use case sinh danh sách các buổi học lặp cố định theo các ngày trong tuần
/// Đảm bảo không tạo trùng lặp với các buổi học đã có và giữ snapshot thông tin lớp học
public struct GenerateRecurringSessionsUseCase: Sendable {
    public init() {}

    /// Sinh các buổi học trong khoảng từ `startDate` đến `endDate` theo các ngày được chọn
    /// - Parameters:
    ///   - templateSession: Buổi học mẫu (chứa classId, title, startTime/endTime để lấy giờ, ghi chú, bài tập)
    ///   - selectedDays: Tập hợp các ngày trong tuần được chọn lặp
    ///   - startDate: Ngày bắt đầu khoảng áp dụng
    ///   - endDate: Ngày kết thúc khoảng áp dụng
    ///   - existingSessions: Danh sách buổi học hiện có trong hệ thống để tránh trùng lặp
    ///   - seriesId: Mã chuỗi lặp chung cho tất cả các buổi được sinh ra (mặc định sinh mới)
    /// - Returns: Danh sách các buổi học được sinh, sắp xếp tăng dần theo thời gian bắt đầu
    public func execute(
        templateSession: TeachingSessionEntity,
        selectedDays: Set<DayOfWeek>,
        startDate: Date,
        endDate: Date,
        existingSessions: [TeachingSessionEntity] = [],
        seriesId: UUID = UUID()
    ) -> [TeachingSessionEntity] {
        guard !selectedDays.isEmpty else { return [] }
        guard endDate >= startDate else { return [] }

        let calendar = Calendar.current
        let startOfDayRange = calendar.startOfDay(for: startDate)
        // Đặt endDate đến cuối ngày (23:59:59) để không sót ngày kết thúc
        let endOfDayRange = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        // Trích xuất giờ, phút bắt đầu và thời lượng từ template
        let templateStartComponents = calendar.dateComponents([.hour, .minute], from: templateSession.startTime)
        let templateHour = templateStartComponents.hour ?? 17
        let templateMinute = templateStartComponents.minute ?? 30
        let durationMinutes = max(15, templateSession.durationMinutes)

        var generatedSessions: [TeachingSessionEntity] = []
        var currentDate = startOfDayRange

        while currentDate <= endOfDayRange {
            let weekdayNumber = calendar.component(.weekday, from: currentDate)
            let isDaySelected = selectedDays.contains { $0.rawValue == weekdayNumber }

            if isDaySelected {
                // Tạo mốc giờ bắt đầu và kết thúc của buổi học trong ngày này
                var sessionStartComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
                sessionStartComponents.hour = templateHour
                sessionStartComponents.minute = templateMinute
                sessionStartComponents.second = 0

                if let sessionStart = calendar.date(from: sessionStartComponents) {
                    let sessionEnd = sessionStart.addingTimeInterval(TimeInterval(durationMinutes * 60))

                    // Kiểm tra xem đã có buổi học nào của lớp này trong ngày/giờ này chưa (Tránh tạo trùng lặp)
                    let isDuplicate = existingSessions.contains { existing in
                        existing.classId == templateSession.classId &&
                        calendar.isDate(existing.startTime, inSameDayAs: sessionStart) &&
                        abs(existing.startTime.timeIntervalSince(sessionStart)) < 120 &&
                        existing.status != .cancelled
                    }

                    if !isDuplicate {
                        var session = TeachingSessionEntity(
                            id: UUID(),
                            classId: templateSession.classId,
                            title: templateSession.title,
                            startTime: sessionStart,
                            endTime: sessionEnd,
                            status: .scheduled,
                            lessonNotes: templateSession.userDisplayNotes,
                            homeworkAssigned: templateSession.homeworkAssigned,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        session.setSeriesId(seriesId)
                        generatedSessions.append(session)
                    }
                }
            }

            // Tiến tới ngày tiếp theo
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDay
        }

        return generatedSessions.sorted { $0.startTime < $1.startTime }
    }
}

