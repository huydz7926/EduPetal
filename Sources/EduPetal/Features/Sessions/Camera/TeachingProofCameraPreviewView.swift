import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit

/// View hiển thị luồng video thời gian thực từ camera (AVCaptureVideoPreviewLayer)
public struct TeachingProofCameraPreviewView: UIViewRepresentable {
    #if canImport(AVFoundation)
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
    #else
    public init() {}
    public func makeUIView(context: Context) -> UIView { UIView() }
    public func updateUIView(_ uiView: UIView, context: Context) {}
    #endif
}

#if canImport(AVFoundation)
public final class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
#endif
#endif

