import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Tóm tắt trạng thái thực tế của quyền và hàng đợi thông báo trên hệ thống iOS
public struct NotificationStatusSummary: Sendable, Equatable {
    public let isAuthorized: Bool
    public let isDenied: Bool
    public let isNotDetermined: Bool
    public let pendingSessionReminderCount: Int
    public let nextSessionReminderDate: Date?
    public let isDailyReminderPending: Bool
    public let dailyReminderHour: Int
    public let dailyReminderMinute: Int

    public init(
        isAuthorized: Bool,
        isDenied: Bool,
        isNotDetermined: Bool,
        pendingSessionReminderCount: Int,
        nextSessionReminderDate: Date?,
        isDailyReminderPending: Bool,
        dailyReminderHour: Int,
        dailyReminderMinute: Int
    ) {
        self.isAuthorized = isAuthorized
        self.isDenied = isDenied
        self.isNotDetermined = isNotDetermined
        self.pendingSessionReminderCount = pendingSessionReminderCount
        self.nextSessionReminderDate = nextSessionReminderDate
        self.isDailyReminderPending = isDailyReminderPending
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
    }
}

/// Giao thức quản lý thông báo cục bộ (Local Notification Service Protocol)
public protocol NotificationServiceProtocol: AnyObject, Sendable {
    // Nhắc trước buổi dạy (Feature 9)
    var isSessionReminderEnabled: Bool { get set }
    func requestAuthorization() async -> Bool
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    @discardableResult
    func scheduleSessionReminder(for session: TeachingSessionEntity) async -> Bool
    func cancelSessionReminder(sessionId: UUID) async
    func syncSessionReminders(for sessions: [TeachingSessionEntity]) async
    func getPendingReminderSessionIds() async -> [UUID]

    // Nhắc xem lịch hằng ngày (Feature 10)
    var isDailyReminderEnabled: Bool { get set }
    var dailyReminderHour: Int { get set }
    var dailyReminderMinute: Int { get set }
    @discardableResult
    func scheduleDailyReminder(hour: Int, minute: Int) async -> Bool
    @discardableResult
    func updateDailyReminderTime(hour: Int, minute: Int) async -> Bool
    func cancelDailyReminder() async
    func syncDailyReminder() async
}

#if canImport(UserNotifications)
/// Xử lý delegate nhận và phản hồi thông báo từ hệ thống iOS
final class NotificationCenterDelegateHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        let activeOwnerId = UserSessionManager.shared.currentOwnerId

        var safeUserInfo: [String: String] = [:]
        if let type = userInfo["type"] as? String {
            safeUserInfo["type"] = type
        }
        if let target = userInfo["target"] as? String {
            safeUserInfo["target"] = target
        }
        if let sessionId = userInfo["sessionId"] as? String {
            safeUserInfo["sessionId"] = sessionId
        }
        if let ownerId = userInfo["ownerId"] as? String {
            safeUserInfo["ownerId"] = ownerId
        }
        let sessionStartTime: Double? = {
            if let ts = userInfo["sessionStartTime"] as? TimeInterval {
                return ts
            } else if let num = userInfo["sessionStartTime"] as? NSNumber {
                return num.doubleValue
            }
            return nil
        }()

        Task { @MainActor in
            var reconstructed: [AnyHashable: Any] = safeUserInfo
            if let sessionStartTime {
                reconstructed["sessionStartTime"] = sessionStartTime
            }
            _ = AppNavigationState.shared.handleNotificationTap(
                identifier: identifier,
                userInfo: reconstructed,
                currentOwnerId: activeOwnerId
            )
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let notifOwner = userInfo["ownerId"] as? String,
           !notifOwner.isEmpty,
           notifOwner != UserSessionManager.shared.currentOwnerId {
            completionHandler([])
            return
        }

        #if os(iOS)
        completionHandler([.banner, .list, .sound, .badge])
        #else
        completionHandler([.sound, .badge])
        #endif
    }
}
#endif

