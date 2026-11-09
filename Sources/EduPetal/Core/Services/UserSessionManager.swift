import Foundation
import Observation
import CryptoKit
import SwiftData
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Loại nhà cung cấp xác thực (Tách biệt định danh theo từng provider, tuyệt đối không tự gộp theo email)
public enum AuthProviderType: String, Codable, Sendable, Equatable {
    case apple = "apple"
    case google = "google"
    case email = "email"
    case guestIsolated = "guest"

    public var displayName: String {
        switch self {
        case .apple:
            return "Apple ID"
        case .google:
            return "Google"
        case .email:
            return "Email & Mật khẩu"
        case .guestIsolated:
            return "Khách"
        }
    }
}

/// Thông tin tài khoản người dùng đang đăng nhập
public struct AuthenticatedUser: Codable, Sendable, Equatable, Identifiable {
    /// Định danh duy nhất phân vùng theo provider (ví dụ: `google_<uid>`, `apple_<sub_id>`, `email_<uid>`)
    public let userId: String
    public let provider: AuthProviderType
    public let email: String
    public var displayName: String
    public var photoURL: String?
    public let signedInAt: Date

    public var id: String { userId }

    public var isGuest: Bool {
        provider == .guestIsolated
    }

    /// Chuỗi hiển thị email đã che một phần (chuẩn App Store tương tự SnapSpend)
    public var maskedIdentifier: String {
        if isGuest {
            return "Chế độ Khách (Dữ liệu trên thiết bị)"
        }
        guard !email.isEmpty else {
            return provider.displayName
        }
        let parts = email.split(separator: "@")
        guard parts.count == 2 else { return email }
        let name = String(parts[0])
        let domain = String(parts[1])
        let maskedName = name.count <= 2
            ? "\(name.prefix(1))***"
            : "\(name.prefix(1))***\(name.suffix(1))"
        return "\(provider.displayName): \(maskedName)@\(domain)"
    }

    public init(
        userId: String,
        provider: AuthProviderType,
        email: String,
        displayName: String,
        photoURL: String? = nil,
        signedInAt: Date = Date()
    ) {
        self.userId = userId
        self.provider = provider
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.signedInAt = signedInAt
    }

    public var initials: String {
        let words = displayName.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words.first?.prefix(1) ?? ""
            let last = words.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

/// Ngữ cảnh phiên làm việc dùng để bảo vệ các tác vụ bất đồng bộ (Import PDF, xử lý ảnh, tạo PDF, lưu nháp)
public struct SessionTaskContext: Sendable, Equatable {
    public let ownerId: String
    public let sessionToken: UUID

    public init(ownerId: String, sessionToken: UUID) {
        self.ownerId = ownerId
        self.sessionToken = sessionToken
    }
}

/// Các lỗi vi phạm cô lập dữ liệu và phiên người dùng
public enum SessionIsolationError: Error, LocalizedError, Equatable {
    case unauthorizedRecordAccess(ownerId: String, currentUserId: String)
    case unauthorizedFileAccess(requestedOwner: String, activeOwner: String)
    case sessionChangedDuringAsyncTask(expectedOwner: String, currentOwner: String)
    case unownedLegacyDataAccessDenied
    case invalidCredentials(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorizedRecordAccess:
            return "Từ chối truy cập: Dữ liệu này thuộc về một tài khoản khác."
        case .unauthorizedFileAccess:
            return "Từ chối mở hoặc sử dụng tài liệu: Tệp thuộc quyền sở hữu của tài khoản khác."
        case .sessionChangedDuringAsyncTask:
            return "Tác vụ đã bị hủy do phiên đăng nhập hoặc tài khoản người dùng đã thay đổi."
        case .unownedLegacyDataAccessDenied:
            return "Dữ liệu cũ chưa có chủ sở hữu không được phép truy cập tự động khi chưa xác nhận chuyển đổi."
        case .invalidCredentials(let reason):
            return reason
        }
    }
}

/// Quản lý Phiên đăng nhập (Google / Apple) và Cô lập Dữ liệu & Tài liệu theo User (Mục 8 & 9 của `/duan`)
/// Thiết kế an toàn: Không khởi tạo vòng lặp giữa các singleton, không tự chuyển sang khách khi đăng xuất/lỗi.
@Observable
public final class UserSessionManager: @unchecked Sendable {
    public static let shared = UserSessionManager()

    /// Owner ID mặc định khi chạy các bài test đơn vị độc lập không qua màn hình đăng nhập
    public static let defaultLocalOwnerId = "local_default_owner"

    private static let activeSessionKey = "EduPetal_ActiveAuthenticatedUser_V1"
    private static let activeTokenKey = "EduPetal_ActiveSessionToken_V1"
    private static let knownGoogleAccountsKey = "EduPetal_KnownGoogleAccounts_V1"
    private static let knownAppleAccountsKey = "EduPetal_KnownAppleAccounts_V1"
    private static let appleCachedProfilesKey = "EduPetal_AppleCachedProfiles_V1"
    private static let registeredEmailAccountsKey = "EduPetal_RegisteredEmailAccounts_V1"

    private struct CachedAppleProfile: Codable, Sendable {
        let email: String
        let displayName: String
    }

    private struct RegisteredEmailRecord: Codable, Sendable {
        let userId: String
        let fullName: String
        let email: String
        let passwordHash: String
        let createdAt: Date
    }

