import Foundation

/// Kết quả kiểm tra cấu hình Firebase & Google Sign-In (Không bao giờ lưu/in API_KEY ra log)
public struct FirebaseConfigInspectionResult: Sendable, Equatable {
    public let isPlistFound: Bool
    public let projectId: String
    public let plistBundleId: String
    public let expectedBundleId: String
    public let isBundleIdMatched: Bool
    public let isSignInEnabled: Bool
    public let hasOAuthClientId: Bool
    public let googleAppId: String?
    public let encodedAppScheme: String?
    public let clientId: String?
    public let reversedClientId: String?
    public let hasCallbackURLSchemeConfigured: Bool

    public init(
        isPlistFound: Bool,
        projectId: String,
        plistBundleId: String,
        expectedBundleId: String = "com.edupetal.app",
        isBundleIdMatched: Bool,
        isSignInEnabled: Bool,
        hasOAuthClientId: Bool,
        googleAppId: String? = nil,
        encodedAppScheme: String? = nil,
        clientId: String? = nil,
        reversedClientId: String? = nil,
        hasCallbackURLSchemeConfigured: Bool
    ) {
        self.isPlistFound = isPlistFound
        self.projectId = projectId
        self.plistBundleId = plistBundleId
        self.expectedBundleId = expectedBundleId
        self.isBundleIdMatched = isBundleIdMatched
        self.isSignInEnabled = isSignInEnabled
        self.hasOAuthClientId = hasOAuthClientId
        self.googleAppId = googleAppId
        self.encodedAppScheme = encodedAppScheme
        self.clientId = clientId
        self.reversedClientId = reversedClientId
        self.hasCallbackURLSchemeConfigured = hasCallbackURLSchemeConfigured
    }

    /// Tóm tắt trạng thái cấu hình an toàn (không chứa khóa bí mật)
    public var diagnosticMessage: String {
        guard isPlistFound else {
            return "Chưa tìm thấy tệp GoogleService-Info.plist trong Bundle."
        }
        if !isBundleIdMatched {
            return "Cảnh báo: BUNDLE_ID trong GoogleService-Info.plist (\(plistBundleId)) không khớp với Bundle ID của ứng dụng (\(expectedBundleId))."
        }
        if !isSignInEnabled {
            return "IS_SIGNIN_ENABLED đang tắt trong GoogleService-Info.plist."
        }
        if !hasOAuthClientId && googleAppId == nil {
            return "BUNDLE_ID (\(plistBundleId)) và PROJECT_ID (\(projectId)) đã khớp nhưng thiếu GOOGLE_APP_ID / CLIENT_ID."
        }
        return "Đã kết nối Firebase Auth & Google OAuth cho dự án \(projectId) (\(plistBundleId))."
    }
}

/// Thông số runtime dùng nội bộ cho phiên xác thực OAuth với Firebase Identity Toolkit
internal struct FirebaseOAuthRuntimeConfig: Sendable {
    let apiKey: String
    let projectId: String
    let bundleId: String
    let googleAppId: String
    let encodedAppScheme: String
    let clientId: String?
    let reversedClientId: String?
}

/// Dịch vụ kiểm tra cấu hình Firebase (`GoogleService-Info.plist`) và OAuth URL Scheme
public final class FirebaseAuthConfigService: @unchecked Sendable {
    public static let shared = FirebaseAuthConfigService()
    public static let expectedAppBundleId = "com.edupetal.app"

    private let fileManager = FileManager.default

    public init() {}

    /// Kiểm tra tệp `GoogleService-Info.plist` từ Bundle chính hoặc đường dẫn tùy chỉnh (phục vụ kiểm thử)
    public func inspectConfiguration(customPlistURL: URL? = nil) -> FirebaseConfigInspectionResult {
        let resolvedURL = customPlistURL ?? locatePlistURL()

        guard let url = resolvedURL,
              fileManager.fileExists(atPath: url.path),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return FirebaseConfigInspectionResult(
                isPlistFound: false,
                projectId: "",
                plistBundleId: "",
                expectedBundleId: Self.expectedAppBundleId,
                isBundleIdMatched: false,
                isSignInEnabled: false,
                hasOAuthClientId: false,
                hasCallbackURLSchemeConfigured: checkURLSchemeConfigured(reversedClientId: nil, encodedAppScheme: nil)
            )
        }

