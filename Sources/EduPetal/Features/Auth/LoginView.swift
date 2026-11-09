import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

// MARK: - LoginView (Chuẩn App Store tương tự AuthWelcomeView của SnapSpend)

public struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Bindable public var sessionManager: UserSessionManager
    @State private var localizationManager = LocalizationManager.shared

    private enum AuthScreenMode {
        case welcome
        case email
    }

    @State private var mode: AuthScreenMode = .welcome
    @State private var isRegistering: Bool = false

    // Form fields
    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var showPrivacySheet: Bool = false
    @State private var showForgotPasswordAlert: Bool = false
    @State private var forgotPasswordMessage: String = ""

    public init(sessionManager: UserSessionManager = .shared) {
        self.sessionManager = sessionManager
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 26) {
                        Spacer(minLength: mode == .welcome ? 24 : 8)

                        // App Logo & Header
                        appHeaderView

                        if mode == .welcome {
                            welcomeButtonsView
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            emailAuthFormView
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }

                        // Điều khoản & Chính sách bảo mật
                        legalTermsFooterView
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode == .email {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                errorMessage = nil
                                mode = .welcome
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                Text(L("Quay lại", "Back"))
                            }
                            .foregroundStyle(AppColors.primaryText)
                        }
                    } else {
                        // Nút chuyển ngôn ngữ nhanh trên màn hình Đăng nhập
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localizationManager.toggleLanguage()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(localizationManager.currentLanguage.flagEmoji)
                                Text(localizationManager.currentLanguage == .vietnamese ? "VN" : "EN")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.surfaceCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                            .foregroundStyle(AppColors.primaryText)
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if sessionManager.isAuthenticated {
                        Button(L("Hủy", "Cancel")) {
                            dismiss()
                        }
                        .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            .sheet(isPresented: $showPrivacySheet) {
                NavigationStack {
                    EduPetalDataPrivacyView()
                }
            }
            .alert(L("Khôi phục mật khẩu", "Reset Password"), isPresented: $showForgotPasswordAlert) {
                Button(L("Đã hiểu", "Got it"), role: .cancel) {}
            } message: {
                Text(forgotPasswordMessage)
            }
        }
    }

    // MARK: - 1. App Header (Chuẩn SnapSpend)

    private var appHeaderView: some View {
        VStack(spacing: 12) {
            appLogoBadge
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)

            Text("EduPetal")
                .font(AppTypography.font(size: 30))
                .foregroundStyle(AppColors.primaryText)

            Text(L("Quản lý lớp học & học phí", "Classroom & Tuition Management"))
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var appLogoBadge: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(named: "AppLogo") {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            defaultLogoEmblem
        }
        #else
        defaultLogoEmblem
        #endif
    }

    private var defaultLogoEmblem: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.secondaryPink, AppColors.primaryPink.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(AppColors.accentRose)
        }
    }

    // MARK: - 2. Welcome Buttons (Chỉ gồm các nút đăng nhập gọn sạch chuẩn App Store)

    private var welcomeButtonsView: some View {
        VStack(spacing: 14) {
            // 1. Sign in with Apple (1 chạm xác thực Face ID / Apple ID trực tiếp, không hiện form nhập tay)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = sessionManager.prepareAppleSignInNonce()
            } onCompletion: { result in
                handleAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(minHeight: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)

            // 2. Google Login (OAuth 2.0 chuẩn App Store)
            Button {
                handleGoogleSignIn()
            } label: {
                HStack(spacing: 10) {
                    googleLogoView
                    Text(L("Tiếp tục với Google", "Continue with Google"))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .font(AppTypography.font(size: 16))
                        .foregroundStyle(AppColors.primaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.divider, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || sessionManager.isAuthenticating)

            // 3. Tiếp tục với Email & Mật khẩu
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    errorMessage = nil
                    mode = .email
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                    Text(L("Tiếp tục với Email", "Continue with Email"))
                        .font(AppTypography.font(size: 16))
                        .foregroundStyle(AppColors.primaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let errorMessage = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.error)
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // Divider "hoặc"
            HStack(spacing: 12) {
                Rectangle()
                    .fill(AppColors.divider)
                    .frame(height: 1)
                Text(L("hoặc", "or"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.secondaryText)
                Rectangle()
                    .fill(AppColors.divider)
                    .frame(height: 1)
            }
            .padding(.vertical, 4)

            // 4. Dùng thử ngay không cần tài khoản (Guest Mode)
            Button {
                Task {
                    _ = await sessionManager.continueAsGuest()
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(L("Dùng thử ngay không cần tài khoản", "Try Instantly as Guest"))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. Email Auth Form (Đăng nhập / Đăng ký — Chuẩn SnapSpend)

    private var emailAuthFormView: some View {
        VStack(spacing: 18) {
            Picker("", selection: $isRegistering) {
                Text(L("Đăng nhập", "Sign In")).tag(false)
                Text(L("Tạo tài khoản", "Create Account")).tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: isRegistering) { _, _ in
                errorMessage = nil
            }

            VStack(spacing: 14) {
                if isRegistering {
                    inputField(
                        title: L("Họ và tên", "Full Name"),
                        placeholder: L("Nguyễn Văn A", "John Doe"),
                        icon: "person.fill",
                        text: $fullName,
                        isSecure: false
                    )
                }

                inputField(
                    title: "Email",
                    placeholder: "name@example.com",
                    icon: "envelope.fill",
                    text: $email,
                    isSecure: false,
                    isEmailField: true
                )

                VStack(alignment: .trailing, spacing: 6) {
                    inputField(
                        title: L("Mật khẩu", "Password"),
                        placeholder: L("Ít nhất 6 ký tự", "At least 6 characters"),
                        icon: "lock.fill",
                        text: $password,
                        isSecure: true
                    )

                    if !isRegistering {
                        Button {
                            handleForgotPassword()
                        } label: {
                            Text(L("Quên mật khẩu?", "Forgot password?"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.accentRose)
                        }
                    }
                }

                if isRegistering {
                    inputField(
                        title: L("Xác nhận mật khẩu", "Confirm Password"),
                        placeholder: L("Nhập lại mật khẩu", "Re-enter password"),
                        icon: "lock.rotation",
                        text: $confirmPassword,
                        isSecure: true
                    )
                }
            }
            .padding(18)
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            )

            if let errorMessage = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.error)
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            Button {
                submitEmailAuth()
            } label: {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isRegistering ? L("Tạo tài khoản", "Create Account") : L("Đăng nhập", "Sign In"))
                            .font(AppTypography.font(size: 17))
                    }
                }
                .foregroundStyle(AppColors.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(AppColors.accentRose)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AppColors.accentRose.opacity(0.28), radius: 8, y: 4)
            }
            .disabled(isLoading)
        }
    }

    // MARK: - 4. Input Field Builder

    private func inputField(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        isSecure: Bool,
        isEmailField: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 20)

                if isSecure {
                    SecureField(placeholder, text: text)
                        .font(.body)
                        .foregroundStyle(AppColors.primaryText)
                } else {
                    TextField(placeholder, text: text)
                        .font(.body)
                        .foregroundStyle(AppColors.primaryText)
                        #if canImport(UIKit)
                        .keyboardType(isEmailField ? .emailAddress : .default)
                        .textInputAutocapitalization(isEmailField ? .never : .words)
                        #endif
                        .autocorrectionDisabled()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            )
        }
    }

    // MARK: - 5. Legal Terms Footer

    private var legalTermsFooterView: some View {
        VStack(spacing: 6) {
            Text(L("Tiếp tục nghĩa là bạn đồng ý với điều khoản của EduPetal.", "By continuing, you agree to EduPetal's Terms & Privacy Policy."))
                .font(.caption2)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                showPrivacySheet = true
            } label: {
                Text(L("Chính sách quyền riêng tư", "Privacy Policy"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentRose)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 6. Google Logo View

    private var googleLogoView: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#FFFFFF"))
                .frame(width: 24, height: 24)
                .shadow(color: Color.black.opacity(0.08), radius: 1, y: 0.5)

            Text("G")
                .font(AppTypography.font(size: 15))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.92, green: 0.26, blue: 0.21),
                            Color(red: 0.98, green: 0.74, blue: 0.02),
                            Color(red: 0.20, green: 0.66, blue: 0.33)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - 7. Actions

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    do {
                        _ = try await sessionManager.handleAppleSignInCompletion(
                            userIdentifier: credential.user,
                            email: credential.email,
                            fullName: credential.fullName,
                            identityTokenData: credential.identityToken
                        )
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                sessionManager.handleSignInCancelled()
                return
            }
            if nsError.domain == ASAuthorizationError.errorDomain,
               (nsError.code == ASAuthorizationError.unknown.rawValue ||
                nsError.code == ASAuthorizationError.notHandled.rawValue ||
                nsError.code == ASAuthorizationError.invalidResponse.rawValue) {
                let msg = AppleSignInError.capabilityNotProvisioned.errorDescription ?? error.localizedDescription
                sessionManager.handleSignInError(msg)
                errorMessage = msg
                return
            }
            sessionManager.handleSignInError(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func handleGoogleSignIn() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                _ = try await GoogleOAuthService.shared.signInWithGoogleWebSession(sessionManager: sessionManager)
                isLoading = false
                dismiss()
            } catch GoogleOAuthError.cancelledByUser {
                sessionManager.handleSignInCancelled()
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitEmailAuth() {
        errorMessage = nil

        if isRegistering {
            guard password == confirmPassword else {
                errorMessage = L("Mật khẩu xác nhận không khớp.", "Passwords do not match.")
                return
            }
        }

        isLoading = true
        Task {
            do {
                if isRegistering {
                    _ = try await sessionManager.signUpWithEmail(
                        fullName: fullName,
                        email: email,
                        password: password
                    )
                } else {
                    _ = try await sessionManager.signInWithEmail(
                        email: email,
                        password: password
                    )
                }
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleForgotPassword() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            errorMessage = L("Nhập email trước.", "Please enter your email first.")
            return
        }

        Task {
            do {
                try await sessionManager.sendPasswordResetEmail(to: trimmedEmail)
                forgotPasswordMessage = L(
                    "Đã gửi email đặt lại mật khẩu tới \(trimmedEmail).",
                    "Password reset email sent to \(trimmedEmail)."
                )
                showForgotPasswordAlert = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - EduPetalDataPrivacyView (Bảo mật & Quyền riêng tư ngắn gọn)

public struct EduPetalDataPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                privacyItem(
                    icon: "iphone",
                    title: L("Lưu trữ trên thiết bị", "On-Device Storage"),
                    detail: L(
                        "Dữ liệu lớp học, học sinh, lịch dạy và học phí được lưu trên iPhone của bạn và tách biệt theo từng tài khoản.",
                        "Class, student, schedule, and tuition data is stored on your iPhone and isolated per account."
                    )
                )

                privacyItem(
                    icon: "camera.fill",
                    title: L("Camera & Thư viện ảnh", "Camera & Photos"),
                    detail: L(
                        "Chỉ sử dụng khi bạn chọn ảnh đại diện hoặc chụp ảnh minh chứng buổi dạy.",
                        "Used only when you select an avatar or capture a session photo."
                    )
                )

                privacyItem(
                    icon: "bell.fill",
                    title: L("Thông báo", "Notifications"),
                    detail: L(
                        "Dùng để nhắc trước giờ dạy và nhắc kiểm tra lịch hằng ngày.",
                        "Used for session reminders and daily schedule alerts."
                    )
                )

                privacyItem(
                    icon: "lock.shield.fill",
                    title: L("Không chia sẻ dữ liệu", "No Data Sharing"),
                    detail: L(
                        "Ứng dụng không bán hoặc chia sẻ dữ liệu của bạn cho bên thứ ba.",
                        "Your data is never sold or shared with third parties."
                    )
                )

                privacyItem(
                    icon: "envelope.fill",
                    title: L("Liên hệ hỗ trợ", "Support Contact"),
                    detail: "huytx3z3@gmail.com"
                )
            }
            .padding(16)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(L("Bảo mật & Quyền riêng tư", "Privacy Policy"))
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Đóng", "Close")) { dismiss() }
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accentRose)
            }
        }
    }

    private func privacyItem(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accentRose)
                .frame(width: 28, height: 28)
                .background(AppColors.accentRose.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)

                Text(detail)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}
