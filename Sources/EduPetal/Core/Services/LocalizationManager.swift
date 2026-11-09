import Foundation
import SwiftUI
import ObjectiveC.runtime

// MARK: - AppLanguage

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case vietnamese = "vi"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }

    public var flagEmoji: String {
        switch self {
        case .vietnamese: return "🇻🇳"
        case .english: return "🇬🇧"
        }
    }
}

/// Hàm tiện ích dịch nhanh Việt / Anh dùng trên toàn ứng dụng
public func L(_ vi: String, _ en: String) -> String {
    LocalizationManager.currentLanguageThreadSafe == .english ? en : vi
}

// MARK: - LocalizationManager

@Observable
public final class LocalizationManager: @unchecked Sendable {
    public static let shared = LocalizationManager()

    private static let languageKey = "app_language"
    @ObservationIgnored
    private static let lock = NSLock()
    @ObservationIgnored
    nonisolated(unsafe) private static var _cachedLanguage: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: "app_language"),
           let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        return .vietnamese
    }()

    public static var currentLanguageThreadSafe: AppLanguage {
        lock.lock()
        let lang = _cachedLanguage
        lock.unlock()
        return lang
    }

    public var currentLanguage: AppLanguage {
        didSet {
            let newLang = currentLanguage
            Self.lock.lock()
            Self._cachedLanguage = newLang
            Self.lock.unlock()
            UserDefaults.standard.set(newLang.rawValue, forKey: Self.languageKey)
        }
    }

    public var isEnglish: Bool {
        currentLanguage == .english
    }

    public var locale: Locale {
        switch currentLanguage {
        case .vietnamese: return Locale(identifier: "vi_VN")
        case .english: return Locale(identifier: "en_US")
        }
    }

    public init() {
        EduPetalLocalizedBundle.installIfNeeded()
        if let saved = UserDefaults.standard.string(forKey: Self.languageKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
            Self.lock.lock()
            Self._cachedLanguage = lang
            Self.lock.unlock()
        } else {
            self.currentLanguage = .vietnamese
        }
    }

    public func setLanguage(_ language: AppLanguage) {
        self.currentLanguage = language
    }

    public func toggleLanguage() {
        self.currentLanguage = (currentLanguage == .vietnamese) ? .english : .vietnamese
    }

    /// Dịch tự động chuỗi tiếng Việt sang tiếng Anh khi đang chọn English
    public static func translate(_ text: String) -> String {
        guard currentLanguageThreadSafe == .english else { return text }
        if text.isEmpty { return text }

        if let exact = exactDictionary[text] {
            return exact
        }

        // Xử lý các mẫu chuỗi động có số / tên biến
        var result = text
        for (viPhrase, enPhrase) in phraseReplacements {
            if result.contains(viPhrase) {
                result = result.replacingOccurrences(of: viPhrase, with: enPhrase)
            }
        }
        return result
    }

    // MARK: - Exact Dictionary (Vietnamese -> English)

    /// Danh sách cặp dịch chính xác (Việt -> Anh) dùng để khởi tạo `exactDictionary` thông qua
    /// `Dictionary(_:uniquingKeysWith:)` thay vì dictionary literal `[String: String]` nhằm loại bỏ
    /// hoàn toàn nguy cơ văng ứng dụng (`EXC_BREAKPOINT / SIGTRAP` trong `Dictionary.init(dictionaryLiteral:)`)
    public static let exactTranslationPairs: [(String, String)] = [
        // 1. Navigation & Tabs
        ("Tổng quan", "Overview"),
        ("Trang chủ", "Home"),
        ("Học sinh", "Students"),
        ("Lịch dạy", "Schedule"),
        ("Đề thi", "Exams"),
        ("Đề kiểm tra", "Exams"),
        ("Học phí", "Tuition"),
        ("Tài chính & Học phí", "Finance & Tuition"),
        ("Cài đặt & Hồ sơ", "Settings & Profile"),
        ("Lớp học", "Classes"),

        // 2. Common Buttons & Actions
        ("Lưu", "Save"),
        ("Hủy", "Cancel"),
        ("Hủy bỏ", "Cancel"),
        ("Đóng", "Close"),
        ("Xong", "Done"),
        ("Sửa", "Edit"),
        ("Chỉnh sửa", "Edit"),
        ("Xóa", "Delete"),
        ("Xóa vĩnh viễn", "Delete Permanently"),
        ("Khôi phục", "Restore"),
        ("Lưu trữ", "Archive"),
        ("Quay lại", "Back"),
        ("Đã hiểu", "Got it"),
        ("Chia sẻ", "Share"),
        ("Sao chép", "Copy"),
        ("Hôm nay", "Today"),
        ("Tất cả", "All"),
        ("Tất cả các lớp", "All Classes"),
        ("Tháng này", "This Month"),
        ("Tháng trước", "Last Month"),
        ("Chọn tháng", "Custom Month"),
        ("Ngày", "Day"),
        ("Tháng", "Month"),
        ("Lên lịch", "Schedule"),
        ("Thêm buổi", "Add Session"),
        ("Lên lịch buổi dạy", "Schedule Session"),
        ("Lên lịch dạy", "Schedule Session"),
        ("Thêm học sinh", "Add Student"),
        ("Quản lý lớp", "Manage Classes"),
        ("Tạo lớp học mới", "Create New Class"),
        ("Lớp mới", "New Class"),
        ("Thu tiền", "Record Payment"),
        ("Ghi nhận thu tiền", "Record Payment"),
        ("Xác nhận lưu", "Confirm & Save"),
        ("Xác nhận thêm vào lớp", "Confirm Enrollment"),
        ("Đang lưu...", "Saving..."),
        ("Đổi file", "Change File"),
        ("Gỡ ảnh", "Remove Photo"),

        // 3. Login & Auth & Privacy
        ("Quản lý lớp học & học phí", "Classroom & Tuition Management"),
        ("Tiếp tục với Google", "Continue with Google"),
        ("Tiếp tục với Email", "Continue with Email"),
        ("Tiếp tục với Apple", "Continue with Apple"),
        ("hoặc", "or"),
        ("Dùng thử ngay không cần tài khoản", "Try Instantly as Guest"),
        ("Đăng nhập", "Sign In"),
        ("Tạo tài khoản", "Create Account"),
        ("Họ và tên", "Full Name"),
        ("Nguyễn Văn A", "John Doe"),
        ("Mật khẩu", "Password"),
        ("Ít nhất 6 ký tự", "At least 6 characters"),
        ("Quên mật khẩu?", "Forgot password?"),
        ("Xác nhận mật khẩu", "Confirm Password"),
        ("Nhập lại mật khẩu", "Re-enter password"),
        ("Tiếp tục nghĩa là bạn đồng ý với điều khoản của EduPetal.", "By continuing, you agree to EduPetal's Terms & Privacy Policy."),
        ("Chính sách quyền riêng tư", "Privacy Policy"),
        ("Chính sách Quyền riêng tư", "Privacy Policy"),
        ("Khôi phục mật khẩu", "Reset Password"),
        ("Mật khẩu xác nhận không khớp.", "Passwords do not match."),
        ("Nhập email trước.", "Please enter your email first."),
        ("Không thể đăng nhập bằng Apple.", "Unable to sign in with Apple."),
        ("Tài khoản", "Account"),
        ("Đăng nhập / Tạo tài khoản", "Sign In / Create Account"),
        ("Đổi tài khoản / Phương thức đăng nhập", "Switch Account / Sign-In Method"),
        ("Đăng xuất", "Sign Out"),
        ("Đăng xuất tài khoản?", "Sign Out?"),
        ("Dữ liệu của bạn vẫn được giữ lại.", "Your teaching data remains safely stored on this device."),
        ("Giáo viên (Khách)", "Teacher (Guest)"),
        ("Chế độ Khách (Cô lập)", "Guest Mode"),
        ("Tài khoản Apple", "Apple Account"),
        ("Tài khoản Google", "Google Account"),
        ("Email & Mật khẩu", "Email & Password"),

        // 4. Home Dashboard
        ("Tài chính", "Finance"),
        ("Kỳ: Tất cả thời gian", "Period: All Time"),
        ("Học phí phát sinh", "Accrued"),
        ("Đang hoạt động", "Active"),
        ("Lịch dạy sắp tới", "Upcoming Schedule"),
        ("Chưa có buổi dạy hôm nay hoặc sắp tới.", "No sessions today or upcoming."),
        ("Chưa có lớp đang hoạt động.", "No active classes."),
        ("Chưa có học sinh đang hoạt động.", "No active students."),
        ("Sắp dạy", "Scheduled"),
        ("Đang học", "Active"),
        ("Đã lưu trữ", "Archived"),
        ("Chạm xem các lớp", "Tap to view classes"),
        ("Ca dạy hôm nay", "Today's Sessions"),
        ("Đã hoàn thành", "Completed"),
        ("Bài cần chấm", "To Grade"),
        ("Đã nộp", "Submitted"),
        ("Tài chính học phí", "Tuition Overview"),
        ("Phát sinh", "Accrued"),
        ("Đã thu", "Collected"),
        ("Còn nợ", "Outstanding"),
        ("Việc cần chú ý", "Attention Needed"),
        ("Chấm bài tập", "Grade Assignments"),
        ("Buổi học quá giờ", "Overdue Sessions"),
        ("Học phí còn nợ", "Unpaid Tuition"),
        ("Lịch dạy hôm nay", "Today's Schedule"),
        ("Hôm nay không có ca dạy", "No Sessions Today"),
        ("Chúc bạn một ngày nghỉ ngơi hoặc chuẩn bị giáo án thật vui vẻ!", "Enjoy your day off or lesson planning!"),
        ("Thao tác nhanh", "Quick Actions"),
        ("Buổi dạy", "Sessions"),

        // 5. Schedule & Sessions
        ("Sắp dạy (Tháng)", "Upcoming (Month)"),
        ("Sắp dạy (Ngày)", "Upcoming (Day)"),
        ("Hoàn thành (Tháng)", "Completed (Month)"),
        ("Hoàn thành (Ngày)", "Completed (Day)"),
        ("Sắp tới", "Upcoming"),
        ("Hoàn thành", "Completed"),
        ("Đã hủy", "Cancelled"),
        ("Không có buổi dạy", "No Teaching Sessions"),
        ("Chưa có buổi dạy trong tháng", "No Sessions This Month"),
        ("Trống lịch trong ngày này", "No sessions on this day"),
        ("Bấm 'Thêm buổi' hoặc chạm vào ô ngày để lên lịch dạy.", "Tap 'Add Session' or tap the date cell to schedule."),
        ("Bấm nút '+' để lên lịch buổi dạy mới hoặc tạo lịch lặp theo tháng.", "Tap '+' to schedule a new session or monthly recurring sessions."),
        ("Đang tải lịch dạy...", "Loading schedule..."),
        ("Hủy buổi dạy", "Cancel Session"),
        ("Hủy buổi", "Cancel Session"),
        ("Chi tiết buổi học", "Session Details"),
        ("Điểm danh học sinh", "Student Attendance"),
        ("Có mặt", "Present"),
        ("Vắng", "Absent"),
        ("Có phép", "Excused"),
        ("Chưa điểm danh", "Pending"),
        ("Nội dung đã dạy & Bài tập", "Lesson Notes & Homework"),
        ("Nội dung đã dạy", "Lesson Content Taught"),
        ("Bài tập về nhà", "Homework Assigned"),
        ("Lưu ghi chú", "Save Notes"),
        ("Ảnh minh chứng buổi học", "Session Proof Photos"),
        ("Chụp minh chứng", "Take Proof Photo"),
        ("Chọn từ thư viện", "Choose from Library"),
        ("Hoàn thành buổi học", "Complete Session"),

        // 6. Students & Classes
        ("Đang tải danh sách...", "Loading list..."),
        ("Không có học sinh lưu trữ", "No Archived Students"),
        ("Chưa có học sinh", "No Students Yet"),
        ("Các học sinh đã dừng học được chuyển vào mục lưu trữ để bảo toàn điểm số và học phí.", "Inactive students are kept in archive to preserve grades and tuition history."),
        ("Thêm học sinh đầu tiên để bắt đầu điểm danh, giao bài và theo dõi học phí.", "Add your first student to track attendance, grades, and tuition."),
        ("Tìm theo tên, SĐT, email...", "Search by name, phone, email..."),
        ("Xác nhận xóa học sinh", "Confirm Student Deletion"),
        ("Không thể xóa học sinh", "Cannot Delete Student"),
        ("Chuyển vào Lưu trữ", "Move to Archive"),
        ("Lưu trữ học sinh", "Archive Student"),
        ("Tiếp tục lưu trữ", "Archive Anyway"),
        ("Hồ sơ học sinh", "Student Profile"),
        ("Điểm số", "Grades"),
        ("Lớp & Lịch", "Classes & Schedule"),
        ("Tình hình học phí", "Tuition Summary"),
        ("Xem chi tiết", "View Details"),
        ("Thông tin liên hệ & Ghi chú", "Contact Info & Notes"),
        ("SĐT học sinh", "Student Phone"),
        ("SĐT phụ huynh", "Parent Phone"),
        ("Ghi chú sư phạm:", "Teacher Notes:"),
        ("Chưa có ghi chú sư phạm.", "No teacher notes yet."),
        ("Thêm lớp cho học sinh", "Add Class for Student"),
        ("1. Chọn lớp học", "1. Select Class"),
        ("2. Ngày bắt đầu & Đơn giá", "2. Start Date & Tuition Rate"),
        ("Ngày bắt đầu học", "Enrollment Start Date"),
        ("Áp dụng học phí riêng", "Use Custom Tuition Rate"),
        ("Đơn giá riêng mỗi buổi (VND)", "Custom Rate per Session (VND)"),
        ("3. Lịch học", "3. Schedule Setup"),
        ("Tạo lịch học theo tháng", "Create Monthly Schedule"),
        ("Tạo thêm lịch tháng mới", "Add Monthly Schedule"),
        ("Tháng áp dụng", "Target Month"),
        ("Chọn thứ học trong tuần", "Select Days of Week"),
        ("Bắt đầu", "Start"),
        ("Kết thúc", "End"),
        ("Từ ngày", "From"),
        ("Đến", "To"),
        ("4. Xem trước lịch học", "4. Schedule Preview"),
        ("Chưa có buổi học nào được chọn.", "No sessions selected yet."),

        // 7. Classes & First-Time Guide
        ("Các lớp đang dạy", "Active Classes"),
        ("Chưa có lớp lưu trữ", "No Archived Classes"),
        ("Bắt đầu nhanh trong 3 bước", "Quick Start in 3 Steps"),
        ("Tạo lớp đầu tiên", "Create First Class"),
        ("Lên lịch buổi đầu", "Schedule First Session"),
        ("Hiện hướng dẫn", "Show Guide"),
        ("Làm sau", "Later"),
        ("Bỏ qua hướng dẫn", "Skip Guide"),
        ("Bổ sung tùy chọn", "Optional Details"),
        ("Màu nhận diện lớp (16 màu)", "Class Color (16 Colors)"),
        ("Thiết lập lịch theo tháng", "Monthly Schedule"),
        ("Tạo 1 buổi lẻ", "Single Session"),
        ("Chưa có buổi dạy sắp tới", "No upcoming sessions"),

        // 8. Finance & Tuition & Receipts
        ("Học phí học sinh", "Student Tuition"),
        ("Phiếu thu đã lập", "Payment Receipts"),
        ("Đã thu trong kỳ", "Collected in Period"),
        ("Còn nợ hiện tại", "Current Outstanding"),
        ("Tổng còn nợ hiện tại", "Total Outstanding"),
        ("Tổng còn nợ", "Total Outstanding"),
        ("Một phần", "Partial"),
        ("Chưa thu", "Unpaid"),
        ("Đã thu đủ", "Paid in Full"),
        ("Đã hoàn tất", "Paid"),
        ("Thanh toán một phần", "Partially Paid"),
        ("Chưa thanh toán", "Unpaid"),
        ("Chưa phát sinh", "No Charges"),
        ("Không có học sinh nào", "No Students Found"),
        ("Thử chuyển bộ lọc sang 'Tất cả' để xem đầy đủ danh sách.", "Switch filter to 'All' to view all students."),
        ("Chưa có phiếu thu", "No Receipts Yet"),
        ("Các phiếu thu học phí sẽ xuất hiện tại đây để bạn xuất hóa đơn và chia sẻ.", "Recorded tuition receipts will appear here for PDF invoice export and sharing."),
        ("Tìm học sinh, lớp, mã phiếu thu...", "Search student, class, receipt code..."),
        ("Hóa đơn", "Invoice"),
        ("Phiếu thu học phí", "Tuition Receipt"),
        ("PHIẾU THU HỌC PHÍ", "TUITION RECEIPT"),
        ("Đã xác nhận", "Confirmed"),
        ("SỐ TIỀN ĐÃ THANH TOÁN", "AMOUNT PAID"),
        ("Phương thức thanh toán", "Payment Method"),
        ("Dư nợ còn lại sau thu", "Remaining Balance"),
        ("Nội dung / Ghi chú", "Notes"),
        ("Xuất & Chia sẻ Hóa đơn", "Export & Share Invoice"),
        ("Đã sao chép nội dung phiếu thu!", "Receipt copied to clipboard!"),
        ("Mã QR chuyển khoản", "Bank Transfer QR"),
        ("Sao chép thông tin", "Copy Details"),
        ("Tạo Bản kê nháp PDF", "Create Draft Statement PDF"),
        ("Chia sẻ PDF nháp", "Share Draft PDF"),

        // 9. Settings
        ("Ngôn ngữ / Language", "Language / Ngôn ngữ"),
        ("Ngôn ngữ hiển thị", "App Language"),
        ("Tài khoản nhận học phí (VietQR)", "Bank Account for Tuition (VietQR)"),
        ("Chưa cài đặt tài khoản", "Bank account not configured"),
        ("Thông báo & Lời nhắc", "Notifications & Reminders"),
        ("Nhắc trước buổi dạy (60 phút)", "Session Reminder (60 mins before)"),
        ("Gửi thông báo cục bộ trước giờ bắt đầu 1 tiếng", "Send a local alert 1 hour before class starts"),
        ("Nhắc xem lịch hằng ngày", "Daily Schedule Reminder"),
        ("Tiêu đề: Chuẩn bị lịch dạy ngày mai 🌸", "Daily reminder to review tomorrow's classes 🌸"),
        ("Giờ nhắc hằng ngày", "Daily Reminder Time"),
        ("Đã cấp quyền nhận thông báo", "Notifications Enabled"),
        ("Quyền thông báo đang bị tắt trong Cài đặt iPhone.", "Notifications are disabled in iOS Settings."),
        ("Mở Cài đặt iPhone", "Open iOS Settings"),
        ("Giao diện & Chủ đề", "Appearance & Theme"),
        ("Chủ đề hiển thị", "Theme"),
        ("Hệ thống", "System"),
        ("Sáng", "Light"),
        ("Tối", "Dark"),
        ("Bảo mật & Quyền riêng tư", "Security & Privacy"),
        ("Xem Chính sách Quyền riêng tư", "View Privacy Policy"),
        ("Sao lưu & Xuất dữ liệu", "Backup & Data Export"),
        ("Định dạng xuất:", "Export Format:"),
        ("Phiên bản", "Version")
    ]

    public static let exactDictionary: [String: String] = Dictionary(
        exactTranslationPairs,
        uniquingKeysWith: { _, latest in latest }
    )

    // MARK: - Dynamic Phrase Replacements

    private static let phraseReplacements: [(String, String)] = [
        ("Chào buổi sáng", "Good morning"),
        ("Chào buổi chiều", "Good afternoon"),
        ("Chào buổi tối", "Good evening"),
        ("Thầy/Cô", "Teacher"),
        ("Danh sách học phí học sinh", "Student Tuition List"),
        ("Bảng kê buổi học thanh toán", "Paid Sessions Breakdown"),
        ("Chi tiết buổi học", "Session Details"),
        ("Danh sách buổi dạy", "Teaching Sessions"),
        ("Các lớp đang tham gia", "Enrolled Classes"),
        ("Danh sách bài kiểm tra", "Assessments"),
        ("Danh sách buổi đã dạy", "Completed Sessions"),
        ("buổi hoàn thành", "completed sessions"),
        ("ảnh minh chứng", "proof photos"),
        ("buổi có mặt", "present"),
        ("Kỳ xem:", "Period:"),
        ("Kỳ:", "Period:"),
        ("Lịch ngày", "Schedule for"),
        ("Ngày thu:", "Paid on:"),
        ("Ngày học:", "Session Date:"),
        ("Tổng đã thu:", "Total Collected:"),
        ("Mặc định theo lớp:", "Class Default:"),
        ("Đang học", "Active"),
        ("Các lớp", "Classes"),
        ("Tháng ", "Month "),
        ("Thg ", "M"),
        (" buổi", " sessions"),
        (" ảnh", " photos"),
        (" phút", " mins"),
        (" trang", " pages"),
        ("/buổi", "/session")
    ]
}

// MARK: - Bundle Swizzling so SwiftUI LocalizedStringKey uses LocalizationManager

private final class EduPetalLocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) private static var isInstalled = false

    static func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        object_setClass(Bundle.main, EduPetalLocalizedBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if LocalizationManager.currentLanguageThreadSafe == .english {
            let translated = LocalizationManager.translate(key)
            if translated != key {
                return translated
            }
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}