        let plistBundleId = (dict["BUNDLE_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectId = (dict["PROJECT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isSignInEnabled = (dict["IS_SIGNIN_ENABLED"] as? Bool) ?? false

        let rawGoogleAppId = (dict["GOOGLE_APP_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validGoogleAppId = (rawGoogleAppId?.isEmpty == false && rawGoogleAppId?.contains("REPLACE_WITH") == false) ? rawGoogleAppId : nil
        let encodedScheme = validGoogleAppId.map { "app-\($0.replacingOccurrences(of: ":", with: "-"))" }

        let rawClientId = (dict["CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawReversedClientId = (dict["REVERSED_CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let validClientId = (rawClientId?.isEmpty == false && rawClientId?.contains("REPLACE_WITH") == false) ? rawClientId : nil
        let validReversedId = (rawReversedClientId?.isEmpty == false && rawReversedClientId?.contains("REPLACE_WITH") == false) ? rawReversedClientId : nil

        let isBundleMatched = (plistBundleId == Self.expectedAppBundleId)
        let hasOAuth = (validClientId != nil && validReversedId != nil) || (validGoogleAppId != nil && isSignInEnabled)
        let hasURLScheme = checkURLSchemeConfigured(reversedClientId: validReversedId, encodedAppScheme: encodedScheme)

        return FirebaseConfigInspectionResult(
            isPlistFound: true,
            projectId: projectId,
            plistBundleId: plistBundleId,
            expectedBundleId: Self.expectedAppBundleId,
            isBundleIdMatched: isBundleMatched,
            isSignInEnabled: isSignInEnabled,
            hasOAuthClientId: hasOAuth,
            googleAppId: validGoogleAppId,
            encodedAppScheme: encodedScheme,
            clientId: validClientId,
            reversedClientId: validReversedId,
            hasCallbackURLSchemeConfigured: hasURLScheme
        )
    }

    /// Đọc thông số runtime chỉ dùng trong bộ nhớ để gọi Google OAuth qua Firebase Identity Toolkit (Không ghi log)
    internal func loadRuntimeOAuthConfig(customPlistURL: URL? = nil) -> FirebaseOAuthRuntimeConfig? {
        guard let url = customPlistURL ?? locatePlistURL(),
              fileManager.fileExists(atPath: url.path),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }

        let apiKey = (dict["API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectId = (dict["PROJECT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleId = (dict["BUNDLE_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let googleAppId = (dict["GOOGLE_APP_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty, !apiKey.contains("REPLACE_WITH"),
              !projectId.isEmpty, !bundleId.isEmpty, !googleAppId.isEmpty else {
            return nil
        }

        let encodedScheme = "app-\(googleAppId.replacingOccurrences(of: ":", with: "-"))"
        let rawClientId = (dict["CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawReversedId = (dict["REVERSED_CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return FirebaseOAuthRuntimeConfig(
            apiKey: apiKey,
            projectId: projectId,
            bundleId: bundleId,
            googleAppId: googleAppId,
            encodedAppScheme: encodedScheme,
            clientId: (rawClientId?.isEmpty == false && rawClientId?.contains("REPLACE_WITH") == false) ? rawClientId : nil,
            reversedClientId: (rawReversedId?.isEmpty == false && rawReversedId?.contains("REPLACE_WITH") == false) ? rawReversedId : nil
        )
    }

    private func locatePlistURL() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") {
            return bundleURL
        }
        // Fallback cho môi trường chạy Swift Package Test (`swift test`)
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let appHostPlist = cwd.appendingPathComponent("AppHost/GoogleService-Info.plist")
        if fileManager.fileExists(atPath: appHostPlist.path) {
            return appHostPlist
        }
        let examplePlist = cwd.appendingPathComponent("AppHost/GoogleService-Info.plist.example")
        if fileManager.fileExists(atPath: examplePlist.path) {
            return examplePlist
        }
        return nil
    }

    private func checkURLSchemeConfigured(reversedClientId: String?, encodedAppScheme: String?) -> Bool {
        guard let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else {
            // Khi chạy trong SPM CLI test runner không có Info.plist của AppHost, kiểm tra file AppHost/Info.plist
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            let infoPlistURL = cwd.appendingPathComponent("AppHost/Info.plist")
            if let dict = NSDictionary(contentsOf: infoPlistURL) as? [String: Any],
               let types = dict["CFBundleURLTypes"] as? [[String: Any]] {
                return containsExpectedScheme(in: types, reversedClientId: reversedClientId, encodedAppScheme: encodedAppScheme)
            }
            return false
        }
        return containsExpectedScheme(in: urlTypes, reversedClientId: reversedClientId, encodedAppScheme: encodedAppScheme)
    }

    private func containsExpectedScheme(in urlTypes: [[String: Any]], reversedClientId: String?, encodedAppScheme: String?) -> Bool {
        let allSchemes = urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        if let scheme = encodedAppScheme, !scheme.isEmpty, allSchemes.contains(scheme) {
            return true
        }
        if let rev = reversedClientId, !rev.isEmpty {
            return allSchemes.contains(rev) || allSchemes.contains(Self.expectedAppBundleId)
        }
        return allSchemes.contains(Self.expectedAppBundleId) || allSchemes.contains(where: { $0.hasPrefix("com.googleusercontent.apps.") })
    }
}