    private struct ThreadSafeSessionSnapshot: Sendable {
        var currentUser: AuthenticatedUser? = nil
        var currentSessionToken: UUID = UUID()
        var fallbackOwnerId: String = UserSessionManager.defaultLocalOwnerId
        var currentAppleRawNonce: String? = nil
    }

    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private let lock = NSLock()
    @ObservationIgnored
    private var _snapshot = ThreadSafeSessionSnapshot()

    /// Người dùng đang đăng nhập hiện tại (`nil` nghĩa là đang ở màn hình Đăng nhập, tuyệt đối không tự vào Guest)
    public private(set) var currentUser: AuthenticatedUser?
    /// Mã phiên duy nhất cho mỗi lần đăng nhập (tự động đổi mới khi đăng xuất hoặc chuyển tài khoản)
    public private(set) var currentSessionToken: UUID
    /// Bộ đếm thế hệ phiên giúp SwiftUI hủy sạch mọi sheet/preview/ViewModel của phiên cũ ngay lập tức
    public private(set) var sessionGeneration: Int = 0

    public var isAuthenticating: Bool = false
    public var authErrorMessage: String? = nil

    /// Danh sách tài khoản Google đã từng đăng nhập trên thiết bị này (giúp chuyển nhanh tài khoản giống Google Account Chooser)
    public private(set) var savedGoogleAccounts: [AuthenticatedUser] = []

    /// Danh sách tài khoản Apple / iOS đã từng đăng nhập trên thiết bị này
    public private(set) var savedAppleAccounts: [AuthenticatedUser] = []

    public init(userDefaults: UserDefaults = .standard, autoRestore: Bool = true) {
        self.userDefaults = userDefaults
        let initialToken = UUID()
        self.currentSessionToken = initialToken
        self._snapshot = ThreadSafeSessionSnapshot(
            currentUser: nil,
            currentSessionToken: initialToken,
            fallbackOwnerId: Self.defaultLocalOwnerId,
            currentAppleRawNonce: nil
        )
        self.savedGoogleAccounts = Self.loadAccountList(from: userDefaults, key: Self.knownGoogleAccountsKey)
        let loadedApple = Self.loadAccountList(from: userDefaults, key: Self.knownAppleAccountsKey)
            .filter { !Self.isLegacyDemoAccount($0) }
        self.savedAppleAccounts = loadedApple
        Self.saveAccountList(loadedApple, to: userDefaults, key: Self.knownAppleAccountsKey)
        if autoRestore {
            self.restoreSession()
        }
    }

    /// Kiểm tra và loại bỏ tài khoản Apple demo cũ (`appleid@icloud.com` / `apple_ios_...`)
    private static func isLegacyDemoAccount(_ user: AuthenticatedUser) -> Bool {
        let lowerEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return user.userId.hasPrefix("apple_ios_") || lowerEmail == "appleid@icloud.com"
    }

    /// Định danh chủ sở hữu đang hoạt động (dùng để phân vùng thư mục file, SwiftData và kiểm tra quyền sở hữu)
    /// Đọc từ `_snapshot` (`@ObservationIgnored`) để không bao giờ gây khóa chéo (AB-BA deadlock) với `ObservationRegistrar` của SwiftUI.
    public var currentOwnerId: String {
        lock.lock()
        let user = _snapshot.currentUser
        let fallback = _snapshot.fallbackOwnerId
        lock.unlock()
        if let user {
            return user.userId
        }
        return fallback
    }

    /// Kiểm tra xem có phiên người dùng thực sự đã đăng nhập hay chưa.
    /// Không giữ `NSLock` khi đọc thuộc tính `@Observable` `currentUser` để tránh deadlock `0x8BADF00D` với `ObservationCenter._MovableLock`.
    public var isAuthenticated: Bool {
        currentUser != nil
    }

    // MARK: - 1. Khôi phục phiên, Đăng nhập Google & Đăng xuất

    /// Khôi phục phiên đăng nhập từ lần sử dụng trước (nếu người dùng chưa đăng xuất)
    @discardableResult
    public func restoreSession() -> AuthenticatedUser? {
        guard let data = userDefaults.data(forKey: Self.activeSessionKey),
              let restoredUser = try? JSONDecoder().decode(AuthenticatedUser.self, from: data),
              !Self.isLegacyDemoAccount(restoredUser) else {
            userDefaults.removeObject(forKey: Self.activeSessionKey)
            userDefaults.removeObject(forKey: Self.activeTokenKey)
            lock.lock()
            _snapshot.currentUser = nil
            lock.unlock()
            self.currentUser = nil
            return nil
        }

        let resolvedToken: UUID
        if let tokenStr = userDefaults.string(forKey: Self.activeTokenKey),
           let savedToken = UUID(uuidString: tokenStr) {
            resolvedToken = savedToken
        } else {
            let newToken = UUID()
            resolvedToken = newToken
            userDefaults.set(newToken.uuidString, forKey: Self.activeTokenKey)
        }

        lock.lock()
        _snapshot.currentUser = restoredUser
        _snapshot.currentSessionToken = resolvedToken
        lock.unlock()

        self.currentSessionToken = resolvedToken
        self.currentUser = restoredUser
        return restoredUser
    }

