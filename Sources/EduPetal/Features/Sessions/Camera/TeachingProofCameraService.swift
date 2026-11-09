#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif
import SwiftUI

/// Dịch vụ quản lý phần cứng Camera cho Ảnh minh chứng lớp học (Lấy cảm hứng từ SnapSpend & trải nghiệm Locket)
@MainActor
public final class TeachingProofCameraService: NSObject, ObservableObject {
    @Published public var isSessionRunning = false
    @Published public var isCameraAvailable = false
    @Published public var isPermissionDenied = false
    @Published public var isCapturingPhoto = false
    #if canImport(UIKit)
    @Published public var capturedImage: UIImage? = nil
    #endif

    #if canImport(AVFoundation)
    @Published public var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published public var isFlashSupported: Bool = false
    @Published public var currentPosition: AVCaptureDevice.Position = .back
    @Published public var availableZoomFactors: [CGFloat] = [1.0]
    @Published public var currentZoomFactor: CGFloat = 1.0

    nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated(unsafe) let photoOutput = AVCapturePhotoOutput()
    private nonisolated(unsafe) var videoDeviceInput: AVCaptureDeviceInput?
    private nonisolated(unsafe) var isSessionConfigured = false
    /// Hệ số zoom cơ sở của ống kính 1x (trên cụm DualWide/Triple camera của iPhone, 1x tương ứng hệ số phần cứng 2.0)
    private nonisolated(unsafe) var baseWideZoomFactor: CGFloat = 1.0
    private let sessionQueue = DispatchQueue(label: "com.edupetal.cameraSessionQueue", qos: .userInitiated)
    #endif

    public override init() {
        super.init()
    }

    // MARK: - Permissions

