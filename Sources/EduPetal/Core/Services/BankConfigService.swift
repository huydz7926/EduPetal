import Foundation

/// Cấu hình thông tin tài khoản ngân hàng của giáo viên để tạo mã VietQR
public struct BankAccountConfig: Codable, Sendable, Equatable {
    public var bankCode: String         // Mã ngân hàng (VCB, MB, TCB, ACB, BIDV, CTG, TPB, VPB...)
    public var bankName: String         // Tên hiển thị đầy đủ
    public var accountNumber: String    // Số tài khoản
    public var accountHolderName: String // Tên chủ tài khoản (in hoa không dấu)

    public init(
        bankCode: String = "VCB",
        bankName: String = "Vietcombank (VCB)",
        accountNumber: String = "",
        accountHolderName: String = ""
    ) {
        self.bankCode = bankCode
        self.bankName = bankName
        self.accountNumber = accountNumber
        self.accountHolderName = accountHolderName
    }

    public var isConfigured: Bool {
        !accountNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Dữ liệu thông tin ngân hàng hỗ trợ VietQR
public struct SupportedBank: Identifiable, Sendable, Hashable {
    public let code: String
    public let shortName: String
    public let name: String

    public var id: String { code }

    public init(code: String, shortName: String, name: String) {
        self.code = code
        self.shortName = shortName
        self.name = name
    }
}

/// Dịch vụ quản lý thông tin ngân hàng & tạo đường dẫn VietQR chuẩn NAPAS 247
public final class BankConfigService: @unchecked Sendable {
    public static let shared = BankConfigService()

    private let userDefaultsKeyPrefix = "edupetal_bank_account_config_"
    private let primaryDeviceKey = "edupetal_bank_account_config_primary"
    private let userDefaults: UserDefaults
    private let sessionManager: UserSessionManager

    private var scopedUserDefaultsKey: String {
        let owner = UserSessionManager.sanitizeIdentifier(sessionManager.currentOwnerId)
        return "\(userDefaultsKeyPrefix)\(owner)"
    }

    private var emailScopedUserDefaultsKey: String? {
        guard let email = sessionManager.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else {
            return nil
        }
        let hash = UserSessionManager.deterministicHash(of: "bank_email:\(email)")
        return "\(userDefaultsKeyPrefix)email_\(hash)"
    }

    private var persistentFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport.appendingPathComponent("EduPetal_BankAccountConfig.json")
    }

    public static let supportedBanks: [SupportedBank] = [
        SupportedBank(code: "VCB", shortName: "Vietcombank", name: "Ngân hàng Ngoại Thương Việt Nam (VCB)"),
        SupportedBank(code: "MB", shortName: "MB Bank", name: "Ngân hàng Quân Đội (MB)"),
        SupportedBank(code: "TCB", shortName: "Techcombank", name: "Ngân hàng Kỹ Thương (Techcombank)"),
        SupportedBank(code: "ACB", shortName: "ACB", name: "Ngân hàng Á Châu (ACB)"),
        SupportedBank(code: "BIDV", shortName: "BIDV", name: "Ngân hàng Đầu tư và Phát triển VN (BIDV)"),
        SupportedBank(code: "ICB", shortName: "VietinBank", name: "Ngân hàng Công Thương VN (VietinBank)"),
        SupportedBank(code: "TPB", shortName: "TPBank", name: "Ngân hàng Tiên Phong (TPBank)"),
        SupportedBank(code: "VPB", shortName: "VPBank", name: "Ngân hàng Việt Nam Thịnh Vượng (VPBank)"),
        SupportedBank(code: "VIB", shortName: "VIB", name: "Ngân hàng Quốc Tế (VIB)"),
        SupportedBank(code: "STB", shortName: "Sacombank", name: "Ngân hàng Sài Gòn Thương Tín (Sacombank)")
    ]

    public init(
        userDefaults: UserDefaults = .standard,
        sessionManager: UserSessionManager = .shared
    ) {
        self.userDefaults = userDefaults
        self.sessionManager = sessionManager
    }

    /// Tải cấu hình ngân hàng đã lưu (bền vững qua mọi lần đăng nhập / đăng xuất)
    public func loadConfig() -> BankAccountConfig {
        // 1. Ưu tiên đọc theo khóa của phiên hiện tại nếu đã cấu hình
        if let data = userDefaults.data(forKey: scopedUserDefaultsKey),
           let config = try? JSONDecoder().decode(BankAccountConfig.self, from: data),
           config.isConfigured {
            return config
        }

        // 2. Đọc theo khóa gắn với email của người dùng hiện tại (nếu có)
        if let emailKey = emailScopedUserDefaultsKey,
           let data = userDefaults.data(forKey: emailKey),
           let config = try? JSONDecoder().decode(BankAccountConfig.self, from: data),
           config.isConfigured {
            persistToAllStores(config)
            return config
        }

        // 3. Đọc từ khóa chính trên thiết bị (không bị mất khi sign out / sign in)
        if let data = userDefaults.data(forKey: primaryDeviceKey),
           let config = try? JSONDecoder().decode(BankAccountConfig.self, from: data),
           config.isConfigured {
            persistToAllStores(config)
            return config
        }

        // 4. Đọc từ file lưu bền vững trong Application Support
        if userDefaults == .standard,
           let data = try? Data(contentsOf: persistentFileURL),
           let config = try? JSONDecoder().decode(BankAccountConfig.self, from: data),
           config.isConfigured {
            persistToAllStores(config)
            return config
        }

        // 5. Khôi phục từ bất kỳ khóa `edupetal_bank_account_config_*` nào đã từng lưu trước đó
        for (key, value) in userDefaults.dictionaryRepresentation() where key.hasPrefix(userDefaultsKeyPrefix) {
            if let data = value as? Data,
               let config = try? JSONDecoder().decode(BankAccountConfig.self, from: data),
               config.isConfigured {
                persistToAllStores(config)
                return config
            }
        }

        return BankAccountConfig()
    }

    /// Lưu cấu hình ngân hàng bền vững qua các lần đăng nhập / đăng xuất
    public func saveConfig(_ config: BankAccountConfig) {
        persistToAllStores(config)
    }

    private func persistToAllStores(_ config: BankAccountConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        userDefaults.set(data, forKey: scopedUserDefaultsKey)
        if let emailKey = emailScopedUserDefaultsKey {
            userDefaults.set(data, forKey: emailKey)
        }
        userDefaults.set(data, forKey: primaryDeviceKey)
        if userDefaults == .standard {
            try? data.write(to: persistentFileURL, options: .atomic)
        }
    }

    /// Tạo URL ảnh VietQR chuẩn với số tiền và nội dung chuyển khoản
    /// Format công khai chuẩn: https://img.vietqr.io/image/<BANK_ID>-<ACCOUNT_NO>-compact2.png?amount=<AMOUNT>&addInfo=<CONTENT>&accountName=<NAME>
    public func generateVietQRURL(
        config: BankAccountConfig,
        amount: Int64,
        note: String
    ) -> URL? {
        guard config.isConfigured else { return nil }

        let cleanAcc = config.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBank = config.bankCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = config.accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var components = URLComponents(string: "https://img.vietqr.io/image/\(cleanBank)-\(cleanAcc)-compact2.png")
        var queryItems: [URLQueryItem] = []

        if amount > 0 {
            queryItems.append(URLQueryItem(name: "amount", value: "\(amount)"))
        }

        if !note.isEmpty {
            queryItems.append(URLQueryItem(name: "addInfo", value: note))
        }

        if !cleanName.isEmpty {
            queryItems.append(URLQueryItem(name: "accountName", value: cleanName))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    /// Chuỗi văn bản chuyển khoản nhanh cho phụ huynh (hỗ trợ copy/paste)
    public func generateTransferMessage(
        config: BankAccountConfig,
        amount: Int64,
        studentName: String,
        note: String
    ) -> String {
        let content = note.isEmpty ? "Hoc phi \(studentName)" : note
        return """
        🌸 THÔNG TIN CHUYỂN KHOẢN HỌC PHÍ — EDUPETAL
        • Ngân hàng: \(config.bankName)
        • Số tài khoản: \(config.accountNumber)
        • Chủ tài khoản: \(config.accountHolderName)
        • Số tiền: \(amount.formattedVND)
        • Nội dung chuyển khoản: \(content)

        (Sau khi chuyển khoản thành công, giáo viên sẽ xác nhận và gửi biên lai cho phụ huynh. Trân trọng cảm ơn!)
        """
    }
}
