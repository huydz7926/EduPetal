import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Dịch vụ lưu trữ, nén và quản lý vòng đời ảnh đại diện (Avatar) phân vùng theo User
/// Tuân thủ nguyên tắc On-Device Per-User Storage: Không lưu binary vào database, chỉ lưu đường dẫn tương đối `"<ownerId>/<fileName>"`
public final class AvatarStorageService: @unchecked Sendable {
    public static let shared = AvatarStorageService()

    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, AnyObject>()
    private let sessionManager: UserSessionManager

    public static let teacherAvatarKeyPrefix = "EduPetal_Teacher_AvatarPath_"

    public init(sessionManager: UserSessionManager = .shared) {
        self.sessionManager = sessionManager
    }

    /// Xóa toàn bộ cache avatar trong RAM khi đăng xuất hoặc chuyển tài khoản
    public func clearMemoryCache() {
        cache.removeAllObjects()
    }

    /// Thư mục lưu trữ avatar phân vùng theo `ownerId` trong `Application Support/Users/<ownerId>/Media/Avatars`
    public func avatarsDirectoryURL(for ownerId: String? = nil) -> URL {
        let userDir = sessionManager.userRootDirectoryURL(for: ownerId)
        let dir = userDir.appendingPathComponent("Media/Avatars", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var avatarsDirectoryURL: URL {
        avatarsDirectoryURL(for: nil)
    }

    private var scopedTeacherAvatarKey: String {
        let owner = UserSessionManager.sanitizeIdentifier(sessionManager.currentOwnerId)
        return "\(Self.teacherAvatarKeyPrefix)\(owner)"
    }

    /// Đường dẫn avatar của Giáo viên lưu trong UserDefaults theo từng `ownerId`
    public var teacherAvatarPath: String? {
        get {
            UserDefaults.standard.string(forKey: scopedTeacherAvatarKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: scopedTeacherAvatarKey)
            } else {
                UserDefaults.standard.removeObject(forKey: scopedTeacherAvatarKey)
            }
        }
    }

    /// Lưu dữ liệu Data ảnh trực tiếp xuống đĩa trong phân vùng của user hiện tại
    @discardableResult
    public func saveAvatarData(
        _ data: Data,
        prefix: String,
        oldAvatarPath: String? = nil
    ) throws -> String {
        let ownerId = UserSessionManager.sanitizeIdentifier(sessionManager.currentOwnerId)
        let rawFileName = "avatar_\(prefix)_\(UUID().uuidString.prefix(8)).jpg"
        let fileURL = avatarsDirectoryURL(for: ownerId).appendingPathComponent(rawFileName)

        try data.write(to: fileURL, options: .atomic)
        let scopedPath = "\(ownerId)/\(rawFileName)"

        // Dọn ảnh cũ sau khi thay thành công (chỉ xóa nếu thuộc cùng chủ sở hữu)
        if let old = oldAvatarPath, !old.isEmpty, old != scopedPath {
            deleteAvatar(named: old)
        }

        return scopedPath
    }

    #if canImport(UIKit)
    /// Lưu UIImage xuống đĩa: Tự động crop vuông và resize kích thước tối đa 512x512, nén JPEG 0.82
    @discardableResult
    public func saveAvatar(
        image: UIImage,
        prefix: String,
        oldAvatarPath: String? = nil
    ) throws -> String {
        let processedImage = cropToSquareAndResize(image: image, targetSize: CGSize(width: 512, height: 512))
        guard let data = processedImage.jpegData(compressionQuality: 0.82) else {
            throw AvatarStorageError.compressionFailed
        }

        let scopedPath = try saveAvatarData(data, prefix: prefix, oldAvatarPath: oldAvatarPath)
        cache.setObject(processedImage, forKey: scopedPath as NSString)
        return scopedPath
    }

    /// Tải UIImage từ đường dẫn ảnh đại diện (Kiểm tra quyền sở hữu `ownerId` trước khi trả về)
    public func loadAvatar(named relativePath: String) -> UIImage? {
        guard let (ownerId, fileName) = try? sessionManager.verifyAndExtractFileName(from: relativePath) else {
            return nil
        }

        let cacheKey = "\(ownerId)/\(fileName)" as NSString
        if let cached = cache.object(forKey: cacheKey) as? UIImage {
            return cached
        }

        let fileURL = avatarsDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }

        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private func cropToSquareAndResize(image: UIImage, targetSize: CGSize) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let originX = (image.size.width - side) / 2.0
        let originY = (image.size.height - side) / 2.0
        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }

        let cropped = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif

    /// Xóa tệp avatar khỏi đĩa và xóa khỏi cache RAM (Chỉ xóa nếu đúng chủ sở hữu hiện tại)
    public func deleteAvatar(named relativePath: String) {
        guard let (ownerId, fileName) = try? sessionManager.verifyAndExtractFileName(from: relativePath) else {
            return
        }
        let cacheKey = "\(ownerId)/\(fileName)" as NSString
        cache.removeObject(forKey: cacheKey)
        let fileURL = avatarsDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// Kiểm tra xem tệp avatar có tồn tại và thuộc quyền sở hữu của user hiện tại hay không
    public func avatarFileExists(named relativePath: String) -> Bool {
        guard let (ownerId, fileName) = try? sessionManager.verifyAndExtractFileName(from: relativePath) else {
            return false
        }
        let fileURL = avatarsDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }
}

public enum AvatarStorageError: Error, LocalizedError {
    case compressionFailed
    case fileWriteFailed

    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Không thể nén dữ liệu ảnh đại diện."
        case .fileWriteFailed:
            return "Không thể lưu tệp ảnh đại diện vào bộ nhớ."
        }
    }
}
