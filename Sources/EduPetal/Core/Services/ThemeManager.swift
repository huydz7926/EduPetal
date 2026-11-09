import Foundation
import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Các chế độ hiển thị giao diện (Theme) của EduPetal
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"   // Tự động theo giao diện hệ thống iOS
    case light = "light"     // Giao diện Sáng (Light Mode)
    case dark = "dark"       // Giao diện Tối (Dark Mode)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "Hệ thống"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// ColorScheme tương ứng của SwiftUI
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    #if canImport(UIKit)
    /// UIUserInterfaceStyle tương ứng của UIKit để đồng bộ tức thì cho mọi UIWindow và Sheet đang mở
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
    #endif
}

/// Trình quản lý chế độ hiển thị toàn cục (Theme Manager)
/// Lưu cấu hình bền vững vào UserDefaults và áp dụng tự động cho toàn bộ ứng dụng (kể cả Sheet / Alert đang mở)
@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public static let themePreferenceKey = "EduPetal_Setting_AppTheme"
    private let userDefaults: UserDefaults

    public var currentTheme: AppTheme {
        didSet {
            userDefaults.set(currentTheme.rawValue, forKey: Self.themePreferenceKey)
            applyToAllWindows()
        }
    }

    public var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let saved = userDefaults.string(forKey: Self.themePreferenceKey),
           let theme = AppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
        applyToAllWindows()
    }

    public func setTheme(_ theme: AppTheme) {
        self.currentTheme = theme
        applyToAllWindows()
    }

    /// Đồng bộ `overrideUserInterfaceStyle` trên toàn bộ `UIWindow` hiện hành để mọi màn hình và Sheet đổi chế độ Sáng/Tối ngay lập tức
    public func applyToAllWindows() {
        #if canImport(UIKit)
        let style = currentTheme.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window.overrideUserInterfaceStyle != style {
                    UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve) {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }
        #endif
    }
}