    public func checkPermissions() {
        #if canImport(AVFoundation)
        // Bảo đảm Info.plist có NSCameraUsageDescription trước khi gọi API phần cứng để tránh TCC SIGABRT
        guard Self.hasCameraUsageDescriptionInBundle() else {
            isPermissionDenied = true
            isCameraAvailable = false
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isPermissionDenied = false
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.isPermissionDenied = false
                        self.setupSession()
                    } else {
                        self.isPermissionDenied = true
                        self.isCameraAvailable = false
                    }
                }
            }
        case .denied, .restricted:
            isPermissionDenied = true
            isCameraAvailable = false
        @unknown default:
            isCameraAvailable = false
        }
        #else
        isCameraAvailable = false
        #endif
    }

    /// Kiểm tra khóa NSCameraUsageDescription trong Info.plist của ứng dụng
    nonisolated public static func hasCameraUsageDescriptionInBundle(_ bundle: Bundle = .main) -> Bool {
        if let desc = bundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        // Khi chạy trong môi trường SwiftPM test bundle không phải .app host, cho phép kiểm thử logic
        if bundle.bundlePath.hasSuffix(".xctest") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return false
    }

    // MARK: - Session Setup (Serialized on sessionQueue)

    public func setupSession(forceReconfigure: Bool = false) {
        #if canImport(AVFoundation)
        let desiredPosition = currentPosition
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.isSessionConfigured && !forceReconfigure {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                Task { @MainActor [weak self] in
                    self?.isCameraAvailable = true
                    self?.isSessionRunning = running
                }
                return
            }

            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.photo) {
                self.session.sessionPreset = .photo
            }

            if let oldInput = self.videoDeviceInput {
                self.session.removeInput(oldInput)
                self.videoDeviceInput = nil
            }

            guard let device = Self.selectDevice(for: desiredPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                self.isSessionConfigured = false
                Task { @MainActor [weak self] in
                    self?.isCameraAvailable = false
                    self?.isSessionRunning = false
                }
                return
            }

            self.session.addInput(input)
            self.videoDeviceInput = input

            if !self.session.outputs.contains(self.photoOutput) {
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
            }

            // Chỉ cấu hình maxPhotoDimensions từ danh sách được activeFormat hỗ trợ hợp lệ trên thiết bị thật
            if #available(iOS 16.0, *) {
                if let validDimension = Self.selectSupportedMaxPhotoDimensions(for: device) {
                    self.photoOutput.maxPhotoDimensions = validDimension
                }
            }

            let capabilities = Self.resolveCapabilities(for: device, position: desiredPosition)
            self.baseWideZoomFactor = capabilities.baseZoomFactor

            // Đặt mức zoom mặc định về ống kính 1x (tránh bị mặc định ở góc siêu rộng 0.5x trên cụm Triple/DualWide)
            Self.applyHardwareZoom(uiFactor: 1.0, baseZoomFactor: capabilities.baseZoomFactor, on: device)

            self.session.commitConfiguration()
            self.isSessionConfigured = true

            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCameraAvailable = true
                self.isSessionRunning = running
                self.availableZoomFactors = capabilities.zoomFactors
                self.isFlashSupported = capabilities.isFlashSupported
                if !capabilities.isFlashSupported {
                    self.flashMode = .off
                }
                self.currentZoomFactor = 1.0
            }
        }
        #else
        isCameraAvailable = false
        #endif
    }

    public func startSession() {
        #if canImport(AVFoundation)
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor [weak self] in
                self?.isSessionRunning = running
            }
        }
        #endif
    }

    public func stopSession() {
        #if canImport(AVFoundation)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
                self?.isCapturingPhoto = false
            }
        }
        #endif
    }

    // MARK: - Device Discovery & Capabilities

    #if canImport(AVFoundation)
    nonisolated private static func selectDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        #if os(iOS)
        if position == .front {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        #else
        return AVCaptureDevice.default(for: .video)
        #endif
    }

    /// Chọn kích thước ảnh tối đa hợp lệ nằm trong `device.activeFormat.supportedMaxPhotoDimensions`
    /// Tuyệt đối không gán kích thước tùy ý (như 3024x3024) gây văng `NSInvalidArgumentException` trên iOS 16+
    @available(iOS 16.0, macOS 13.0, *)
    nonisolated public static func selectSupportedMaxPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard !supported.isEmpty else { return nil }
        // Ưu tiên độ phân giải chuẩn ~12MP ( <= 4032x3024 ) để vừa sắc nét vừa tiết kiệm bộ nhớ, nếu không có thì lấy phần tử hợp lệ đầu tiên
        let preferred = supported.filter { Int($0.width) * Int($0.height) <= 4032 * 3024 }
        if let bestStandard = preferred.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            return bestStandard
        }
        return supported.first
    }

    nonisolated private static func resolveCapabilities(
        for device: AVCaptureDevice,
        position: AVCaptureDevice.Position
    ) -> (zoomFactors: [CGFloat], baseZoomFactor: CGFloat, isFlashSupported: Bool) {
        #if os(iOS)
        if position == .back {
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
            let hasUltraWide = (device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera) && !switchOvers.isEmpty
            let baseZoom: CGFloat = hasUltraWide ? (switchOvers.first ?? 2.0) : 1.0
            let factors: [CGFloat] = hasUltraWide ? [0.5, 1.0, 2.0] : [1.0, 2.0]
            return (factors, baseZoom, device.hasFlash)
        } else {
            return ([1.0], 1.0, false)
        }
        #else
        return ([1.0], 1.0, false)
        #endif
    }

    nonisolated private static func applyHardwareZoom(
        uiFactor: CGFloat,
        baseZoomFactor: CGFloat,
        on device: AVCaptureDevice
    ) {
        #if os(iOS)
        do {
            try device.lockForConfiguration()
            let rawTarget = uiFactor * baseZoomFactor
            let minZoom = max(1.0, device.minAvailableVideoZoomFactor)
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
            let clamped = max(minZoom, min(rawTarget, maxZoom))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
        #endif
    }

    public func flipCamera() {
        guard !isCapturingPhoto else { return }
        currentPosition = (currentPosition == .back) ? .front : .back
        setupSession(forceReconfigure: true)
    }

    public func toggleFlash() {
        guard isFlashSupported else { return }
        switch flashMode {
        case .auto: flashMode = .on
        case .on:   flashMode = .off
        case .off:  flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    public func setZoomFactor(_ factor: CGFloat) {
        currentZoomFactor = factor
        #if os(iOS)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            Self.applyHardwareZoom(uiFactor: factor, baseZoomFactor: self.baseWideZoomFactor, on: device)
        }
        #endif
    }

    public func capturePhoto() {
        guard !isCapturingPhoto else { return }

        guard isCameraAvailable else {
            #if canImport(UIKit)
            simulateCaptureForTesting()
            #endif
            return
        }

        isCapturingPhoto = true
        let desiredFlash = self.flashMode
        let flashAllowed = self.isFlashSupported

        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard self.session.isRunning,
                  let connection = self.photoOutput.connection(with: .video),
                  connection.isEnabled,
                  connection.isActive else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isCapturingPhoto = false
                    #if canImport(UIKit)
                    if !self.isCameraAvailable {
                        self.simulateCaptureForTesting()
                    }
                    #endif
                }
                return
            }

            let settings = AVCapturePhotoSettings()
            let supportedFlashModes = self.photoOutput.supportedFlashModes
            if flashAllowed && supportedFlashModes.contains(desiredFlash) {
                settings.flashMode = desiredFlash
            } else if supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }

            if #available(iOS 16.0, *) {
                let maxDim = self.photoOutput.maxPhotoDimensions
                if maxDim.width > 0 && maxDim.height > 0 {
                    settings.maxPhotoDimensions = maxDim
                }
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    #endif

    #if canImport(UIKit)
    /// Trình giả lập ảnh minh chứng phục vụ kiểm thử Simulator
    public func simulateCaptureForTesting() {
        let size = CGSize(width: 800, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor(red: 232/255, green: 143/255, blue: 168/255, alpha: 1.0).cgColor,
                          UIColor(red: 248/255, green: 220/255, blue: 229/255, alpha: 1.0).cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0])!
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 800, y: 800), options: [])

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let text = "EduPetal\nẢnh minh chứng lớp học"
            (text as NSString).draw(in: CGRect(x: 50, y: 350, width: 700, height: 100), withAttributes: attrs)
        }
        self.isCapturingPhoto = false
        self.capturedImage = image
    }

    /// Cắt ảnh theo khung vuông 1:1 chuẩn hóa chiều hướng (.up) và giới hạn kích thước tối ưu bộ nhớ (tối đa 1440x1440 px)
    nonisolated public static func cropToSquare(image: UIImage, maxDimension: CGFloat = 1440) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let minSide = min(pixelWidth, pixelHeight)
        guard minSide > 0 else { return image }

        let targetSide = min(minSide, maxDimension)
        let scaleFactor = targetSide / minSide
        let drawWidth = pixelWidth * scaleFactor
        let drawHeight = pixelHeight * scaleFactor
        let drawX = (targetSide - drawWidth) / 2.0
        let drawY = (targetSide - drawHeight) / 2.0

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))
        }
    }
    #endif
}

#if canImport(AVFoundation)
extension TeachingProofCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        #if canImport(UIKit)
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let originalImage = UIImage(data: data) else {
            Task { @MainActor in
                self.isCapturingPhoto = false
            }
            return
        }

        let squareImage = TeachingProofCameraService.cropToSquare(image: originalImage)
        Task { @MainActor in
            self.isCapturingPhoto = false
            self.capturedImage = squareImage
        }
        #else
        Task { @MainActor in
            self.isCapturingPhoto = false
        }
        #endif
    }
}
#endif
