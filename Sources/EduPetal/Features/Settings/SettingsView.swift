import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Cài đặt & Thông tin Ứng dụng (Settings & Teacher Profile)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public let teacherName: String
    public let teacherTitle: String
    public let activeStudentsCount: Int
    public let activeClassesCount: Int
    public let totalSessionsCount: Int
    public let upcomingSessions: [TeachingSessionEntity]

    @State private var bankConfig: BankAccountConfig = BankAccountConfig()
    @State private var isShowingBankSetup: Bool = false
    @State private var isShowingSignOutConfirm: Bool = false
    @State private var isShowingAuthSheet: Bool = false
    @State private var isShowingPrivacySheet: Bool = false
    @State private var sessionManager = UserSessionManager.shared
    @State private var localizationManager = LocalizationManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var teacherAvatarPath: String? = AvatarStorageService.shared.teacherAvatarPath
    #if canImport(UIKit)
    @State private var avatarEditItem: AvatarEditItem? = nil
    #endif
    #if canImport(PhotosUI)
    @State private var selectedTeacherPhotoItem: PhotosPickerItem? = nil
    #endif
    @State private var isSessionReminderEnabled: Bool = LocalNotificationService.shared.isSessionReminderEnabled
    @State private var isDailyReminderEnabled: Bool = LocalNotificationService.shared.isDailyReminderEnabled
    @State private var dailyReminderTime: Date = {
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comp.hour = LocalNotificationService.shared.dailyReminderHour
        comp.minute = LocalNotificationService.shared.dailyReminderMinute
        return Calendar.current.date(from: comp) ?? Date()
    }()
    @State private var isProgrammaticTimeUpdate: Bool = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationSummary: NotificationStatusSummary = NotificationStatusSummary(
        isAuthorized: false,
        isDenied: false,
        isNotDetermined: true,
        pendingSessionReminderCount: 0,
        nextSessionReminderDate: nil,
        isDailyReminderPending: false,
        dailyReminderHour: LocalNotificationService.shared.dailyReminderHour,
        dailyReminderMinute: LocalNotificationService.shared.dailyReminderMinute
    )
    @State private var scheduleFeedbackMessage: String? = nil

    private let bankService = BankConfigService.shared
    private let notificationService = LocalNotificationService.shared

    public init(
        teacherName: String = "Thầy Minh Huy",
        teacherTitle: String = "Giáo viên / Gia sư Tự do",
        activeStudentsCount: Int = 0,
        activeClassesCount: Int = 0,
        totalSessionsCount: Int = 0,
        upcomingSessions: [TeachingSessionEntity] = []
    ) {
        self.teacherName = teacherName
        self.teacherTitle = teacherTitle
        self.activeStudentsCount = activeStudentsCount
        self.activeClassesCount = activeClassesCount
        self.totalSessionsCount = totalSessionsCount
        self.upcomingSessions = upcomingSessions
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // MARK: - Teacher Profile Card
                    AppCard {
                        VStack(spacing: AppSpacing.sm) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(
                                    avatarPath: teacherAvatarPath,
                                    initials: "EP",
                                    size: 76,
                                    showBorder: true
                                )

                                #if canImport(PhotosUI)
                                PhotosPicker(selection: $selectedTeacherPhotoItem, matching: .images) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(AppColors.accentRose)
                                        .background(Circle().fill(AppColors.surfaceCard))
                                }
                                #endif
                            }

                            if teacherAvatarPath != nil {
                                HStack(spacing: AppSpacing.md) {
                                    #if canImport(UIKit)
                                    Button {
                                        if let path = teacherAvatarPath,
                                           let img = AvatarStorageService.shared.loadAvatar(named: path) {
                                            avatarEditItem = AvatarEditItem(image: img)
                                        }
                                    } label: {
                                        Text(L("Chỉnh sửa", "Edit"))
                                            .font(AppTypography.caption1)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.accentRose)
                                    }
                                    #endif

                                    Button(role: .destructive) {
                                        if let old = teacherAvatarPath {
                                            AvatarStorageService.shared.deleteAvatar(named: old)
                                        }
                                        teacherAvatarPath = nil
                                        AvatarStorageService.shared.teacherAvatarPath = nil
                                    } label: {
                                        Text(L("Gỡ ảnh", "Remove Photo"))
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.error)
                                    }
                                }
                            }

                            VStack(spacing: 4) {
                                Text(LocalizationManager.translate(sessionManager.currentUser?.displayName ?? teacherName))
                                    .font(AppTypography.title3)
                                    .foregroundColor(AppColors.primaryText)
                                    .fontWeight(.bold)

                                if let user = sessionManager.currentUser {
                                    HStack(spacing: 6) {
                                        Text(LocalizationManager.translate(user.provider.displayName))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                user.isGuest
                                                ? AppColors.secondaryText.opacity(0.15)
                                                : AppColors.accentRose.opacity(0.15)
                                            )
                                            .foregroundColor(
                                                user.isGuest
                                                ? AppColors.secondaryText
                                                : AppColors.accentRose
                                            )
                                            .clipShape(Capsule())

                                        Text(LocalizationManager.translate(user.maskedIdentifier))
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text(LocalizationManager.translate(teacherTitle))
                                        .font(AppTypography.subheadline)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }

                            Divider()
                                .background(AppColors.divider)

                            HStack {
                                profileCounter(title: L("Học sinh", "Students"), value: "\(activeStudentsCount)")
                                Divider().frame(height: 24)
                                profileCounter(title: L("Lớp học", "Classes"), value: "\(activeClassesCount)")
                                Divider().frame(height: 24)
                                profileCounter(title: L("Buổi dạy", "Sessions"), value: "\(totalSessionsCount)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // MARK: - Language Switcher Card (Chuyển ngôn ngữ Tiếng Việt / English)
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "globe")
                                    .foregroundColor(AppColors.accentRose)
                                Text(L("Ngôn ngữ hiển thị", "App Language"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Picker(
                                L("Ngôn ngữ", "Language"),
                                selection: Binding(
                                    get: { localizationManager.currentLanguage },
                                    set: { newLang in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            localizationManager.setLanguage(newLang)
                                        }
                                    }
                                )
                            ) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text("\(lang.flagEmoji) \(lang.displayName)")
                                        .tag(lang)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // MARK: - Account Card (Chuẩn App Store tương tự SnapSpend)
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundColor(AppColors.accentRose)
                                Text(L("Tài khoản", "Account"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            if let user = sessionManager.currentUser {
                                if user.isGuest {
                                    SecondaryButton(
                                        L("Đăng nhập / Tạo tài khoản", "Sign In / Create Account"),
                                        icon: "person.badge.key.fill"
                                    ) {
                                        isShowingAuthSheet = true
                                    }
                                } else {
                                    SecondaryButton(
                                        L("Đổi tài khoản / Phương thức đăng nhập", "Switch Account / Sign-In Method"),
                                        icon: "arrow.triangle.2.circlepath"
                                    ) {
                                        isShowingAuthSheet = true
                                    }
                                }

                                HStack(spacing: AppSpacing.xs) {
                                    SecondaryButton(
                                        L("Đăng xuất", "Sign Out"),
                                        icon: "rectangle.portrait.and.arrow.right"
                                    ) {
                                        isShowingSignOutConfirm = true
                                    }
                                }
                            } else {
                                SecondaryButton(
                                    L("Đăng nhập / Tạo tài khoản", "Sign In / Create Account"),
                                    icon: "person.badge.key.fill"
                                ) {
                                    isShowingAuthSheet = true
                                }
                            }
                        }
                    }

                    // MARK: - Bank Account & VietQR Card
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "qrcode")
                                    .foregroundColor(AppColors.accentRose)
                                Text(L("Tài khoản nhận học phí (VietQR)", "Bank Account for Tuition (VietQR)"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Button {
                                isShowingBankSetup = true
                            } label: {
                                HStack {
                                    if bankConfig.isConfigured {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bankConfig.bankName)
                                                .font(AppTypography.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(AppColors.primaryText)
                                            Text("\(bankConfig.accountNumber) • \(bankConfig.accountHolderName)")
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                    } else {
                                        HStack(spacing: AppSpacing.xxs) {
                                            Image(systemName: "exclamationmark.circle")
                                                .foregroundColor(AppColors.warning)
                                            Text(L("Chưa cài đặt tài khoản", "Bank account not configured"))
                                                .font(AppTypography.subheadline)
                                                .foregroundColor(AppColors.warning)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppColors.tertiaryText)
                                }
                                .padding(AppSpacing.sm)
                                .background(AppColors.surfaceSubtle)
                                .cornerRadius(AppRadius.sm)
                            }
                            .padding(.top, AppSpacing.xxs)
                        }
                    }

                    // MARK: - Notifications & Reminders Card
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(AppColors.accentRose)
                                Text(L("Thông báo & Lời nhắc", "Notifications & Reminders"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Divider()
                                .background(AppColors.divider)

                            #if canImport(UserNotifications)
                            // Trạng thái quyền thực tế của iOS
                            if notificationSummary.isNotDetermined {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bell.circle.fill")
                                            .foregroundColor(AppColors.accentRose)
                                            .font(AppTypography.font(size: 16))
                                        Text(L(
                                            "Chưa cấp quyền thông báo trên iPhone",
                                            "Notifications Not Yet Authorized"
                                        ))
                                        .font(AppTypography.caption1)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)
                                    }

                                    Text(L(
                                        "Bấm nút bên dưới để cho phép EduPetal gửi lời nhắc trước buổi dạy 60 phút và nhắc lịch lúc 22:00 hằng ngày.",
                                        "Tap below to allow EduPetal to schedule 60-minute session alerts and daily 22:00 reminders."
                                    ))
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)

                                    PrimaryButton(
                                        L("Cho phép gửi thông báo", "Allow Notifications"),
                                        icon: "bell.badge.fill"
                                    ) {
                                        Task {
                                            let granted = await notificationService.requestAuthorization()
                                            if granted {
                                                await notificationService.syncSessionReminders(for: upcomingSessions)
                                                await notificationService.syncDailyReminder()
                                                scheduleFeedbackMessage = L(
                                                    "Đã cấp quyền và lên lịch lời nhắc thành công.",
                                                    "Permission granted and reminders scheduled."
                                                )
                                            }
                                            await checkNotificationStatus()
                                        }
                                    }
                                }
                                .padding(AppSpacing.sm)
                                .background(AppColors.secondaryPink.opacity(0.4))
                                .cornerRadius(AppRadius.sm)
                            } else if notificationSummary.isDenied {
                                HStack(alignment: .top, spacing: AppSpacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppColors.warning)
                                        .font(AppTypography.font(size: 15))

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L(
                                            "Quyền thông báo đang bị tắt trong Cài đặt iOS.",
                                            "Notifications are disabled in iOS Settings."
                                        ))
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.primaryText)
                                        .fontWeight(.semibold)

                                        Text(L(
                                            "iPhone đang chặn thông báo của ứng dụng. Hãy mở Cài đặt iPhone -> Thông báo -> bật Cho phép thông báo.",
                                            "iOS is blocking app alerts. Open iOS Settings -> Notifications -> toggle Allow Notifications."
                                        ))
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.secondaryText)

                                        Button {
                                            LocalNotificationService.openSystemSettings()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "gearshape.fill")
                                                Text(L("Mở Cài đặt iPhone", "Open iOS Settings"))
                                            }
                                            .font(AppTypography.caption1)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(AppColors.accentRose))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 2)
                                    }
                                }
                                .padding(AppSpacing.sm)
                                .background(AppColors.warning.opacity(0.12))
                                .cornerRadius(AppRadius.sm)
                            }
                            #endif

                            // Loại A: Nhắc trước buổi dạy 60 phút
                            Toggle(isOn: $isSessionReminderEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Nhắc trước buổi dạy (60 phút)", "Session Reminder (60 mins before)"))
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)

                                    if isSessionReminderEnabled && notificationSummary.isAuthorized {
                                        Text(
                                            notificationSummary.pendingSessionReminderCount > 0
                                            ? L(
                                                "Đang hẹn: \(notificationSummary.pendingSessionReminderCount) buổi sắp tới",
                                                "Scheduled: \(notificationSummary.pendingSessionReminderCount) upcoming session(s)"
                                            )
                                            : L(
                                                "Đang hẹn: 0 buổi",
                                                "Scheduled: 0 sessions"
                                            )
                                        )
                                        .font(AppTypography.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(notificationSummary.pendingSessionReminderCount > 0 ? AppColors.success : AppColors.secondaryText)
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .tint(AppColors.accentRose)
                            .onChange(of: isSessionReminderEnabled) { _, newValue in
                                Task {
                                    let scheduled = await notificationService.setSessionReminderEnabled(
                                        newValue,
                                        upcomingSessions: upcomingSessions
                                    )
                                    await checkNotificationStatus()
                                    if newValue && scheduled {
                                        scheduleFeedbackMessage = L(
                                            "Đã bật lời nhắc trước buổi dạy 60 phút.",
                                            "Enabled 60-minute session reminders."
                                        )
                                    } else if !newValue {
                                        scheduleFeedbackMessage = L(
                                            "Đã tắt lời nhắc trước buổi dạy.",
                                            "Disabled 60-minute session reminders."
                                        )
                                    }
                                }
                            }

                            Divider()
                                .background(AppColors.divider)

                            // Loại B: Nhắc xem/thêm lịch hằng ngày (mặc định 22:00)
                            Toggle(isOn: $isDailyReminderEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Nhắc xem/thêm lịch dạy hằng ngày", "Daily Schedule Reminder"))
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.primaryText)

                                    if isDailyReminderEnabled && notificationSummary.isDailyReminderPending {
                                        Text(
                                            String(
                                                format: L(
                                                    "Đang hẹn lúc %02d:%02d hằng ngày",
                                                    "Scheduled at %02d:%02d daily"
                                                ),
                                                notificationSummary.dailyReminderHour,
                                                notificationSummary.dailyReminderMinute
                                            )
                                        )
                                        .font(AppTypography.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(AppColors.success)
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .tint(AppColors.accentRose)
                            .onChange(of: isDailyReminderEnabled) { _, newValue in
                                Task {
                                    let scheduled = await notificationService.setDailyReminderEnabled(newValue)
                                    await checkNotificationStatus()
                                    if newValue && scheduled {
                                        scheduleFeedbackMessage = String(
                                            format: L(
                                                "Đã lên lịch nhắc hằng ngày lúc %02d:%02d.",
                                                "Scheduled daily reminder at %02d:%02d."
                                            ),
                                            notificationService.dailyReminderHour,
                                            notificationService.dailyReminderMinute
                                        )
                                    } else if !newValue {
                                        scheduleFeedbackMessage = L(
                                            "Đã tắt lời nhắc hằng ngày.",
                                            "Disabled daily schedule reminder."
                                        )
                                    }
                                }
                            }

                            if isDailyReminderEnabled {
                                DatePicker(
                                    L("Giờ nhắc hằng ngày", "Daily Reminder Time"),
                                    selection: $dailyReminderTime,
                                    displayedComponents: [.hourAndMinute]
                                )
                                .font(AppTypography.body)
                                .onChange(of: dailyReminderTime) { _, newTime in
                                    guard !isProgrammaticTimeUpdate else { return }
                                    let comp = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                    let hour = comp.hour ?? 22
                                    let minute = comp.minute ?? 0
                                    Task {
                                        let scheduled = await notificationService.updateDailyReminderTime(
                                            hour: hour,
                                            minute: minute
                                        )
                                        await checkNotificationStatus()
                                        if scheduled {
                                            scheduleFeedbackMessage = String(
                                                format: L(
                                                    "Đã cập nhật lịch nhắc hằng ngày sang %02d:%02d.",
                                                    "Updated daily reminder to %02d:%02d."
                                                ),
                                                hour,
                                                minute
                                            )
                                        }
                                    }
                                }
                            }

                            if let feedback = scheduleFeedbackMessage {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppColors.success)
                                        .font(AppTypography.font(size: 13))
                                        .padding(.top, 1)
                                    Text(feedback)
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.primaryText)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.success.opacity(0.10))
                                .cornerRadius(AppRadius.sm)
                            }
                        }
                    }

                    // MARK: - Theme & Appearance Card
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .foregroundColor(AppColors.accentRose)
                                Text(L("Giao diện", "Appearance"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Divider()
                                .background(AppColors.divider)

                            Picker(
                                L("Chủ đề hiển thị", "Theme"),
                                selection: Binding(
                                    get: { themeManager.currentTheme },
                                    set: { newTheme in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            themeManager.setTheme(newTheme)
                                        }
                                    }
                                )
                            ) {
                                ForEach(AppTheme.allCases) { theme in
                                    Label(LocalizationManager.translate(theme.displayName), systemImage: theme.iconName)
                                        .tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // MARK: - Data Safety & Privacy
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(AppColors.success)
                                Text(L("Bảo mật & Quyền riêng tư", "Security & Privacy"))
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Button {
                                isShowingPrivacySheet = true
                            } label: {
                                HStack {
                                    Text(L("Xem Chính sách Quyền riêng tư", "View Privacy Policy"))
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.accentRose)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppColors.tertiaryText)
                                }
                                .padding(.top, 2)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .background(AppColors.divider)

                            infoRow(label: L("Phiên bản", "Version"), value: "1.0.0")
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(L("Cài đặt & Hồ sơ", "Settings & Profile"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Đóng", "Close")) {
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentRose)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                themeManager.applyToAllWindows()
                self.bankConfig = bankService.loadConfig()
                Task {
                    await checkNotificationStatus()
                }
            }
            .onChange(of: sessionManager.sessionGeneration) { _, _ in
                self.bankConfig = bankService.loadConfig()
                self.teacherAvatarPath = AvatarStorageService.shared.teacherAvatarPath
            }
            .preferredColorScheme(themeManager.colorScheme)
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    let status = await notificationService.checkAuthorizationStatus()
                    if notificationService.isAuthorizedStatus(status) {
                        await notificationService.syncSessionReminders(for: upcomingSessions)
                        await notificationService.syncDailyReminder()
                    }
                    await checkNotificationStatus()
                }
            }
            #endif
            .sheet(isPresented: $isShowingBankSetup) {
                BankSetupSheet(config: $bankConfig) {
                    self.bankConfig = bankService.loadConfig()
                }
            }
            #if canImport(UIKit)
            .fullScreenCover(item: $avatarEditItem) { item in
                AvatarEditorView(
                    image: item.image,
                    onCancel: { avatarEditItem = nil },
                    onDone: { edited in
                        let saved = try? AvatarStorageService.shared.saveAvatar(
                            image: edited,
                            prefix: "teacher",
                            oldAvatarPath: teacherAvatarPath
                        )
                        if let saved {
                            teacherAvatarPath = saved
                            AvatarStorageService.shared.teacherAvatarPath = saved
                        }
                        avatarEditItem = nil
                    }
                )
            }
            #endif
            .sheet(isPresented: $isShowingAuthSheet) {
                LoginView(sessionManager: sessionManager)
            }
            .sheet(isPresented: $isShowingPrivacySheet) {
                NavigationStack {
                    EduPetalDataPrivacyView()
                }
            }
            .alert(L("Đăng xuất tài khoản?", "Sign Out?"), isPresented: $isShowingSignOutConfirm) {
                Button(L("Hủy", "Cancel"), role: .cancel) {}
                Button(L("Đăng xuất", "Sign Out"), role: .destructive) {
                    Task {
                        await sessionManager.signOut()
                        dismiss()
                    }
                }
            } message: {
                Text(L("Dữ liệu của bạn vẫn được giữ lại.", "Your teaching data remains safely stored on this device."))
            }
            #if canImport(PhotosUI)
            .onChange(of: selectedTeacherPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        #if canImport(UIKit)
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                self.avatarEditItem = AvatarEditItem(image: image)
                                self.selectedTeacherPhotoItem = nil
                            }
                        }
                        #endif
                    }
                }
            }
            #endif
        }
    }

    private func updatePickerTimeProgrammatically(hour: Int, minute: Int) {
        isProgrammaticTimeUpdate = true
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comp.hour = hour
        comp.minute = minute
        if let newDate = Calendar.current.date(from: comp) {
            self.dailyReminderTime = newDate
        }
        DispatchQueue.main.async {
            self.isProgrammaticTimeUpdate = false
        }
    }

    private func checkNotificationStatus() async {
        #if canImport(UserNotifications)
        self.notificationAuthStatus = await notificationService.checkAuthorizationStatus()
        self.notificationSummary = await notificationService.fetchStatusSummary()
        #endif
    }

    private func profileCounter(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppTypography.title3)
                .fontWeight(.bold)
                .foregroundColor(AppColors.accentRose)
            Text(title)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(value)
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.primaryText)
                .fontWeight(.medium)
        }
    }
}