    /// Đăng nhập bằng tài khoản Google
    /// - Tạo định danh `google_<uid>` tách biệt hoàn toàn với mọi tài khoản Apple hay tài khoản Google khác
    /// - Không bao giờ tự gộp dữ liệu chỉ vì trùng email với provider khác
    @MainActor
    @discardableResult
    public func signInWithGoogle(
        email: String,
        displayName: String,
        googleSubjectId: String? = nil,
        photoURL: String? = nil
    ) async throws -> AuthenticatedUser {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty, cleanEmail.contains("@"), cleanEmail.contains(".") else {
            let err = SessionIsolationError.invalidCredentials(reason: "Vui lòng nhập địa chỉ email Google hợp lệ (ví dụ: giaovien@gmail.com).")
            self.authErrorMessage = err.localizedDescription
            throw err
        }

        isAuthenticating = true
        authErrorMessage = nil
        defer { isAuthenticating = false }

        // Nếu đang có phiên của tài khoản khác, thực hiện dọn dẹp cache/thông báo/file tạm của phiên cũ trước khi chuyển
        let previousOwnerId = currentOwnerId
        let subComponent: String
        if let sub = googleSubjectId?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            subComponent = Self.sanitizeIdentifier(sub)
        } else {
            subComponent = Self.deterministicHash(of: "google:\(cleanEmail)")
        }

        let googleUserId = "google_\(subComponent)"
        let resolvedName = cleanName.isEmpty
            ? String(cleanEmail.split(separator: "@").first ?? "Giáo viên")
            : cleanName

        let newUser = AuthenticatedUser(
            userId: googleUserId,
            provider: .google,
            email: cleanEmail,
            displayName: resolvedName,
            photoURL: photoURL,
            signedInAt: Date()
        )

        if previousOwnerId != googleUserId {
            await performSessionTransitionCleanup()
        }

        activateSession(for: newUser)
        rememberGoogleAccount(newUser)

        // Khởi tạo thư mục phân vùng riêng cho user này
        _ = userRootDirectoryURL(for: googleUserId)
        return newUser
    }

