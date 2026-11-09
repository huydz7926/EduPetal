import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

public enum AppleSignInError: Error, LocalizedError, Equatable {
    case cancelledByUser
    case capabilityNotProvisioned
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelledByUser:
            return nil
        case .capabilityNotProvisioned:
            return L(
                "Sign in with Apple chưa được cấp quyền trên Provisioning Profile hiện tại (Personal Team). Vui lòng bật capability 'Sign in with Apple' trên Apple Developer Portal cho com.edupetal.app, hoặc chọn 'Tiếp tục với Google' / 'Tiếp tục với Email'.",
                "Sign in with Apple is not provisioned on the current Personal Team profile. Please enable the 'Sign in with Apple' capability in Apple Developer Portal for com.edupetal.app, or sign in with Google / Email."
            )
        case .failed(let message):
            return message
        }
    }
}

/// Dịch vụ Đăng nhập bằng Apple native (`ASAuthorizationAppleIDProvider`).
/// Tuyệt đối không tạo tài khoản demo, không dùng UIDevice/Face ID thay thế xác thực Apple Account thật.
@MainActor
public final class AppleSignInService: NSObject {
    public static let shared = AppleSignInService()

    private var activeContinuation: CheckedContinuation<(userIdentifier: String, email: String?, fullName: String?), Error>?
    private var activeController: ASAuthorizationController?

    public override init() {
        super.init()
    }

    /// Thực hiện luồng Sign in with Apple native của iOS (`ASAuthorizationController`).
    /// Chỉ tạo phiên đã đăng nhập khi hệ thống trả về `ASAuthorizationAppleIDCredential` hợp lệ.
    public func authenticateWithiOS(
        sessionManager: UserSessionManager = .shared
    ) async throws -> AuthenticatedUser? {
        sessionManager.isAuthenticating = true
        sessionManager.authErrorMessage = nil

        do {
            let credential = try await performNativeAppleIDRequest()
            return try await sessionManager.signInWithApple(
                appleUserIdentifier: credential.userIdentifier,
                email: credential.email,
                displayName: credential.fullName
            )
        } catch AppleSignInError.cancelledByUser {
            sessionManager.handleSignInCancelled()
            return nil
        } catch {
            sessionManager.handleSignInError(error.localizedDescription)
            throw error
        }
    }

    private func performNativeAppleIDRequest() async throws -> (userIdentifier: String, email: String?, fullName: String?) {
        return try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = UserSessionManager.shared.prepareAppleSignInNonce()

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.activeController = controller
            controller.performRequests()
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    public nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            defer {
                self.activeController = nil
                self.activeContinuation = nil
            }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.activeContinuation?.resume(throwing: AppleSignInError.failed(
                    L("Không nhận được thông tin xác thực Apple ID.", "Did not receive valid Apple ID credentials.")
                ))
                return
            }

            let userIdentifier = credential.user
            let email = credential.email

            var formattedName: String? = nil
            if let fullName = credential.fullName {
                let formatter = PersonNameComponentsFormatter()
                let str = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    formattedName = str
                }
            }

            self.activeContinuation?.resume(returning: (
                userIdentifier: userIdentifier,
                email: email,
                fullName: formattedName
            ))
        }
    }

    public nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            defer {
                self.activeController = nil
                self.activeContinuation = nil
            }
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    self.activeContinuation?.resume(throwing: AppleSignInError.cancelledByUser)
                    return
                case .unknown, .notHandled, .invalidResponse:
                    self.activeContinuation?.resume(throwing: AppleSignInError.capabilityNotProvisioned)
                    return
                default:
                    break
                }
            }
            self.activeContinuation?.resume(throwing: AppleSignInError.failed(error.localizedDescription))
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
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

