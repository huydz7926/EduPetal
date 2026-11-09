import Foundation
import CryptoKit
import AuthenticationServices
#if canImport(UIKit)
import UIKit
import WebKit
#endif

/// Kết quả trả về từ phiên xác thực OAuth của Google thông qua Firebase Identity Toolkit
public struct GoogleOAuthProfile: Sendable, Equatable {
    public let googleSubjectId: String
    public let email: String
    public let displayName: String
    public let photoURL: String?

    public init(
        googleSubjectId: String,
        email: String,
        displayName: String,
        photoURL: String? = nil
    ) {
        self.googleSubjectId = googleSubjectId
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }
}

public enum GoogleOAuthError: Error, LocalizedError, Equatable {
    case cancelledByUser
    case alreadyInProgress
    case missingFirebaseConfig
    case invalidHandlerURL
    case missingCallbackURL
    case stateMismatch
    case firebaseAuthError(String)
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelledByUser, .alreadyInProgress:
            return nil
        case .missingFirebaseConfig:
            return L(
                "Không tìm thấy cấu hình Firebase hợp lệ trong GoogleService-Info.plist.",
                "Missing valid Firebase configuration in GoogleService-Info.plist."
            )
        case .invalidHandlerURL:
            return L(
                "Không thể khởi tạo đường dẫn xác thực Google OAuth.",
                "Unable to initialize Google OAuth URL."
            )
        case .missingCallbackURL:
            return L(
                "Không nhận được phản hồi xác thực từ Google.",
                "Did not receive authentication callback from Google."
            )
        case .stateMismatch:
            return L(
                "Phiên xác thực không hợp lệ hoặc đã hết hạn (lệch mã state bảo mật). Vui lòng thử đăng nhập lại.",
                "Invalid or expired authentication session (OAuth state mismatch). Please sign in again."
            )
        case .firebaseAuthError(let msg):
            return L(
                "Xác thực Google không thành công: \(msg)",
                "Google authentication failed: \(msg)"
            )
        case .tokenExchangeFailed(let msg):
            return L(
                "Không thể xác minh tài khoản Google với Firebase Auth: \(msg)",
                "Failed to verify Google credential with Firebase Auth: \(msg)"
            )
        }
    }
}

/// Dịch vụ xác thực tài khoản Google thật trên iOS kết nối với Firebase Auth (`accounts:signInWithIdp`).
/// - Không mở trực tiếp trang web `/__/auth/handler?authType=signInWithRedirect` (nguyên nhân gây lỗi mất `window.sessionStorage`:
///   `"Unable to process request due to missing initial state"` khi Safari chuyển hướng qua lại với `accounts.google.com`).
/// - Hỗ trợ luồng chuẩn iOS OAuth 2.0 PKCE (`client_id` + `REVERSED_CLIENT_ID:/oauth2redirect` -> Google `id_token` -> Firebase Auth)
///   và luồng trực tiếp `accounts:createAuthUri` -> `accounts.google.com` -> kiểm tra `state` -> Firebase Auth `accounts:signInWithIdp`.
/// - Chặn gọi đăng nhập lặp/đồng thời, kiểm tra nghiêm ngặt tham số `state` chống giả mạo và chỉ tạo phiên khi Firebase Auth thành công.
@MainActor
public final class GoogleOAuthService: NSObject {
    public static let shared = GoogleOAuthService()

    private var isSignInInProgress: Bool = false
    private var activeWebSession: ASWebAuthenticationSession?
    private var pendingOpenURLHandler: ((URL) -> Bool)?
    #if canImport(UIKit)
    private var activeSheetController: GoogleOAuthWebSheetController?
    #endif

    public override init() {
        super.init()
    }