/// Dịch vụ quản lý Thông báo cục bộ (Local Notifications) trên thiết bị
/// Tuân thủ quy định iOS: Giới hạn tối đa 64 thông báo chờ, nhắc trước 60 phút, nhắc lặp hằng ngày lúc 22:00
public final class LocalNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    public static let shared = LocalNotificationService()

    private let userDefaults: UserDefaults

    // Khóa cấu hình Nhắc trước buổi dạy
    private static let sessionReminderKey = "EduPetal_Setting_SessionReminderEnabled"
    public static let sessionReminderPrefix = "session_reminder_"
    public static let maxScheduledSessionsCount = 40

    // Khóa cấu hình Nhắc hằng ngày lúc 22:00
    public static let dailyReminderIdentifier = "daily_schedule_reminder"
    private static let dailyReminderKey = "EduPetal_Setting_DailyReminderEnabled"
    private static let dailyReminderHourKey = "EduPetal_Setting_DailyReminderHour"
    private static let dailyReminderMinuteKey = "EduPetal_Setting_DailyReminderMinute"

    // Khóa lưu giờ gốc của người dùng khi bật chế độ test giờ gần hiện tại
    private static let savedPreTestHourKey = "EduPetal_Setting_PreTestDailyHour"
    private static let savedPreTestMinuteKey = "EduPetal_Setting_PreTestDailyMinute"
    private static let isNearTimeTestActiveKey = "EduPetal_Setting_IsNearTimeTestActive"

    #if canImport(UserNotifications)
    private let delegateHandler = NotificationCenterDelegateHandler()
    #endif

    /// Kiểm tra xem tiến trình hiện tại có bundle ứng dụng hợp lệ hỗ trợ UserNotifications không
    /// Tránh lỗi NSInternalInconsistencyException khi chạy trong môi trường Swift Package Manager / CLI Test Runner
    private var isNotificationCenterAvailable: Bool {
        #if canImport(UserNotifications)
        let bundlePath = Bundle.main.bundleURL.path
        if bundlePath.contains("XcodeDefault.xctoolchain") ||
           bundlePath.contains("swift-testing") ||
           Bundle.main.bundleIdentifier == nil {
            return false
        }
        return true
        #else
        return false
        #endif
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        configureDelegateIfNeeded()
    }

    /// Đăng ký `UNUserNotificationCenterDelegate` ngay từ khi khởi động app (không xin quyền lúc mở app)
    /// Giúp bắt đúng sự kiện chạm thông báo cả khi app đang đóng hoàn toàn (Cold Launch)
    public func configureDelegateIfNeeded() {
        #if canImport(UserNotifications)
        if isNotificationCenterAvailable {
            UNUserNotificationCenter.current().delegate = delegateHandler
        }
        #endif
    }

    /// Kiểm tra một trạng thái quyền iOS có cho phép đặt lịch thông báo hay không
    public func isAuthorizedStatus(_ status: UNAuthorizationStatus) -> Bool {
        #if os(iOS)
        return status == .authorized || status == .provisional || status == .ephemeral
        #else
        return status == .authorized || status == .provisional
        #endif
    }

    /// Xin quyền thông báo ở đúng ngữ cảnh người dùng thao tác (khi tạo lịch dạy hoặc bật/chỉnh thông báo trong Cài đặt).
    /// Tuyệt đối không gọi tự động lúc vừa mở app.
    public func requestAuthorizationIfNeeded() async -> Bool {
        let status = await checkAuthorizationStatus()
        if isAuthorizedStatus(status) {
            return true
        }
        if status == .notDetermined {
            return await requestAuthorization()
        }
        return false
    }

    // MARK: - Nhắc trước buổi dạy 60 phút (Loại A)

    public var isSessionReminderEnabled: Bool {
        get {
            if userDefaults.object(forKey: Self.sessionReminderKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: Self.sessionReminderKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.sessionReminderKey)
            if !newValue {
                Task {
                    await cancelAllSessionReminders()
                }
            }
        }
    }

    /// Bật/tắt công tắc Nhắc trước buổi dạy 60 phút từ giao diện Cài đặt (xử lý tuần tự, không chạy đè)
    @discardableResult
    public func setSessionReminderEnabled(_ enabled: Bool, upcomingSessions: [TeachingSessionEntity] = []) async -> Bool {
        userDefaults.set(enabled, forKey: Self.sessionReminderKey)
        if enabled {
            let granted = await requestAuthorizationIfNeeded()
            guard granted else { return false }
            await syncSessionReminders(for: upcomingSessions)
            return true
        } else {
            await cancelAllSessionReminders()
            return false
        }
    }

    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return true }
        do {
            configureDelegateIfNeeded()
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await syncDailyReminder()
            }
            return granted
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    public func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return .authorized }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
        #else
        return .authorized
        #endif
    }

    /// Lên lịch thông báo nhắc trước buổi dạy 60 phút (chỉ báo thành công sau khi thêm vào hàng đợi iOS thành công)
    @discardableResult
    public func scheduleSessionReminder(for session: TeachingSessionEntity) async -> Bool {
        return await scheduleSessionReminderInternal(for: session, allowPermissionPrompt: true)
    }

    @discardableResult
    private func scheduleSessionReminderInternal(
        for session: TeachingSessionEntity,
        allowPermissionPrompt: Bool
    ) async -> Bool {
        guard isSessionReminderEnabled else { return false }

        guard session.status == .scheduled else {
            await cancelSessionReminder(sessionId: session.id)
            return false
        }

        let reminderDate = session.startTime.addingTimeInterval(-60 * 60)
        guard reminderDate > Date() else {
            await cancelSessionReminder(sessionId: session.id)
            return false
        }

        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return true }

        let isAllowed: Bool
        if allowPermissionPrompt {
            isAllowed = await requestAuthorizationIfNeeded()
        } else {
            let status = await checkAuthorizationStatus()
            isAllowed = isAuthorizedStatus(status)
        }
        guard isAllowed else { return false }

        let center = UNUserNotificationCenter.current()
        let identifier = "\(Self.sessionReminderPrefix)\(session.id.uuidString)"
        let activeOwnerId = UserSessionManager.shared.currentOwnerId

        // Xóa bản ghi cũ cùng ID trước khi ghi mới để không tạo trùng
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Nhắc nhở buổi dạy: \(session.title)"
        content.body = "Buổi dạy sẽ bắt đầu lúc \(session.startTime.formatted(date: .omitted, time: .shortened)) (còn 60 phút). Hãy chuẩn bị tài liệu nhé! 🌸"
        content.sound = .default
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "sessionStartTime": session.startTime.timeIntervalSince1970,
            "ownerId": activeOwnerId,
            "type": "session_reminder"
        ]

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminderDate
        )
        triggerComponents.calendar = calendar
        triggerComponents.timeZone = TimeZone.current

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            let pending = await center.pendingNotificationRequests()
            return pending.contains { $0.identifier == identifier }
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    public func cancelSessionReminder(sessionId: UUID) async {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return }
        let identifier = "\(Self.sessionReminderPrefix)\(sessionId.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        #endif
    }

    public func cancelAllSessionReminders() async {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let sessionIds = requests
            .filter { $0.identifier.hasPrefix(Self.sessionReminderPrefix) }
            .map { $0.identifier }
        if !sessionIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: sessionIds)
            center.removeDeliveredNotifications(withIdentifiers: sessionIds)
        }
        #endif
    }

    public func syncSessionReminders(for sessions: [TeachingSessionEntity]) async {
        guard isSessionReminderEnabled else {
            await cancelAllSessionReminders()
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let thirtyDaysLater = calendar.date(byAdding: .day, value: 30, to: now) ?? now

        // Chỉ giữ các buổi scheduled trong 30 ngày tới mà mốc nhắc trước 60 phút vẫn còn ở tương lai (> now)
        let upcomingSessions = sessions
            .filter { session in
                session.status == .scheduled &&
                session.startTime.addingTimeInterval(-60 * 60) > now &&
                session.startTime <= thirtyDaysLater
            }
            .sorted { $0.startTime < $1.startTime }
            .prefix(Self.maxScheduledSessionsCount)

        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return }
        let status = await checkAuthorizationStatus()
        guard isAuthorizedStatus(status) else { return }

        let center = UNUserNotificationCenter.current()
        let activeOwnerId = UserSessionManager.shared.currentOwnerId
        let pendingRequests = await center.pendingNotificationRequests()

        let targetIds = Set(upcomingSessions.map { "\(Self.sessionReminderPrefix)\($0.id.uuidString)" })

        // Xóa tất cả session_reminder không còn nằm trong danh sách sắp tới hoặc thuộc về tài khoản khác
        let staleIds = pendingRequests.compactMap { req -> String? in
            guard req.identifier.hasPrefix(Self.sessionReminderPrefix) else { return nil }
            let reqOwner = req.content.userInfo["ownerId"] as? String
            if let reqOwner, !reqOwner.isEmpty, reqOwner != activeOwnerId {
                return req.identifier
            }
            if !targetIds.contains(req.identifier) {
                return req.identifier
            }
            return nil
        }

        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        for session in upcomingSessions {
            _ = await scheduleSessionReminderInternal(for: session, allowPermissionPrompt: false)
        }
        #endif
    }

    public func getPendingReminderSessionIds() async -> [UUID] {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return [] }
        let center = UNUserNotificationCenter.current()
        let activeOwnerId = UserSessionManager.shared.currentOwnerId
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap { req in
            guard req.identifier.hasPrefix(Self.sessionReminderPrefix) else { return nil }
            if let reqOwner = req.content.userInfo["ownerId"] as? String,
               !reqOwner.isEmpty,
               reqOwner != activeOwnerId {
                return nil
            }
            let idStr = req.identifier.replacingOccurrences(of: Self.sessionReminderPrefix, with: "")
            return UUID(uuidString: idStr)
        }
        #else
        return []
        #endif
    }

    // MARK: - Nhắc xem/thêm lịch hằng ngày lúc 22:00 (Loại B)

    /// Trạng thái bật/tắt nhắc xem lịch hằng ngày
    public var isDailyReminderEnabled: Bool {
        get {
            if userDefaults.object(forKey: Self.dailyReminderKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: Self.dailyReminderKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.dailyReminderKey)
            if !newValue {
                Task {
                    await cancelDailyReminder()
                }
            }
        }
    }

    /// Bật/tắt công tắc Nhắc xem/thêm lịch hằng ngày từ giao diện Cài đặt (xử lý tuần tự, không chạy đè)
    @discardableResult
    public func setDailyReminderEnabled(_ enabled: Bool) async -> Bool {
        userDefaults.set(enabled, forKey: Self.dailyReminderKey)
        if enabled {
            let granted = await requestAuthorizationIfNeeded()
            guard granted else { return false }
            return await scheduleDailyReminder(hour: dailyReminderHour, minute: dailyReminderMinute)
        } else {
            await cancelDailyReminder()
            return false
        }
    }

    /// Giờ nhắc hằng ngày (Mặc định: 22 giờ)
    public var dailyReminderHour: Int {
        get {
            if userDefaults.object(forKey: Self.dailyReminderHourKey) == nil {
                return 22
            }
            return userDefaults.integer(forKey: Self.dailyReminderHourKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.dailyReminderHourKey)
        }
    }

    /// Phút nhắc hằng ngày (Mặc định: 0 phút)
    public var dailyReminderMinute: Int {
        get {
            return userDefaults.integer(forKey: Self.dailyReminderMinuteKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.dailyReminderMinuteKey)
        }
    }

    /// Cập nhật nguyên tử cả giờ và phút nhắc hằng ngày rồi thay thế thông báo cũ (chống chạy đè 2 Task)
    @discardableResult
    public func updateDailyReminderTime(hour: Int, minute: Int) async -> Bool {
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))
        userDefaults.set(clampedHour, forKey: Self.dailyReminderHourKey)
        userDefaults.set(clampedMinute, forKey: Self.dailyReminderMinuteKey)

        guard isDailyReminderEnabled else { return false }
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return false }
        return await scheduleDailyReminder(hour: clampedHour, minute: clampedMinute)
    }

    /// Lên lịch thông báo lặp hằng ngày lúc HH:mm để nhắc giáo viên chuẩn bị lịch dạy ngày mai
    /// Luôn ghi đè thông báo cũ theo mã duy nhất 'daily_schedule_reminder' để không tạo trùng
    @discardableResult
    public func scheduleDailyReminder(hour: Int, minute: Int) async -> Bool {
        guard isDailyReminderEnabled else { return false }

        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return true }

        let status = await checkAuthorizationStatus()
        guard isAuthorizedStatus(status) else { return false }

        let center = UNUserNotificationCenter.current()
        let activeOwnerId = UserSessionManager.shared.currentOwnerId

        // Thay thế lịch cũ, không tạo thêm bản sao
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Chuẩn bị lịch dạy ngày mai 🌸"
        content.body = "Dành một chút thời gian xem lại lịch dạy hoặc thêm buổi dạy mới nhé!"
        content.sound = .default
        content.userInfo = [
            "type": "daily_schedule_reminder",
            "target": "schedule_tomorrow",
            "ownerId": activeOwnerId
        ]

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = TimeZone.current
        dateComponents.hour = max(0, min(23, hour))
        dateComponents.minute = max(0, min(59, minute))
        dateComponents.second = 0

        // repeats = true: Lặp lại hằng ngày theo giờ địa phương
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyReminderIdentifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            let pending = await center.pendingNotificationRequests()
            return pending.contains { $0.identifier == Self.dailyReminderIdentifier }
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// Hủy riêng thông báo nhắc hằng ngày mà không làm ảnh hưởng thông báo nhắc buổi dạy
    public func cancelDailyReminder() async {
        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.dailyReminderIdentifier])
        #endif
    }

    /// Đồng bộ lại thông báo hằng ngày (không tự ý bật xin quyền nếu chưa cấp quyền)
    public func syncDailyReminder() async {
        if isDailyReminderEnabled {
            _ = await scheduleDailyReminder(hour: dailyReminderHour, minute: dailyReminderMinute)
        } else {
            await cancelDailyReminder()
        }
    }

    /// Hủy toàn bộ thông báo của phiên cũ khi người dùng đăng xuất hoặc chuyển tài khoản (Chống lộ tên học sinh/buổi học của tài khoản trước)
    public func cancelAllUserNotificationsOnSessionChange() async {
        await cancelAllSessionReminders()
        await cancelDailyReminder()
        #if canImport(UserNotifications)
        if isNotificationCenterAvailable {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        #endif
    }

    // MARK: - Hỗ trợ kiểm thử bằng giờ gần hiện tại & Khôi phục giờ người dùng chọn

    /// Kiểm tra xem đang bật chế độ test bằng giờ gần hiện tại hay không
    public var isNearTimeTestActive: Bool {
        userDefaults.bool(forKey: Self.isNearTimeTestActiveKey)
    }

    /// Giờ người dùng đã chọn trước khi bấm test (mặc định 22:00)
    public var savedPreTestTime: (hour: Int, minute: Int) {
        let hour = userDefaults.object(forKey: Self.savedPreTestHourKey) == nil
            ? 22
            : userDefaults.integer(forKey: Self.savedPreTestHourKey)
        let minute = userDefaults.integer(forKey: Self.savedPreTestMinuteKey)
        return (max(0, min(23, hour)), max(0, min(59, minute)))
    }

    /// Đặt tạm giờ nhắc hằng ngày sang 1–2 phút tới để người dùng kiểm thử thực tế trên iPhone (Foreground / Background / Terminated),
    /// đồng thời lưu lại giờ người dùng đã chọn trước đó để khôi phục 1 chạm sau khi test xong.
    public func scheduleNearCurrentTimeForTesting() async -> (scheduled: Bool, testHour: Int, testMinute: Int) {
        if !isNearTimeTestActive {
            userDefaults.set(dailyReminderHour, forKey: Self.savedPreTestHourKey)
            userDefaults.set(dailyReminderMinute, forKey: Self.savedPreTestMinuteKey)
        }

        let now = Date()
        let calendar = Calendar.current
        let currentSecond = calendar.component(.second, from: now)
        // Nếu giây hiện tại >= 42, lùi sang +2 phút để người dùng đủ thời gian khóa máy hoặc vuốt đóng app
        let minutesToAdd = currentSecond >= 42 ? 2 : 1
        let targetDate = calendar.date(byAdding: .minute, value: minutesToAdd, to: now) ?? now.addingTimeInterval(60)
        let testHour = calendar.component(.hour, from: targetDate)
        let testMinute = calendar.component(.minute, from: targetDate)

        userDefaults.set(true, forKey: Self.sessionReminderKey)
        userDefaults.set(true, forKey: Self.dailyReminderKey)
        userDefaults.set(true, forKey: Self.isNearTimeTestActiveKey)

        let scheduled = await updateDailyReminderTime(hour: testHour, minute: testMinute)
        if !scheduled {
            userDefaults.set(false, forKey: Self.isNearTimeTestActiveKey)
        }
        return (scheduled, testHour, testMinute)
    }

    /// Khôi phục lại thời gian nhắc hằng ngày mà người dùng đã chọn trước khi test (hoặc về mặc định 22:00)
    public func restoreUserSelectedDailyTime(resetToDefault22: Bool = false) async -> (scheduled: Bool, hour: Int, minute: Int) {
        let target: (hour: Int, minute: Int) = resetToDefault22 ? (22, 0) : savedPreTestTime
        userDefaults.set(false, forKey: Self.isNearTimeTestActiveKey)
        userDefaults.removeObject(forKey: Self.savedPreTestHourKey)
        userDefaults.removeObject(forKey: Self.savedPreTestMinuteKey)
        let scheduled = await updateDailyReminderTime(hour: target.hour, minute: target.minute)
        return (scheduled, target.hour, target.minute)
    }

    /// Truy vấn trạng thái quyền thực tế và số lượng thông báo đang chờ trong hàng đợi của iOS
    public func fetchStatusSummary() async -> NotificationStatusSummary {
        let status = await checkAuthorizationStatus()
        let authorized = isAuthorizedStatus(status)
        let denied = (status == .denied)
        let notDetermined = (status == .notDetermined)

        #if canImport(UserNotifications)
        guard isNotificationCenterAvailable else {
            return NotificationStatusSummary(
                isAuthorized: authorized,
                isDenied: denied,
                isNotDetermined: notDetermined,
                pendingSessionReminderCount: 0,
                nextSessionReminderDate: nil,
                isDailyReminderPending: isDailyReminderEnabled && authorized,
                dailyReminderHour: dailyReminderHour,
                dailyReminderMinute: dailyReminderMinute
            )
        }

        let center = UNUserNotificationCenter.current()
        let activeOwnerId = UserSessionManager.shared.currentOwnerId
        let pending = await center.pendingNotificationRequests()

        var sessionCount = 0
        var earliestDate: Date? = nil
        var hasDaily = false

        for req in pending {
            if let reqOwner = req.content.userInfo["ownerId"] as? String,
               !reqOwner.isEmpty,
               reqOwner != activeOwnerId {
                continue
            }

            if req.identifier == Self.dailyReminderIdentifier {
                hasDaily = true
            } else if req.identifier.hasPrefix(Self.sessionReminderPrefix) {
                sessionCount += 1
                if let calTrigger = req.trigger as? UNCalendarNotificationTrigger,
                   let nextDate = calTrigger.nextTriggerDate() {
                    if let currentEarliest = earliestDate {
                        if nextDate < currentEarliest {
                            earliestDate = nextDate
                        }
                    } else {
                        earliestDate = nextDate
                    }
                }
            }
        }

        return NotificationStatusSummary(
            isAuthorized: authorized,
            isDenied: denied,
            isNotDetermined: notDetermined,
            pendingSessionReminderCount: sessionCount,
            nextSessionReminderDate: earliestDate,
            isDailyReminderPending: hasDaily,
            dailyReminderHour: dailyReminderHour,
            dailyReminderMinute: dailyReminderMinute
        )
        #else
        return NotificationStatusSummary(
            isAuthorized: authorized,
            isDenied: denied,
            isNotDetermined: notDetermined,
            pendingSessionReminderCount: 0,
            nextSessionReminderDate: nil,
            isDailyReminderPending: false,
            dailyReminderHour: dailyReminderHour,
            dailyReminderMinute: dailyReminderMinute
        )
        #endif
    }

    // MARK: - Tiện ích hệ thống

    @MainActor
    public static func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
