import Testing
import Foundation
@testable import EduPetal

@Suite("Design System & Formatting Test Suite")
struct DesignSystemTests {

    @Test("Kiểm tra định dạng tiền VND cơ bản")
    func testFormattedVNDStandard() {
        let amount: Int64 = 250_000
        let formatted = amount.formattedVND
        #expect(formatted.contains("250.000"))
        #expect(formatted.contains("₫"))
    }

    @Test("Kiểm tra định dạng tiền VND bằng 0")
    func testFormattedVNDZero() {
        let amount: Int64 = 0
        let formatted = amount.formattedVND
        #expect(formatted.contains("0"))
        #expect(formatted.contains("₫"))
    }

    @Test("Kiểm tra định dạng số tiền âm (hoàn tiền/âm nợ)")
    func testFormattedVNDNegative() {
        let amount: Int64 = -100_000
        let formatted = amount.formattedVND
        #expect(formatted.contains("-100.000") || formatted.contains("- 100.000"))
        #expect(formatted.contains("₫"))
    }

    @Test("Kiểm tra phân tích chuỗi người dùng nhập thành Int64 VND")
    func testParseVNDFromString() {
        let raw1 = "250.000 ₫"
        let parsed1 = Int64.parseVND(from: raw1)
        #expect(parsed1 == 250_000)

        let raw2 = "1,500,000"
        let parsed2 = Int64.parseVND(from: raw2)
        #expect(parsed2 == 1_500_000)

        let rawEmpty = ""
        let parsedEmpty = Int64.parseVND(from: rawEmpty)
        #expect(parsedEmpty == 0)

        let rawText = "abc"
        let parsedText = Int64.parseVND(from: rawText)
        #expect(parsedText == 0)
    }

    @Test("Kiểm tra thứ bậc Spacing Scale tăng dần đều")
    func testAppSpacingHierarchy() {
        #expect(AppSpacing.xxs < AppSpacing.xs)
        #expect(AppSpacing.xs < AppSpacing.sm)
        #expect(AppSpacing.sm < AppSpacing.md)
        #expect(AppSpacing.md < AppSpacing.lg)
        #expect(AppSpacing.lg < AppSpacing.xl)
        #expect(AppSpacing.xl < AppSpacing.xxl)
        #expect(AppSpacing.xxl < AppSpacing.xxxl)
    }

    @Test("Kiểm tra thứ bậc Corner Radii tăng dần đều")
    func testAppRadiusHierarchy() {
        #expect(AppRadius.xs < AppRadius.sm)
        #expect(AppRadius.sm < AppRadius.md)
        #expect(AppRadius.md < AppRadius.lg)
        #expect(AppRadius.lg < AppRadius.xl)
        #expect(AppRadius.xl < AppRadius.full)
    }

    @Test("Kiểm tra định dạng số gom nhóm hàng nghìn (formattedGrouped)")
    func testFormattedGrouped() {
        let amount: Int64 = 1_234_567
        let grouped = amount.formattedGrouped
        #expect(grouped == "1.234.567")
    }

    @Test("Kiểm tra các thuộc tính hiển thị và ánh xạ ColorScheme của AppTheme")
    func testAppThemeProperties() {
        #expect(AppTheme.system.displayName == "Hệ thống")
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.system.iconName == "circle.lefthalf.filled")