    /// Xử lý callback URL từ `.onOpenURL` của SwiftUI Scene nếu hệ điều hành chuyển hướng về custom scheme của ứng dụng
    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        if let handler = pendingOpenURLHandler {
            return handler(url)
        }
        return false
    }

    /// Thực hiện đăng nhập Google thật trên iOS và xác thực credential với Firebase Auth trước khi mở phiên `UserSessionManager`
    @discardableResult
    public func signInWithGoogleWebSession(
        sessionManager: UserSessionManager = .shared
    ) async throws -> AuthenticatedUser {
        // Chặn tạo nhiều phiên đăng nhập đồng thời khi người dùng bấm liên tiếp
        guard !isSignInInProgress else {
            throw GoogleOAuthError.alreadyInProgress
        }

        guard let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig() else {
            let err = GoogleOAuthError.missingFirebaseConfig
            sessionManager.handleSignInError(err.localizedDescription)
            throw err
        }

        isSignInInProgress = true
        sessionManager.isAuthenticating = true
        sessionManager.authErrorMessage = nil

        defer {
            isSignInInProgress = false
            pendingOpenURLHandler = nil
            activeWebSession = nil
            #if canImport(UIKit)
            activeSheetController = nil
            #endif
        }

        do {
            let profile: GoogleOAuthProfile

            // Nếu GoogleService-Info.plist có cấu hình iOS OAuth CLIENT_ID & REVERSED_CLIENT_ID riêng cho iOS Native:
            // chạy luồng chuẩn RFC 8252 PKCE -> đổi Google id_token -> xác thực với Firebase Auth (`postBody: id_token=...`)
            if let iosClientId = runtimeConfig.clientId,
               let reversedScheme = runtimeConfig.reversedClientId,
               !iosClientId.isEmpty,
               !reversedScheme.isEmpty {
                profile = try await performNativePKCEGoogleSignIn(
                    clientId: iosClientId,
                    reversedClientId: reversedScheme,
                    config: runtimeConfig
                )
            } else {
                // Khi GoogleService-Info.plist dùng cấu hình Firebase प्रोजेक्ट (`GOOGLE_APP_ID` + Web OAuth client của Firebase):
                // Lấy trực tiếp URL `accounts.google.com/o/oauth2/auth` kèm `state` & `sessionId` từ `accounts:createAuthUri`,
                // mở trực tiếp trang chọn tài khoản Google (không đi qua `/__/auth/handler` để tránh lỗi mất `sessionStorage`),
                // kiểm tra khớp `state` và xác thực mã `code` với Firebase Auth (`accounts:signInWithIdp`).
                let authSession = try await Self.createGoogleAuthURI(config: runtimeConfig)
                let callbackURL = try await presentDirectGoogleSignInSheet(
                    authURL: authSession.authURL,
                    config: runtimeConfig
                )

                try Self.verifyOAuthState(
                    expectedState: authSession.expectedState,
                    callbackURL: callbackURL
                )

                let extractedRequestURI = try Self.extractOAuthRequestURI(from: callbackURL)
                profile = try await Self.exchangeOAuthCodeWithFirebase(
                    requestURI: extractedRequestURI,
                    sessionId: authSession.sessionId,
                    config: runtimeConfig
                )
            }

            // Chỉ tạo phiên đăng nhập trong ứng dụng sau khi Firebase Auth đã xác thực thành công
            return try await sessionManager.signInWithGoogle(
                email: profile.email,
                displayName: profile.displayName,
                googleSubjectId: profile.googleSubjectId,
                photoURL: profile.photoURL
            )
        } catch GoogleOAuthError.cancelledByUser {
            sessionManager.handleSignInCancelled()
            throw GoogleOAuthError.cancelledByUser
        } catch GoogleOAuthError.alreadyInProgress {
            throw GoogleOAuthError.alreadyInProgress
        } catch {
            sessionManager.handleSignInError(error.localizedDescription)
            throw error
        }
    }

    // MARK: - 1. Luồng iOS OAuth 2.0 PKCE -> Google ID Token -> Firebase Auth (`accounts:signInWithIdp`)

    private func performNativePKCEGoogleSignIn(
        clientId: String,
        reversedClientId: String,
        config: FirebaseOAuthRuntimeConfig
    ) async throws -> GoogleOAuthProfile {
        let state = Self.generateRandomURLSafeString(byteCount: 24)
        let codeVerifier = Self.generateRandomURLSafeString(byteCount: 32)
        let codeChallenge = Self.generatePKCECodeChallenge(for: codeVerifier)
        let redirectURI = "\(reversedClientId):/oauth2redirect"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components?.url else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        let callbackURL = try await performASWebAuthSession(
            url: authURL,
            callbackScheme: reversedClientId
        )

        try Self.verifyOAuthState(expectedState: state, callbackURL: callbackURL)

        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = queryItems.first(where: { $0.name == "error" })?.value {
            if err.localizedCaseInsensitiveContains("access_denied") || err.localizedCaseInsensitiveContains("cancel") {
                throw GoogleOAuthError.cancelledByUser
            }
            throw GoogleOAuthError.firebaseAuthError(err)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GoogleOAuthError.missingCallbackURL
        }

        let googleTokens = try await Self.exchangeAuthorizationCodeForGoogleTokens(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI,
            clientId: clientId
        )

        return try await Self.exchangeGoogleIDTokenWithFirebase(
            idToken: googleTokens.idToken,
            accessToken: googleTokens.accessToken,
            config: config
        )
    }

    private func performASWebAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            var isResumed = false
            let resumeOnce: (Result<URL, Error>) -> Void = { [weak self] result in
                guard !isResumed else { return }
                isResumed = true
                self?.activeWebSession = nil
                self?.pendingOpenURLHandler = nil
                continuation.resume(with: result)
            }

            self.pendingOpenURLHandler = { incomingURL in
                guard incomingURL.scheme?.lowercased() == callbackScheme.lowercased() else {
                    return false
                }
                resumeOnce(.success(incomingURL))
                return true
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                Task { @MainActor in
                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin {
                        resumeOnce(.failure(GoogleOAuthError.cancelledByUser))
                        return
                    }
                    if let error = error {
                        resumeOnce(.failure(GoogleOAuthError.firebaseAuthError(error.localizedDescription)))
                        return
                    }
                    guard let callbackURL = callbackURL else {
                        resumeOnce(.failure(GoogleOAuthError.missingCallbackURL))
                        return
                    }
                    resumeOnce(.success(callbackURL))
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeWebSession = session

            if !session.start() {
                resumeOnce(.failure(GoogleOAuthError.invalidHandlerURL))
            }
        }
    }

    internal static func exchangeAuthorizationCodeForGoogleTokens(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        clientId: String
    ) async throws -> (idToken: String, accessToken: String?) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String,
              !idToken.isEmpty else {
            throw GoogleOAuthError.tokenExchangeFailed("Không nhận được id_token hợp lệ từ Google OAuth.")
        }

        let accessToken = json["access_token"] as? String
        return (idToken: idToken, accessToken: accessToken)
    }

    internal static func exchangeGoogleIDTokenWithFirebase(
        idToken: String,
        accessToken: String?,
        config: FirebaseOAuthRuntimeConfig
    ) async throws -> GoogleOAuthProfile {
        guard let endpointURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(config.apiKey)") else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        var postBody = "id_token=\(idToken)&providerId=google.com"
        if let accessToken, !accessToken.isEmpty {
            postBody += "&access_token=\(accessToken)"
        }

        let payload: [String: Any] = [
            "postBody": postBody,
            "requestUri": "http://localhost",
            "returnSecureToken": true,
            "returnIdpCredential": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleOAuthError.tokenExchangeFailed("Firebase Auth từ chối xác thực Google id_token.")
        }

        return try parseSignInWithIdpResponse(json)
    }

    // MARK: - 2. Luồng trực tiếp `accounts:createAuthUri` -> `accounts.google.com` -> Kiểm tra `state` -> Firebase Auth

    private func presentDirectGoogleSignInSheet(
        authURL: URL,
        config: FirebaseOAuthRuntimeConfig
    ) async throws -> URL {
        #if canImport(UIKit)
        guard let presenter = Self.topMostViewController() else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sheet = GoogleOAuthWebSheetController(
                authURL: authURL,
                firebaseHost: "\(config.projectId).firebaseapp.com",
                encodedAppScheme: config.encodedAppScheme
            ) { [weak self] result in
                Task { @MainActor in
                    self?.activeSheetController = nil
                    switch result {
                    case .success(let callbackURL):
                        continuation.resume(returning: callbackURL)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            let nav = UINavigationController(rootViewController: sheet)
            nav.modalPresentationStyle = .pageSheet
            if let presentation = nav.sheetPresentationController {
                presentation.detents = [.large()]
                presentation.prefersGrabberVisible = true
            }
            self.activeSheetController = sheet
            presenter.present(nav, animated: true)
        }
        #else
        throw GoogleOAuthError.invalidHandlerURL
        #endif
    }

    #if canImport(UIKit)
    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        let keyWindow = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first

        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
    #endif

    internal static func createGoogleAuthURI(
        config: FirebaseOAuthRuntimeConfig
    ) async throws -> (authURL: URL, sessionId: String, expectedState: String?) {
        guard let endpointURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=\(config.apiKey)") else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        let continueURI = "https://\(config.projectId).firebaseapp.com/__/auth/handler"
        let initialSessionId = generateSessionId()

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        let payload: [String: Any] = [
            "providerId": "google.com",
            "continueUri": continueURI,
            "authFlowType": "CODE_FLOW",
            "sessionId": initialSessionId,
            "customParameter": [
                "prompt": "select_account"
            ],
            "oauthScope": "email profile openid"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authUriString = json["authUri"] as? String,
              let authURL = URL(string: authUriString) else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        let returnedSessionId = (json["sessionId"] as? String) ?? initialSessionId
        let expectedState = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "state" })?
            .value

        return (authURL: authURL, sessionId: returnedSessionId, expectedState: expectedState)
    }

    // MARK: - Kiểm tra `state` chống giả mạo (CSRF State Validation)

    public static func verifyOAuthState(expectedState: String?, callbackURL: URL) throws {
        guard let expected = expectedState, !expected.isEmpty else {
            return
        }

        let outerItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

        // Nếu người dùng bấm Hủy trên trang Google (`error=access_denied`), cho phép bộ giải mã xử lý hủy trước
        if let err = outerItems.first(where: { $0.name == "error" || $0.name == "firebaseError" })?.value,
           !err.isEmpty {
            return
        }

        if let directState = outerItems.first(where: { $0.name == "state" })?.value {
            guard directState == expected else {
                throw GoogleOAuthError.stateMismatch
            }
            return
        }

        if let deepLinkStr = outerItems.first(where: { $0.name == "deep_link_id" })?.value,
           let deepComponents = URLComponents(string: deepLinkStr),
           let innerLink = deepComponents.queryItems?.first(where: { $0.name == "link" })?.value,
           let innerState = URLComponents(string: innerLink)?.queryItems?.first(where: { $0.name == "state" })?.value {
            guard innerState == expected else {
                throw GoogleOAuthError.stateMismatch
            }
            return
        }

        throw GoogleOAuthError.stateMismatch
    }

    // MARK: - URL Builders & Callback Parsers (Testable Pure Functions)

    internal static func generateSessionId() -> String {
        let digest = SHA256.hash(data: Data(UUID().uuidString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    internal static func generateRandomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    internal static func generatePKCECodeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    internal static func buildFirebaseOAuthHandlerURL(
        config: FirebaseOAuthRuntimeConfig,
        sessionId: String,
        eventId: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(config.projectId).firebaseapp.com"
        components.path = "/__/auth/handler"

        let customParamsJSON = #"{"prompt":"select_account"}"#

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: config.apiKey),
            URLQueryItem(name: "authType", value: "signInWithRedirect"),
            URLQueryItem(name: "ibi", value: config.bundleId),
            URLQueryItem(name: "appId", value: config.googleAppId),
            URLQueryItem(name: "providerId", value: "google.com"),
            URLQueryItem(name: "scopes", value: "email,profile,openid"),
            URLQueryItem(name: "eventId", value: eventId),
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "v", value: "2.20.9"),
            URLQueryItem(name: "customParameters", value: customParamsJSON)
        ]

        if let clientId = config.clientId, !clientId.isEmpty {
            queryItems.append(URLQueryItem(name: "clientId", value: clientId))
        }

        components.queryItems = queryItems
        return components.url
    }

    /// Giải mã `requestURI` từ URL callback trực tiếp (`https://<project>.firebaseapp.com/__/auth/handler?state=...&code=...`)
    /// hoặc từ `deep_link_id` -> `link` (`app-1-...://firebaseauth/link?deep_link_id=...`)
    public static func extractOAuthRequestURI(from callbackURL: URL) throws -> String {
        guard let outerComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.missingCallbackURL
        }

        let outerItems = outerComponents.queryItems ?? []

        // 1. Kiểm tra trường hợp lỗi OAuth hoặc lỗi Firebase trả trực tiếp
        if let oauthErr = outerItems.first(where: { $0.name == "error" })?.value {
            if oauthErr.localizedCaseInsensitiveContains("access_denied") ||
               oauthErr.localizedCaseInsensitiveContains("cancel") {
                throw GoogleOAuthError.cancelledByUser
            }
            let desc = outerItems.first(where: { $0.name == "error_description" })?.value ?? oauthErr
            throw GoogleOAuthError.firebaseAuthError(desc)
        }

        if let errStr = outerItems.first(where: { $0.name == "firebaseError" })?.value {
            if errStr.localizedCaseInsensitiveContains("user-cancelled") || errStr.localizedCaseInsensitiveContains("canceled") {
                throw GoogleOAuthError.cancelledByUser
            }
            throw GoogleOAuthError.firebaseAuthError(parseFirebaseErrorJSON(errStr))
        }

        // 2. Nếu URL là redirect trực tiếp từ Google về `https://<project>.firebaseapp.com/__/auth/handler?state=...&code=...`
        if let code = outerItems.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return callbackURL.absoluteString
        }

        // 3. Nếu URL được bọc trong `deep_link_id` từ custom scheme `app-1-...://firebaseauth/link`
        if let deepLinkStr = outerItems.first(where: { $0.name == "deep_link_id" })?.value,
           let deepComponents = URLComponents(string: deepLinkStr) {
            let deepItems = deepComponents.queryItems ?? []

            if let errStr = deepItems.first(where: { $0.name == "firebaseError" })?.value {
                if errStr.localizedCaseInsensitiveContains("user-cancelled") || errStr.localizedCaseInsensitiveContains("canceled") {
                    throw GoogleOAuthError.cancelledByUser
                }
                throw GoogleOAuthError.firebaseAuthError(parseFirebaseErrorJSON(errStr))
            }

            if let innerLink = deepItems.first(where: { $0.name == "link" })?.value, !innerLink.isEmpty {
                return innerLink
            }
            return deepLinkStr
        }

        if let directLink = outerItems.first(where: { $0.name == "link" })?.value, !directLink.isEmpty {
            return directLink
        }

        throw GoogleOAuthError.missingCallbackURL
    }

    private static func parseFirebaseErrorJSON(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = dict["message"] as? String ?? dict["code"] as? String {
            return message
        }
        return raw
    }

    /// Gọi Firebase Identity Toolkit `accounts:signInWithIdp` để đổi mã OAuth lấy thông tin tài khoản Google đã xác thực
    internal static func exchangeOAuthCodeWithFirebase(
        requestURI: String,
        sessionId: String,
        config: FirebaseOAuthRuntimeConfig
    ) async throws -> GoogleOAuthProfile {
        guard let endpointURL = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(config.apiKey)") else {
            throw GoogleOAuthError.invalidHandlerURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        let payload: [String: Any] = [
            "requestUri": requestURI,
            "sessionId": sessionId,
            "returnSecureToken": true,
            "returnIdpCredential": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleOAuthError.tokenExchangeFailed("Phản hồi mạng không hợp lệ.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errDict["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw GoogleOAuthError.tokenExchangeFailed(message)
            }
            throw GoogleOAuthError.tokenExchangeFailed("Mã lỗi HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleOAuthError.tokenExchangeFailed("Không thể đọc dữ liệu JSON từ máy chủ.")
        }

        return try parseSignInWithIdpResponse(json)
    }

    public static func parseSignInWithIdpResponse(_ json: [String: Any]) throws -> GoogleOAuthProfile {
        var rawUserDict: [String: Any] = [:]
        if let rawUserInfoStr = json["rawUserInfo"] as? String,
           let rawData = rawUserInfoStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            rawUserDict = parsed
        }

        let email = (json["email"] as? String)
            ?? (rawUserDict["email"] as? String)
            ?? ""
        guard !email.isEmpty else {
            throw GoogleOAuthError.tokenExchangeFailed("Tài khoản Google không trả về địa chỉ email.")
        }

        let googleSub = (rawUserDict["sub"] as? String)
            ?? (rawUserDict["id"] as? String)
            ?? (json["federatedId"] as? String)
            ?? (json["localId"] as? String)
            ?? email

        let displayName = (json["displayName"] as? String)
            ?? (json["fullName"] as? String)
            ?? (rawUserDict["name"] as? String)
            ?? String(email.split(separator: "@").first ?? "Giáo viên")

        let photoURL = (json["photoUrl"] as? String)
            ?? (rawUserDict["picture"] as? String)

        return GoogleOAuthProfile(
            googleSubjectId: googleSub,
            email: email,
            displayName: displayName,
            photoURL: photoURL
        )
    }
}

