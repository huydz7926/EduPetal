import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Thành phần giao diện Avatar chuẩn của EduPetal
/// Tự động hiển thị ảnh đã lưu trên thiết bị hoặc avatar mặc định với chữ cái đầu (Initials)
public struct AvatarView: View {
    public let avatarPath: String?
    public let initials: String
    public let size: CGFloat
    public let showBorder: Bool
    public let borderColor: Color

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    #endif

    public init(
        avatarPath: String?,
        initials: String,
        size: CGFloat = 44,
        showBorder: Bool = false,
        borderColor: Color = AppColors.accentRose.opacity(0.3)
    ) {
        self.avatarPath = avatarPath
        self.initials = initials
        self.size = size
        self.showBorder = showBorder
        self.borderColor = borderColor
    }

    public var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                defaultInitialsView
            }
            #else
            defaultInitialsView
            #endif
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(showBorder ? borderColor : Color.clear, lineWidth: max(1.5, size / 32.0))
        )
        #if canImport(UIKit)
        .onAppear {
            loadAvatarImage()
        }
        .onChange(of: avatarPath) { _, _ in
            loadAvatarImage()
        }
        #endif
    }

    private var defaultInitialsView: some View {
        ZStack {
            Circle()
                .fill(AppColors.secondaryPink)
                .frame(width: size, height: size)

            Text(cleanInitials)
                .font(fontForSize(size))
                .foregroundColor(AppColors.accentRose)
                .fontWeight(.bold)
        }
    }

    private var cleanInitials: String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "EP" : trimmed
    }

    private func fontForSize(_ size: CGFloat) -> Font {
        if size <= 32 {
            return AppTypography.caption2
        } else if size <= 48 {
            return AppTypography.headline
        } else if size <= 64 {
            return AppTypography.title3
        } else {
            return AppTypography.title1
        }
    }

    #if canImport(UIKit)
    private func loadAvatarImage() {
        guard let path = avatarPath, !path.isEmpty else {
            self.loadedImage = nil
            return
        }
        self.loadedImage = AvatarStorageService.shared.loadAvatar(named: path)
    }
    #endif
}