        #expect(AppTheme.light.displayName == "Sáng")
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.light.iconName == "sun.max.fill")

        #expect(AppTheme.dark.displayName == "Tối")
        #expect(AppTheme.dark.colorScheme == .dark)
        #expect(AppTheme.dark.iconName == "moon.fill")
    }

    @Test("Kiểm tra ThemeManager lưu trữ và đồng bộ trạng thái theme bền vững")
    @MainActor
    func testThemeManagerPersistence() {
        let suiteName = "ThemeManagerTest_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let manager = ThemeManager(userDefaults: testDefaults)
        #expect(manager.currentTheme == .system)
        #expect(manager.colorScheme == nil)

        // Đổi sang Dark Mode
        manager.setTheme(.dark)
        #expect(manager.currentTheme == .dark)
        #expect(manager.colorScheme == .dark)

        // Kiểm tra lưu vào UserDefaults
        #expect(testDefaults.string(forKey: ThemeManager.themePreferenceKey) == "dark")

        // Khởi tạo instance mới đọc từ cùng UserDefaults
        let reloadedManager = ThemeManager(userDefaults: testDefaults)
        #expect(reloadedManager.currentTheme == .dark)
        #expect(reloadedManager.colorScheme == .dark)

        // Đổi sang Light Mode
        reloadedManager.setTheme(.light)
        #expect(reloadedManager.currentTheme == .light)
        #expect(reloadedManager.colorScheme == .light)
        #expect(testDefaults.string(forKey: ThemeManager.themePreferenceKey) == "light")
    }

    @Test("Kiểm tra LocalizationManager exactDictionary không chứa khóa trùng lặp và dịch an toàn khi bật English")
    @MainActor
    func testLocalizationExactDictionaryNoDuplicateKeysAndEnglishTranslation() {
        let pairs = LocalizationManager.exactTranslationPairs
        let uniqueKeys = Set(pairs.map { $0.0 })
        #expect(pairs.count == uniqueKeys.count)
        #expect(LocalizationManager.exactDictionary.count == uniqueKeys.count)

        let originalLanguage = LocalizationManager.shared.currentLanguage
        defer {
            LocalizationManager.shared.setLanguage(originalLanguage)
        }

        LocalizationManager.shared.setLanguage(.english)
        #expect(!LocalizationManager.exactDictionary.isEmpty)
        #expect(LocalizationManager.translate("Thu tiền") == "Record Payment")
        #expect(LocalizationManager.translate("Tổng quan") == "Overview")
        #expect(LocalizationManager.translate("Chào buổi sáng, Thầy/Cô!") == "Good morning, Teacher!")
    }

    @Test("Kiểm tra chuẩn hóa tên hiển thị của 5 tab điều hướng chính (AppTab)")
    @MainActor
    func testAppTabStandardizedTitles() {
        let originalLanguage = LocalizationManager.shared.currentLanguage
        defer {
            LocalizationManager.shared.setLanguage(originalLanguage)
        }

        LocalizationManager.shared.setLanguage(.vietnamese)
        #expect(AppTab.allCases.count == 5)
        #expect(AppTab.home.title == "Trang chủ")
        #expect(AppTab.students.title == "Học sinh")
        #expect(AppTab.classes.title == "Lớp học")
        #expect(AppTab.schedule.title == "Lịch dạy")
        #expect(AppTab.finance.title == "Học phí")

        LocalizationManager.shared.setLanguage(.english)
        #expect(AppTab.home.title == "Home")
        #expect(AppTab.students.title == "Students")
        #expect(AppTab.classes.title == "Classes")
        #expect(AppTab.schedule.title == "Schedule")
        #expect(AppTab.finance.title == "Tuition")
    }

    @Test("Tài khoản nhận học phí (BankConfigService) giữ nguyên thông tin sau khi đăng xuất và đăng nhập lại")
    @MainActor
    func testBankConfigPersistenceAcrossSignInAndSignOut() async throws {
        let suiteName = "BankConfigPersistenceTest_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let sessionManager = UserSessionManager(userDefaults: testDefaults, autoRestore: false)
        let bankService = BankConfigService(userDefaults: testDefaults, sessionManager: sessionManager)

        _ = try await sessionManager.signInWithGoogle(
            email: "teacher.bank@gmail.com",
            displayName: "Thầy Minh Huy",
            googleSubjectId: "bank_sub_1"
        )

        let savedConfig = BankAccountConfig(
            bankCode: "MB",
            bankName: "Ngân hàng Quân Đội (MB)",
            accountNumber: "0987654321",
            accountHolderName: "GIANG MINH HUY"
        )
        bankService.saveConfig(savedConfig)
        #expect(bankService.loadConfig() == savedConfig)

        // Đăng xuất -> cấu hình ngân hàng vẫn không bị mất
        await sessionManager.signOut()
        #expect(bankService.loadConfig() == savedConfig)

        // Đăng nhập lại hoặc chuyển phương thức -> cấu hình ngân hàng vẫn giữ nguyên
        _ = await sessionManager.continueAsGuest()
        #expect(bankService.loadConfig() == savedConfig)
    }
}