#if canImport(UIKit)
/// Trình điều khiển Sheet đăng nhập Google trực tiếp (`accounts.google.com`) và bắt giữ URL callback ngay lập tức
/// trước khi trang `firebaseapp.com/__/auth/handler` kịp thực thi JavaScript phụ thuộc `sessionStorage`.
@MainActor
private final class GoogleOAuthWebSheetController: UIViewController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let authURL: URL
    private let firebaseHost: String
    private let encodedAppScheme: String
    private var completion: ((Result<URL, GoogleOAuthError>) -> Void)?

    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var progressObservation: NSKeyValueObservation?

    init(
        authURL: URL,
        firebaseHost: String,
        encodedAppScheme: String,
        completion: @escaping (Result<URL, GoogleOAuthError>) -> Void
    ) {
        self.authURL = authURL
        self.firebaseHost = firebaseHost.lowercased()
        self.encodedAppScheme = encodedAppScheme.lowercased()
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L("Đăng nhập Google", "Google Sign-In")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L("Hủy", "Cancel"),
            style: .plain,
            target: self,
            action: #selector(didTapCancel)
        )
        navigationController?.presentationController?.delegate = self

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        // Sử dụng Mobile Safari User-Agent chuẩn để Google hiển thị giao diện OAuth v3 chính thức trên iOS
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .clear

        view.addSubview(webView)
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in
                guard let self else { return }
                let progress = Float(wv.estimatedProgress)
                self.progressView.setProgress(progress, animated: true)
                self.progressView.isHidden = progress >= 1.0
            }
        }

        webView.load(URLRequest(url: authURL))
    }

    @objc private func didTapCancel() {
        finish(with: .failure(.cancelledByUser))
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor in
            self.finish(with: .failure(.cancelledByUser))
        }
    }

    private func finish(with result: Result<URL, GoogleOAuthError>) {
        guard let callback = completion else { return }
        completion = nil
        progressObservation?.invalidate()
        progressObservation = nil

        if presentingViewController != nil {
            dismiss(animated: true) {
                callback(result)
            }
        } else {
            callback(result)
        }
    }

    private func shouldInterceptCallbackURL(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(),
           (scheme == encodedAppScheme || scheme.hasPrefix("com.googleusercontent.apps.")) {
            return true
        }

        if let host = url.host?.lowercased(),
           host == firebaseHost,
           url.path.hasPrefix("/__/auth/") {
            return true
        }

        return false
    }

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, shouldInterceptCallbackURL(url) {
            decisionHandler(.cancel)
            finish(with: .success(url))
            return
        }
        decisionHandler(.allow)
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        if let url = webView.url, shouldInterceptCallbackURL(url) {
            webView.stopLoading()
            finish(with: .success(url))
        }
    }

    @objc(webView:didStartProvisionalNavigation:)
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        if let url = webView.url, shouldInterceptCallbackURL(url) {
            webView.stopLoading()
            finish(with: .success(url))
        }
    }
}
#endif

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = scenes.flatMap({ $0.windows }).first {
            return firstWindow
        }
        return ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