    /// Đăng nhập bằng Apple (Sign in with Apple / iOS):
    /// - Apple chỉ trả `email` và `fullName` ở lần đăng nhập đầu tiên, các lần sau chỉ trả `userIdentifier`
    /// - Hàm này tự động lưu bền vững `(email, displayName)` theo `appleUserIdentifier` ở lần đầu và tự khôi phục ở các lần đăng nhập sau
    /// - Tạo định danh `apple_<id>` tách biệt tuyệt đối với `google_<id>` (không bao giờ tự gộp dù trùng email)
    @MainActor
    @discardableResult
    public func signInWithApple(
        appleUserIdentifier: String,
        email: String? = nil,
        displayName: String? = nil
    ) async throws -> AuthenticatedUser {
        let trimmedId = appleUserIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            let err = SessionIsolationError.invalidCredentials(reason: "Không nhận được mã định danh Apple ID hợp lệ từ iOS.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }

        isAuthenticating = true
        authErrorMessage = nil
        defer { isAuthenticating = false }

        let previousOwnerId = currentOwnerId
        let subComponent = Self.sanitizeIdentifier(trimmedId)
        let appleUserId = "apple_\(subComponent)"

        // Khôi phục hoặc lưu mới hồ sơ (email, displayName) của Apple ID này
        let cachedProfile = loadCachedAppleProfile(for: subComponent)
        let cleanEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedEmail: String
        if !cleanEmail.isEmpty {
            resolvedEmail = cleanEmail
        } else if let cached = cachedProfile, !cached.email.isEmpty {
            resolvedEmail = cached.email
        } else {
            resolvedEmail = "\(subComponent.prefix(10))@privaterelay.appleid.com"
        }

        let resolvedName: String
        if !cleanName.isEmpty {
            resolvedName = cleanName
        } else if let cached = cachedProfile, !cached.displayName.isEmpty {
            resolvedName = cached.displayName
        } else {
            let prefix = resolvedEmail.split(separator: "@").first.map(String.init) ?? "Giáo viên"
            resolvedName = prefix.isEmpty ? "Giáo viên Apple" : prefix
        }

        saveCachedAppleProfile(
            CachedAppleProfile(email: resolvedEmail, displayName: resolvedName),
            for: subComponent
        )

        let newUser = AuthenticatedUser(
            userId: appleUserId,
            provider: .apple,
            email: resolvedEmail,
            displayName: resolvedName,
            photoURL: nil,
            signedInAt: Date()
        )

        if previousOwnerId != appleUserId {
            await performSessionTransitionCleanup()
        }

        activateSession(for: newUser)
        rememberAppleAccount(newUser)

        _ = userRootDirectoryURL(for: appleUserId)
        return newUser
    }

    /// Khởi tạo mã Nonce mật mã (SHA-256) cho `SignInWithAppleButton` (tương tự `SnapSpend`)
    public func prepareAppleSignInNonce() -> String {
        let rawNonce = Self.randomNonceString()
        lock.lock()
        _snapshot.currentAppleRawNonce = rawNonce
        lock.unlock()
        let digest = SHA256.hash(data: Data(rawNonce.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Hoàn tất đăng nhập từ `SignInWithAppleButton` (đổi token qua Firebase `accounts:signInWithIdp` nếu có mạng và lưu hồ sơ bền vững)
    @MainActor
    @discardableResult
    public func handleAppleSignInCompletion(
        userIdentifier: String,
        email: String?,
        fullName: PersonNameComponents?,
        identityTokenData: Data? = nil
    ) async throws -> AuthenticatedUser {
        var resolvedFullName: String? = nil
        if let fullName = fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty {
                resolvedFullName = formatted
            } else {
                let parts = [fullName.familyName, fullName.givenName].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty {
                    resolvedFullName = parts.joined(separator: " ")
                }
            }
        }

        var firebaseResolvedEmail: String? = email
        if let tokenData = identityTokenData,
           let idTokenString = String(data: tokenData, encoding: .utf8),
           let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig() {
            let rawNonce = readCurrentAppleRawNonce()
            if let fbEmail = try? await Self.exchangeAppleTokenWithFirebase(
                idTokenString: idTokenString,
                rawNonce: rawNonce,
                displayName: resolvedFullName,
                apiKey: runtimeConfig.apiKey
            ), !fbEmail.isEmpty {
                firebaseResolvedEmail = fbEmail
            }
        }

        return try await signInWithApple(
            appleUserIdentifier: userIdentifier,
            email: firebaseResolvedEmail,
            displayName: resolvedFullName
        )
    }

    private func readCurrentAppleRawNonce() -> String? {
        lock.lock()
        let nonce = _snapshot.currentAppleRawNonce
        lock.unlock()
        return nonce
    }

    // MARK: - 1B. Đăng ký / Đăng nhập bằng Email & Mật khẩu (Chuẩn Firebase Auth REST API + Local Fallback như SnapSpend)

    /// Đăng ký tài khoản mới bằng Email & Mật khẩu
    @MainActor
    @discardableResult
    public func signUpWithEmail(
        fullName: String,
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedName.isEmpty else {
            let err = SessionIsolationError.invalidCredentials(reason: "Vui lòng nhập họ và tên của bạn.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }
        guard Self.isValidEmailFormat(trimmedEmail) else {
            let err = SessionIsolationError.invalidCredentials(reason: "Địa chỉ Email không hợp lệ.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }
        guard password.count >= 6 else {
            let err = SessionIsolationError.invalidCredentials(reason: "Mật khẩu phải có ít nhất 6 ký tự.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }

        isAuthenticating = true
        authErrorMessage = nil
        defer { isAuthenticating = false }

        let previousOwnerId = currentOwnerId
        var resolvedSub = Self.deterministicHash(of: "email:\(trimmedEmail)")

        // 1. Thử đăng ký trên Firebase Auth REST API (nếu có kết nối mạng & cấu hình)
        if let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig() {
            do {
                let fbUid = try await Self.firebaseSignUpEmail(
                    email: trimmedEmail,
                    password: password,
                    displayName: trimmedName,
                    apiKey: runtimeConfig.apiKey
                )
                if !fbUid.isEmpty {
                    resolvedSub = Self.sanitizeIdentifier(fbUid)
                }
            } catch let SessionIsolationError.invalidCredentials(reason) {
                self.authErrorMessage = reason
                throw SessionIsolationError.invalidCredentials(reason: reason)
            } catch {
                // Nếu ngoại tuyến hoặc chưa bật provider trên console, lưu tài khoản cục bộ đã băm mật khẩu SHA-256
                var localRecords = loadRegisteredEmailRecords()
                if localRecords.contains(where: { $0.email == trimmedEmail }) {
                    let err = SessionIsolationError.invalidCredentials(reason: "Email này đã được đăng ký. Vui lòng chuyển sang tab Đăng nhập.")
                    self.authErrorMessage = err.localizedDescription
                    throw err
                }
                localRecords.append(
                    RegisteredEmailRecord(
                        userId: "email_\(resolvedSub)",
                        fullName: trimmedName,
                        email: trimmedEmail,
                        passwordHash: Self.sha256Hex(of: password),
                        createdAt: Date()
                    )
                )
                saveRegisteredEmailRecords(localRecords)
            }
        } else {
            var localRecords = loadRegisteredEmailRecords()
            if localRecords.contains(where: { $0.email == trimmedEmail }) {
                let err = SessionIsolationError.invalidCredentials(reason: "Email này đã được đăng ký. Vui lòng chuyển sang tab Đăng nhập.")
                self.authErrorMessage = err.localizedDescription
                throw err
            }
            localRecords.append(
                RegisteredEmailRecord(
                    userId: "email_\(resolvedSub)",
                    fullName: trimmedName,
                    email: trimmedEmail,
                    passwordHash: Self.sha256Hex(of: password),
                    createdAt: Date()
                )
            )
            saveRegisteredEmailRecords(localRecords)
        }

        // Lưu đồng bộ bản ghi local để hỗ trợ đăng nhập khi ngoại tuyến
        upsertLocalEmailRecord(
            userId: "email_\(resolvedSub)",
            fullName: trimmedName,
            email: trimmedEmail,
            password: password
        )

        let emailUserId = "email_\(resolvedSub)"
        let newUser = AuthenticatedUser(
            userId: emailUserId,
            provider: .email,
            email: trimmedEmail,
            displayName: trimmedName,
            photoURL: nil,
            signedInAt: Date()
        )

        if previousOwnerId != emailUserId {
            await performSessionTransitionCleanup()
        }

        activateSession(for: newUser)
        _ = userRootDirectoryURL(for: emailUserId)
        return newUser
    }

    /// Đăng nhập bằng Email & Mật khẩu
    @MainActor
    @discardableResult
    public func signInWithEmail(
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard Self.isValidEmailFormat(trimmedEmail) else {
            let err = SessionIsolationError.invalidCredentials(reason: "Địa chỉ Email không hợp lệ.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }
        guard !password.isEmpty else {
            let err = SessionIsolationError.invalidCredentials(reason: "Vui lòng nhập mật khẩu.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }

        isAuthenticating = true
        authErrorMessage = nil
        defer { isAuthenticating = false }

        let previousOwnerId = currentOwnerId
        let localRecords = loadRegisteredEmailRecords()
        let passwordHash = Self.sha256Hex(of: password)

        // 1. Thử xác thực qua Firebase Auth REST API trước
        if let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig() {
            do {
                let fbResult = try await Self.firebaseSignInEmail(
                    email: trimmedEmail,
                    password: password,
                    apiKey: runtimeConfig.apiKey
                )
                let existingRecord = localRecords.first(where: { $0.email == trimmedEmail })
                let sub = Self.sanitizeIdentifier(fbResult.localId.isEmpty ? Self.deterministicHash(of: "email:\(trimmedEmail)") : fbResult.localId)
                let emailUserId = existingRecord?.userId ?? "email_\(sub)"
                let resolvedName = fbResult.displayName.isEmpty
                    ? (existingRecord?.fullName ?? String(trimmedEmail.split(separator: "@").first ?? "Giáo viên"))
                    : fbResult.displayName

                upsertLocalEmailRecord(
                    userId: emailUserId,
                    fullName: resolvedName,
                    email: trimmedEmail,
                    password: password
                )

                let newUser = AuthenticatedUser(
                    userId: emailUserId,
                    provider: .email,
                    email: trimmedEmail,
                    displayName: resolvedName,
                    photoURL: nil,
                    signedInAt: Date()
                )

                if previousOwnerId != emailUserId {
                    await performSessionTransitionCleanup()
                }
                activateSession(for: newUser)
                _ = userRootDirectoryURL(for: emailUserId)
                return newUser
            } catch let SessionIsolationError.invalidCredentials(reason) {
                // Kiểm tra fallback local nếu tài khoản đã tạo khi ngoại tuyến
                if let matched = localRecords.first(where: { $0.email == trimmedEmail && $0.passwordHash == passwordHash }) {
                    let newUser = AuthenticatedUser(
                        userId: matched.userId,
                        provider: .email,
                        email: matched.email,
                        displayName: matched.fullName,
                        photoURL: nil,
                        signedInAt: Date()
                    )
                    if previousOwnerId != matched.userId {
                        await performSessionTransitionCleanup()
                    }
                    activateSession(for: newUser)
                    _ = userRootDirectoryURL(for: matched.userId)
                    return newUser
                }
                self.authErrorMessage = reason
                throw SessionIsolationError.invalidCredentials(reason: reason)
            } catch {
                // Lỗi mạng -> kiểm tra bản ghi local
            }
        }

        // 2. Fallback kiểm tra bản ghi tài khoản cục bộ
        guard let record = localRecords.first(where: { $0.email == trimmedEmail }) else {
            let err = SessionIsolationError.invalidCredentials(reason: "Chưa tìm thấy tài khoản với Email này. Vui lòng kiểm tra lại hoặc chọn Tạo tài khoản.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }
        guard record.passwordHash == passwordHash else {
            let err = SessionIsolationError.invalidCredentials(reason: "Mật khẩu không chính xác. Vui lòng thử lại.")
            self.authErrorMessage = err.localizedDescription
            throw err
        }

        let newUser = AuthenticatedUser(
            userId: record.userId,
            provider: .email,
            email: record.email,
            displayName: record.fullName,
            photoURL: nil,
            signedInAt: Date()
        )

        if previousOwnerId != record.userId {
            await performSessionTransitionCleanup()
        }

        activateSession(for: newUser)
        _ = userRootDirectoryURL(for: record.userId)
        return newUser
    }

    /// Gửi email đặt lại mật khẩu qua Firebase Auth REST API (`accounts:sendOobCode`)
    public func sendPasswordResetEmail(to email: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmailFormat(trimmedEmail) else {
            throw SessionIsolationError.invalidCredentials(reason: "Vui lòng nhập địa chỉ Email hợp lệ trước khi bấm Quên mật khẩu.")
        }
        guard let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig(),
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(runtimeConfig.apiKey)") else {
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requestType": "PASSWORD_RESET",
            "email": trimmedEmail
        ])
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Chế độ "Dùng thử ngay không cần tài khoản" (Guest Mode — cô lập trong phân vùng `guest_local`)
    /// Lưu ý: Chỉ kích hoạt khi người dùng chủ động bấm nút "Dùng thử ngay không cần tài khoản", tuyệt đối không tự gọi khi đăng xuất hay hủy đăng nhập.
    @MainActor
    @discardableResult
    public func continueAsGuest() async -> AuthenticatedUser {
        let previousOwnerId = currentOwnerId
        let guestId = "guest_local"
        let guestUser = AuthenticatedUser(
            userId: guestId,
            provider: .guestIsolated,
            email: "",
            displayName: "Giáo viên (Khách)",
            photoURL: nil,
            signedInAt: Date()
        )

        if previousOwnerId != guestId {
            await performSessionTransitionCleanup()
        }

        activateSession(for: guestUser)
        _ = userRootDirectoryURL(for: guestId)
        return guestUser
    }

    /// Xóa tài khoản hiện tại và toàn bộ dữ liệu thuộc phân vùng của tài khoản đó (Tuân thủ Apple App Store Guideline 5.1.1(v) tương tự SnapSpend)
    @MainActor
    public func deleteCurrentAccount() async {
        let ownerToDelete = currentOwnerId
        let emailToDelete = currentUser?.email ?? ""

        // Xóa thư mục phân vùng vật lý của tài khoản này
        let userDir = userRootDirectoryURL(for: ownerToDelete)
        try? FileManager.default.removeItem(at: userDir)

        // Xóa khỏi danh sách tài khoản lưu nhanh
        removeSavedGoogleAccount(userId: ownerToDelete)
        removeSavedAppleAccount(userId: ownerToDelete)

        if !emailToDelete.isEmpty {
            var records = loadRegisteredEmailRecords()
            records.removeAll { $0.email == emailToDelete || $0.userId == ownerToDelete }
            saveRegisteredEmailRecords(records)
        }

        await signOut()
    }

    /// Xử lý khi người dùng chủ động bấm "Hủy" trong quá trình đăng nhập Google/Apple
    /// Tuyệt đối không báo lỗi giả và không tự động chuyển sang tài khoản khách
    public func handleSignInCancelled() {
        isAuthenticating = false
        authErrorMessage = nil
    }

    /// Xử lý lỗi phát sinh trong quá trình đăng nhập
    public func handleSignInError(_ message: String) {
        isAuthenticating = false
        authErrorMessage = message
    }

    /// Đăng xuất tài khoản hiện tại:
    /// - Đổi mới `currentSessionToken` ngay lập tức để vô hiệu hóa mọi tác vụ bất đồng bộ đang chạy của phiên cũ
    /// - Xóa trạng thái hiển thị, bộ nhớ đệm (RAM cache) và tệp tạm của phiên cũ
    /// - Hủy các thông báo cục bộ của phiên cũ để không lộ tên học sinh/buổi học
    /// - Không xóa dữ liệu gốc hay tài liệu đã lưu bền vững trong vùng riêng của tài khoản
    /// - Không tự chuyển sang tài khoản khách
    @MainActor
    public func signOut() async {
        clearActiveSessionStateSynchronously()
        await performSessionTransitionCleanup()
    }

    private func clearActiveSessionStateSynchronously() {
        let newToken = UUID()
        lock.lock()
        _snapshot.currentSessionToken = newToken
        _snapshot.currentUser = nil
        _snapshot.fallbackOwnerId = Self.defaultLocalOwnerId
        userDefaults.removeObject(forKey: Self.activeSessionKey)
        userDefaults.removeObject(forKey: Self.activeTokenKey)
        lock.unlock()

        self.currentSessionToken = newToken
        self.currentUser = nil
        self.authErrorMessage = nil
        self.sessionGeneration += 1
    }

    /// Xóa một tài khoản khỏi danh sách gợi ý đăng nhập nhanh trên thiết bị (không xóa dữ liệu gốc của tài khoản)
    public func removeSavedGoogleAccount(userId: String) {
        var updated = savedGoogleAccounts
        updated.removeAll { $0.userId == userId }
        savedGoogleAccounts = updated
        lock.lock()
        Self.saveAccountList(updated, to: userDefaults, key: Self.knownGoogleAccountsKey)
        lock.unlock()
    }

    public func removeSavedAppleAccount(userId: String) {
        var updated = savedAppleAccounts
        updated.removeAll { $0.userId == userId }
        savedAppleAccounts = updated
        lock.lock()
        Self.saveAccountList(updated, to: userDefaults, key: Self.knownAppleAccountsKey)
        lock.unlock()
    }

    // MARK: - 2. Bảo vệ Tác vụ Bất đồng bộ & Kiểm tra Quyền sở hữu (Ownership Guard)

    /// Chụp lại ngữ cảnh `(ownerId, sessionToken)` tại thời điểm bắt đầu một tác vụ bất đồng bộ
    public func captureSessionContext() -> SessionTaskContext {
        lock.lock()
        let owner = _snapshot.currentUser?.userId ?? _snapshot.fallbackOwnerId
        let token = _snapshot.currentSessionToken
        lock.unlock()
        return SessionTaskContext(ownerId: owner, sessionToken: token)
    }

    /// Kiểm tra trước khi lưu kết quả của tác vụ bất đồng bộ:
    /// Nếu người dùng đã đăng xuất hoặc chuyển sang tài khoản khác trong lúc tác vụ đang xử lý, ném lỗi ngay lập tức
    public func validateSessionContext(_ context: SessionTaskContext) throws {
        lock.lock()
        let activeOwner = _snapshot.currentUser?.userId ?? _snapshot.fallbackOwnerId
        let activeToken = _snapshot.currentSessionToken
        lock.unlock()

        guard activeOwner == context.ownerId && activeToken == context.sessionToken else {
            throw SessionIsolationError.sessionChangedDuringAsyncTask(
                expectedOwner: context.ownerId,
                currentOwner: activeOwner
            )
        }
    }

    /// Kiểm tra quyền sở hữu đối với một bản ghi dữ liệu (`ownerId`)
    public func verifyRecordOwnership(recordOwnerId: String, expectedOwnerId: String? = nil) throws {
        let activeOwner = expectedOwnerId ?? currentOwnerId
        if recordOwnerId.isEmpty {
            // Dữ liệu cũ chưa có ownerId không được phép tự động gán hoặc truy cập bởi tài khoản mới
            throw SessionIsolationError.unownedLegacyDataAccessDenied
        }
        guard recordOwnerId == activeOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: recordOwnerId,
                currentUserId: activeOwner
            )
        }
    }

    /// Trích xuất `ownerId` từ đường dẫn tương đối đã phân vùng (`"<ownerId>/<fileName>"`) và kiểm tra quyền sở hữu
    public func verifyAndExtractFileName(
        from relativePath: String,
        expectedOwnerId: String? = nil
    ) throws -> (ownerId: String, fileName: String) {
        let activeOwner = Self.sanitizeIdentifier(expectedOwnerId ?? currentOwnerId)
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionIsolationError.unauthorizedFileAccess(requestedOwner: "", activeOwner: activeOwner)
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 2 {
            let pathOwner = String(parts[0])
            let fileName = parts.dropFirst().joined(separator: "/")
            guard pathOwner == activeOwner else {
                throw SessionIsolationError.unauthorizedFileAccess(
                    requestedOwner: pathOwner,
                    activeOwner: activeOwner
                )
            }
            return (ownerId: pathOwner, fileName: fileName)
        } else {
            // Đường dẫn không có tiền tố ownerId (tệp cũ chưa có ownerId hoặc test mặc định)
            if activeOwner == Self.defaultLocalOwnerId {
                return (ownerId: activeOwner, fileName: trimmed)
            }
            throw SessionIsolationError.unownedLegacyDataAccessDenied
        }
    }

    // MARK: - 3. Phân vùng Thư mục & Cơ sở dữ liệu theo User

    /// Thư mục gốc riêng biệt của từng `ownerId` trong `Application Support/Users/<ownerId>`
    public func userRootDirectoryURL(for ownerId: String? = nil) -> URL {
        let resolvedOwner = Self.sanitizeIdentifier(ownerId ?? currentOwnerId)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(resolvedOwner, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Đường dẫn file SQLite / SwiftData riêng biệt cho từng `ownerId`
    public func userDatabaseURL(for ownerId: String? = nil) -> URL {
        let dbDir = userRootDirectoryURL(for: ownerId).appendingPathComponent("Database", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dbDir.path) {
            try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        }
        return dbDir.appendingPathComponent("EduPetal.store")
    }

    /// Khởi tạo `ModelContainer` SwiftData được cô lập vật lý theo từng `ownerId`
    @MainActor
    public func makeIsolatedModelContainer(for ownerId: String? = nil) throws -> ModelContainer {
        let storeURL = userDatabaseURL(for: ownerId)
        let schema = Schema(EduPetalSchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Hỗ trợ Kiểm thử (Test Helpers)

    /// Thiết lập trực tiếp ngữ cảnh phiên (dùng cho cả Đăng nhập Apple ở Tính năng 10 và Unit Tests)
    /// Tuyệt đối không giữ `lock` khi ghi các thuộc tính `@Observable` để tránh khóa chéo `0x8BADF00D`.
    public func activateSession(for user: AuthenticatedUser) {
        let newToken = UUID()
        lock.lock()
        _snapshot.currentUser = user
        _snapshot.currentSessionToken = newToken
        if let encoded = try? JSONEncoder().encode(user) {
            userDefaults.set(encoded, forKey: Self.activeSessionKey)
            userDefaults.set(newToken.uuidString, forKey: Self.activeTokenKey)
        }
        lock.unlock()

        self.currentSessionToken = newToken
        self.authErrorMessage = nil
        self.sessionGeneration += 1
        self.currentUser = user
    }

    /// Đặt lại về trạng thái mặc định cho các bài unit test không kiểm thử đăng nhập
    public func resetForTesting(ownerId: String = UserSessionManager.defaultLocalOwnerId) {
        let newToken = UUID()
        lock.lock()
        _snapshot.currentUser = nil
        _snapshot.fallbackOwnerId = ownerId
        _snapshot.currentSessionToken = newToken
        userDefaults.removeObject(forKey: Self.activeSessionKey)
        userDefaults.removeObject(forKey: Self.activeTokenKey)
        lock.unlock()

        self.currentUser = nil
        self.currentSessionToken = newToken
        self.authErrorMessage = nil
        self.isAuthenticating = false
    }

    // MARK: - Private Helpers

    private func performSessionTransitionCleanup() async {
        // 1. Xóa RAM cache của ảnh minh chứng và avatar
        PhotoStorageService.shared.clearMemoryCache()
        AvatarStorageService.shared.clearMemoryCache()

        // 2. Hủy toàn bộ thông báo nhắc buổi dạy của phiên cũ để không lộ tên học sinh/lớp học sang tài khoản mới
        await LocalNotificationService.shared.cancelAllUserNotificationsOnSessionChange()
    }

    private func rememberGoogleAccount(_ user: AuthenticatedUser) {
        var updated = savedGoogleAccounts
        updated.removeAll { $0.userId == user.userId }
        updated.insert(user, at: 0)
        savedGoogleAccounts = updated

        lock.lock()
        Self.saveAccountList(updated, to: userDefaults, key: Self.knownGoogleAccountsKey)
        lock.unlock()
    }

    private func rememberAppleAccount(_ user: AuthenticatedUser) {
        var updated = savedAppleAccounts
        updated.removeAll { $0.userId == user.userId }
        updated.insert(user, at: 0)
        savedAppleAccounts = updated

        lock.lock()
        Self.saveAccountList(updated, to: userDefaults, key: Self.knownAppleAccountsKey)
        lock.unlock()
    }

    private func loadCachedAppleProfile(for subComponent: String) -> CachedAppleProfile? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = userDefaults.data(forKey: Self.appleCachedProfilesKey),
              let dict = try? JSONDecoder().decode([String: CachedAppleProfile].self, from: data) else {
            return nil
        }
        return dict[subComponent]
    }

    private func saveCachedAppleProfile(_ profile: CachedAppleProfile, for subComponent: String) {
        lock.lock()
        defer { lock.unlock() }
        var dict: [String: CachedAppleProfile] = [:]
        if let data = userDefaults.data(forKey: Self.appleCachedProfilesKey),
           let existing = try? JSONDecoder().decode([String: CachedAppleProfile].self, from: data) {
            dict = existing
        }
        dict[subComponent] = profile
        if let encoded = try? JSONEncoder().encode(dict) {
            userDefaults.set(encoded, forKey: Self.appleCachedProfilesKey)
        }
    }

    private static func loadAccountList(from defaults: UserDefaults, key: String) -> [AuthenticatedUser] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([AuthenticatedUser].self, from: data) else {
            return []
        }
        return list
    }

    private static func saveAccountList(_ list: [AuthenticatedUser], to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }

    public static func sanitizeIdentifier(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultLocalOwnerId }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned)
        return result.isEmpty ? defaultLocalOwnerId : result
    }

    public static func deterministicHash(of input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func loadRegisteredEmailRecords() -> [RegisteredEmailRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = userDefaults.data(forKey: Self.registeredEmailAccountsKey),
              let records = try? JSONDecoder().decode([RegisteredEmailRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func saveRegisteredEmailRecords(_ records: [RegisteredEmailRecord]) {
        lock.lock()
        defer { lock.unlock() }
        if let encoded = try? JSONEncoder().encode(records) {
            userDefaults.set(encoded, forKey: Self.registeredEmailAccountsKey)
        }
    }

    private func upsertLocalEmailRecord(userId: String, fullName: String, email: String, password: String) {
        var records = loadRegisteredEmailRecords()
        records.removeAll { $0.email == email || $0.userId == userId }
        records.append(
            RegisteredEmailRecord(
                userId: userId,
                fullName: fullName,
                email: email,
                passwordHash: Self.sha256Hex(of: password),
                createdAt: Date()
            )
        )
        saveRegisteredEmailRecords(records)
    }

    private static func isValidEmailFormat(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private static func sha256Hex(of input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func exchangeAppleTokenWithFirebase(
        idTokenString: String,
        rawNonce: String?,
        displayName: String?,
        apiKey: String
    ) async throws -> String? {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)") else {
            return nil
        }
        var postBody = "id_token=\(idTokenString)&providerId=apple.com"
        if let rawNonce = rawNonce, !rawNonce.isEmpty {
            postBody += "&nonce=\(rawNonce)"
        }
        let body: [String: Any] = [
            "postBody": postBody,
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let idToken = json["idToken"] as? String,
           let name = displayName, !name.isEmpty,
           let updateURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:update?key=\(apiKey)") {
            var updateReq = URLRequest(url: updateURL)
            updateReq.timeoutInterval = 15
            updateReq.httpMethod = "POST"
            updateReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            updateReq.httpBody = try? JSONSerialization.data(withJSONObject: [
                "idToken": idToken,
                "displayName": name,
                "returnSecureToken": false
            ])
            _ = try? await URLSession.shared.data(for: updateReq)
        }
        return json["email"] as? String
    }

    private static func firebaseSignUpEmail(
        email: String,
        password: String,
        displayName: String,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        if !(200...299).contains(http.statusCode) {
            if let errDict = json["error"] as? [String: Any],
               let msg = errDict["message"] as? String {
                if msg.contains("EMAIL_EXISTS") {
                    throw SessionIsolationError.invalidCredentials(reason: "Email này đã được đăng ký. Vui lòng chuyển sang tab Đăng nhập.")
                } else if msg.contains("INVALID_EMAIL") {
                    throw SessionIsolationError.invalidCredentials(reason: "Địa chỉ Email không hợp lệ.")
                } else if msg.contains("WEAK_PASSWORD") {
                    throw SessionIsolationError.invalidCredentials(reason: "Mật khẩu quá yếu (cần ít nhất 6 ký tự).")
                }
            }
            throw URLError(.cannotConnectToHost)
        }

        let localId = (json["localId"] as? String) ?? ""
        if let idToken = json["idToken"] as? String,
           !displayName.isEmpty,
           let updateURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:update?key=\(apiKey)") {
            var updateReq = URLRequest(url: updateURL)
            updateReq.timeoutInterval = 15
            updateReq.httpMethod = "POST"
            updateReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            updateReq.httpBody = try? JSONSerialization.data(withJSONObject: [
                "idToken": idToken,
                "displayName": displayName,
                "returnSecureToken": false
            ])
            _ = try? await URLSession.shared.data(for: updateReq)
        }
        return localId
    }

    private static func firebaseSignInEmail(
        email: String,
        password: String,
        apiKey: String
    ) async throws -> (localId: String, displayName: String) {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        if !(200...299).contains(http.statusCode) {
            if let errDict = json["error"] as? [String: Any],
               let msg = errDict["message"] as? String {
                if msg.contains("EMAIL_NOT_FOUND") {
                    throw SessionIsolationError.invalidCredentials(reason: "Chưa tìm thấy tài khoản với Email này. Vui lòng chọn Tạo tài khoản.")
                } else if msg.contains("INVALID_PASSWORD") || msg.contains("INVALID_LOGIN_CREDENTIALS") {
                    throw SessionIsolationError.invalidCredentials(reason: "Email hoặc mật khẩu không chính xác. Vui lòng thử lại.")
                } else if msg.contains("USER_DISABLED") {
                    throw SessionIsolationError.invalidCredentials(reason: "Tài khoản này đã bị vô hiệu hóa.")
                } else if msg.contains("TOO_MANY_ATTEMPTS_TRY_LATER") {
                    throw SessionIsolationError.invalidCredentials(reason: "Quá nhiều lần thử sai. Vui lòng thử lại sau ít phút.")
                }
            }
            throw URLError(.cannotConnectToHost)
        }

        let localId = (json["localId"] as? String) ?? ""
        let displayName = (json["displayName"] as? String) ?? ""
        return (localId: localId, displayName: displayName)
    }
}
