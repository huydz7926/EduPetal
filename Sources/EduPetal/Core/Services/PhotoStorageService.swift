import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Dịch vụ lưu trữ và nén ảnh minh chứng lớp học vào vùng dữ liệu cục bộ phân vùng theo User (On-Device Per-User Storage)
/// Tuyệt đối không lưu binary ảnh vào database, chỉ lưu đường dẫn tương đối (`"<ownerId>/<fileName>"`)
public final class PhotoStorageService: @unchecked Sendable {
    public static let shared = PhotoStorageService()

    private var fileManager: FileManager {
        FileManager.default
    }

    private let memoryCache = NSCache<NSString, AnyObject>()
    private let sessionManager: UserSessionManager

    public init(sessionManager: UserSessionManager = .shared) {
        self.sessionManager = sessionManager
        memoryCache.countLimit = 150
    }

    /// Xóa toàn bộ bộ nhớ đệm ảnh trong RAM khi đăng xuất hoặc chuyển tài khoản
    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Thư mục lưu trữ media phân vùng theo `ownerId` trong `Application Support/Users/<ownerId>/Media/Photos`
    public func mediaDirectoryURL(for ownerId: String? = nil) -> URL {
        let userDir = sessionManager.userRootDirectoryURL(for: ownerId)
        let mediaDir = userDir.appendingPathComponent("Media/Photos", isDirectory: true)
        if !fileManager.fileExists(atPath: mediaDir.path) {
            try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        }
        return mediaDir
    }

    public var mediaDirectoryURL: URL {
        mediaDirectoryURL(for: nil)
    }

    /// Lưu dữ liệu Data ảnh minh chứng (hỗ trợ cả macOS CLI test runner và iOS) kèm bảo vệ phiên bất đồng bộ
    public func savePhotoData(
        _ data: Data,
        forSessionId sessionId: UUID,
        expectedSessionContext: SessionTaskContext? = nil
    ) async throws -> String {
        let capturedContext = expectedSessionContext ?? sessionManager.captureSessionContext()
        let ownerId = UserSessionManager.sanitizeIdentifier(capturedContext.ownerId)
        let targetDir = mediaDirectoryURL(for: ownerId)

        let rawFileName = try await Task.detached(priority: .userInitiated) {
            guard !data.isEmpty else {
                throw PhotoStorageError.compressionFailed
            }
            let name = "proof_\(sessionId.uuidString.prefix(8))_\(UUID().uuidString.prefix(6)).jpg"
            let fileURL = targetDir.appendingPathComponent(name)
            try data.write(to: fileURL, options: .atomic)
            return name
        }.value

        // Trước khi trả kết quả, kiểm tra phiên user còn khớp hay đã bị chuyển sang tài khoản khác
        do {
            try sessionManager.validateSessionContext(capturedContext)
        } catch {
            try? fileManager.removeItem(at: targetDir.appendingPathComponent(rawFileName))
            throw error
        }

        return "\(ownerId)/\(rawFileName)"
    }

    /// Kiểm tra quyền sở hữu và đọc dữ liệu ảnh minh chứng theo đường dẫn tương đối
    public func verifyAndLoadPhotoData(named relativePath: String, expectedOwnerId: String? = nil) throws -> Data {
        let (ownerId, fileName) = try sessionManager.verifyAndExtractFileName(
            from: relativePath,
            expectedOwnerId: expectedOwnerId
        )
        let fileURL = mediaDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            throw PhotoStorageError.fileWriteFailed
        }
        return data
    }

    #if canImport(UIKit)
    /// Lưu ảnh UIImage xuống đĩa trong Background Thread, nén JPEG 0.8 và trả về đường dẫn phân vùng `"<ownerId>/<fileName>"`
    /// Tự động kiểm tra `SessionTaskContext` trước khi hoàn tất để chống gán nhầm ảnh nếu đổi tài khoản khi đang chụp
    public func saveImage(
        _ image: UIImage,
        forSessionId sessionId: UUID,
        expectedSessionContext: SessionTaskContext? = nil
    ) async throws -> String {
        let capturedContext = expectedSessionContext ?? sessionManager.captureSessionContext()
        let ownerId = UserSessionManager.sanitizeIdentifier(capturedContext.ownerId)
        let targetDir = mediaDirectoryURL(for: ownerId)

        let rawFileName = try await Task.detached(priority: .userInitiated) {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                throw PhotoStorageError.compressionFailed
            }

            let name = "proof_\(sessionId.uuidString.prefix(8))_\(UUID().uuidString.prefix(6)).jpg"
            let fileURL = targetDir.appendingPathComponent(name)

            try data.write(to: fileURL, options: .atomic)
            return name
        }.value

        // Kiểm tra userID và mã phiên còn khớp trước khi lưu vào cache và trả về
        do {
            try sessionManager.validateSessionContext(capturedContext)
        } catch {
            try? fileManager.removeItem(at: targetDir.appendingPathComponent(rawFileName))
            throw error
        }

        let scopedPath = "\(ownerId)/\(rawFileName)"
        memoryCache.setObject(image, forKey: scopedPath as NSString)
        return scopedPath
    }

    /// Tải ảnh UIImage từ đường dẫn tương đối (Kiểm tra chặt quyền sở hữu `ownerId` trước khi trả về từ cache hoặc đĩa)
    public func loadImage(named relativePath: String) -> UIImage? {
        guard let (ownerId, fileName) = try? sessionManager.verifyAndExtractFileName(from: relativePath) else {
            return nil
        }

        let cacheKey = "\(ownerId)/\(fileName)" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) as? UIImage {
            return cached
        }

        let fileURL = mediaDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }
        memoryCache.setObject(image, forKey: cacheKey)
        return image
    }
    #endif

    /// Xóa một file ảnh minh chứng (Chỉ cho phép xóa nếu đúng chủ sở hữu hiện tại)
    public func deleteImage(named relativePath: String) {
        guard let (ownerId, fileName) = try? sessionManager.verifyAndExtractFileName(from: relativePath) else {
            return
        }
        let cacheKey = "\(ownerId)/\(fileName)" as NSString
        memoryCache.removeObject(forKey: cacheKey)
        let fileURL = mediaDirectoryURL(for: ownerId).appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Dọn dẹp các file mồ côi trong phân vùng của user hiện tại
    public func cleanupOrphanFiles(validFileNames: Set<String>) async {
        let currentOwner = UserSessionManager.sanitizeIdentifier(sessionManager.currentOwnerId)
        let mediaDir = mediaDirectoryURL(for: currentOwner)
        let normalizedValid: Set<String> = Set(validFileNames.compactMap { path in
            if let (owner, name) = try? sessionManager.verifyAndExtractFileName(from: path, expectedOwnerId: currentOwner),
               owner == currentOwner {
                return name
            }
            return nil
        })

        await Task.detached(priority: .utility) { [fm = self.fileManager] in
            guard let contents = try? fm.contentsOfDirectory(atPath: mediaDir.path) else { return }
            for file in contents {
                if !normalizedValid.contains(file) {
                    let fileURL = mediaDir.appendingPathComponent(file)
                    try? fm.removeItem(at: fileURL)
                }
            }
        }.value
    }
}

public enum PhotoStorageError: Error, LocalizedError {
    case compressionFailed
    case fileWriteFailed

    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Không thể nén dữ liệu ảnh."
        case .fileWriteFailed:
            return "Không thể ghi tệp ảnh vào bộ nhớ ứng dụng."
        }
    }
}
