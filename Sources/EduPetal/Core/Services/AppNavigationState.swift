import Foundation
import Observation

/// Quản lý điều hướng toàn cục của ứng dụng khi tương tác từ Thông báo (Local Notification Deep Link)
@Observable
@MainActor
public final class AppNavigationState {
    public static let shared = AppNavigationState()

    public var selectedTabRaw: Int = 0 // 0: Home, 1: Students, 2: Schedule, 3: Exams/Classes, 4: Finance
    public var targetScheduleDate: Date? = nil
    public var targetSessionId: UUID? = nil
    public var shouldOpenAddSessionSheet: Bool = false

    public init() {}

    /// Điều hướng người dùng đến tab Lịch dạy ở mốc ngày mai
    public func navigateToScheduleTomorrow(openAddSheet: Bool = false) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        self.targetScheduleDate = tomorrow
        self.targetSessionId = nil
        self.selectedTabRaw = 2 // Tab Lịch dạy
        self.shouldOpenAddSessionSheet = openAddSheet
    }

    /// Điều hướng người dùng đến tab Lịch dạy và mở chi tiết buổi học cụ thể
    public func navigateToSession(sessionId: UUID, sessionDate: Date? = nil) {
        if let sessionDate {
            self.targetScheduleDate = sessionDate
        }
        self.targetSessionId = sessionId
        self.selectedTabRaw = 2 // Tab Lịch dạy
        self.shouldOpenAddSessionSheet = false
    }

    /// Xử lý khi người dùng chạm vào thông báo cục bộ từ hệ thống iOS.
    /// Kiểm tra `ownerId` để đảm bảo thông báo của tài khoản trước không bao giờ điều hướng hoặc lộ sang tài khoản hiện tại.
    @discardableResult
    public func handleNotificationTap(
        identifier: String,
        userInfo: [AnyHashable: Any],
        currentOwnerId: String = UserSessionManager.shared.currentOwnerId
    ) -> Bool {
        if let notifOwner = userInfo["ownerId"] as? String,
           !notifOwner.isEmpty,
           notifOwner != currentOwnerId {
            return false
        }

        let type = userInfo["type"] as? String
        let target = userInfo["target"] as? String

        if identifier == LocalNotificationService.dailyReminderIdentifier ||
           type == "daily_schedule_reminder" ||
           target == "schedule_tomorrow" {
            navigateToScheduleTomorrow()
            return true
        }

        if type == "session_reminder" || identifier.hasPrefix(LocalNotificationService.sessionReminderPrefix) {
            let rawSessionId = (userInfo["sessionId"] as? String)
                ?? identifier.replacingOccurrences(of: LocalNotificationService.sessionReminderPrefix, with: "")

            var sessionDate: Date? = nil
            if let timestamp = userInfo["sessionStartTime"] as? TimeInterval {
                sessionDate = Date(timeIntervalSince1970: timestamp)
            } else if let number = userInfo["sessionStartTime"] as? NSNumber {
                sessionDate = Date(timeIntervalSince1970: number.doubleValue)
            }

            if let sessionId = UUID(uuidString: rawSessionId) {
                navigateToSession(sessionId: sessionId, sessionDate: sessionDate)
                return true
            } else {
                self.targetScheduleDate = sessionDate ?? Date()
                self.selectedTabRaw = 2
                return true
            }
        }

        return false
    }
}

