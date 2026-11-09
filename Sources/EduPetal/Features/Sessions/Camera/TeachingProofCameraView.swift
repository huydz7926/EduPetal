import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Màn hình Camera chụp ảnh minh chứng buổi dạy theo phong cách Rose & Cream sắc nét, độ tương phản cao
public struct TeachingProofCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraService = TeachingProofCameraService()

    public let session: TeachingSessionEntity
    public let className: String
    public let onPhotoConfirmed: (String, String) -> Void // (fileName, note)

    @State private var noteText: String = ""
    @State private var isNoteExpanded: Bool = true
    @FocusState private var isNoteFocused: Bool
    @State private var isSaving: Bool = false
    @State private var isShowingSettingsAlert: Bool = false

    public init(
        session: TeachingSessionEntity,
        className: String,
        initialNote: String = "",
        onPhotoConfirmed: @escaping (String, String) -> Void
    ) {
        self.session = session
        self.className = className
        self._noteText = State(initialValue: initialNote)
        self.onPhotoConfirmed = onPhotoConfirmed
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                #if canImport(UIKit)
                if let captured = cameraService.capturedImage {
                    // MARK: - Post-capture Review & Note Screen (Màn hình xem lại & ghi chú)
                    reviewScreen(image: captured)
                } else {
                    // MARK: - Live Camera Viewfinder (Khung chụp 1:1)
                    liveViewfinderScreen
                }
                #else
                Text("Camera chỉ hỗ trợ trên iOS")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                #endif
            }
            #if canImport(UIKit)
            .navigationTitle(cameraService.capturedImage == nil ? "Chụp ảnh minh chứng" : "Xem lại ảnh minh chứng")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationTitle("Chụp ảnh minh chứng")
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismissKeyboard()
                        cameraService.stopSession()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Đóng")
                                .font(AppTypography.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(AppColors.accentRose)
                    }
                }
            }
            .alert("Quyền truy cập Camera bị từ chối", isPresented: $isShowingSettingsAlert) {
                #if canImport(UIKit)
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
                Button("Đóng", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("EduPetal cần quyền truy cập Camera để chụp ảnh minh chứng buổi dạy. Vui lòng cấp quyền trong Cài đặt iPhone.")
            }
            .onAppear {
                cameraService.checkPermissions()
                if cameraService.isPermissionDenied {
                    isShowingSettingsAlert = true
                }
            }
            .onChange(of: cameraService.isPermissionDenied) { _, denied in
                if denied {
                    isShowingSettingsAlert = true
                }
            }
            #if canImport(UIKit)
            .onChange(of: cameraService.capturedImage) { _, newImage in
                if newImage != nil {
                    // Khi vừa chụp xong, mở sẵn khung ghi chú nhưng không tự bật bàn phím gây che ảnh
                    isNoteExpanded = true
                    isNoteFocused = false
                }
            }
            #endif
            .onDisappear {
                cameraService.stopSession()
            }
        }
    }

    private func dismissKeyboard() {
        isNoteFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: - Live Viewfinder Screen

    #if canImport(UIKit)
    private var liveViewfinderScreen: some View {
        VStack(spacing: AppSpacing.md) {
            // Thẻ thông tin buổi dạy sắc nét, chữ đậm dễ đọc
            headerInfoCard
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)

            Spacer(minLength: 4)

            // Khung ngắm chụp vuông 1:1 chuẩn Locket
            ZStack {
                if cameraService.isCameraAvailable {
                    #if canImport(AVFoundation)
                    TeachingProofCameraPreviewView(session: cameraService.session)
                        .clipped()
                    #endif
                } else {
                    // Khung giả lập cho Simulator với chữ trắng sắc nét trên nền đậm
                    LinearGradient(
                        colors: [Color(hex: "#392D33"), Color(hex: "#523B45")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundColor(AppColors.primaryPink)
                        Text("Chế độ mô phỏng Camera")
                            .font(AppTypography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Bấm nút Chụp ảnh bên dưới để tạo ảnh minh chứng mẫu")
                            .font(AppTypography.subheadline)
                            .foregroundColor(Color.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                }

                // Khung viền căn chỉnh 1:1 sắc nét
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(AppColors.primaryPink, lineWidth: 2.5)

                // Nhãn hướng dẫn & mức zoom nổi bật
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("KHUNG VUÔNG 1:1")
                                .font(AppTypography.font(size: 11))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())

                        Spacer()
                    }
                    .padding(AppSpacing.sm)

                    Spacer()

                    // Nút chọn mức Zoom (0.5x, 1x, 2x) độ tương phản cao ngay trong khung ngắm
                    #if canImport(AVFoundation)
                    if cameraService.availableZoomFactors.count > 1 {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(cameraService.availableZoomFactors, id: \.self) { factor in
                                let isSelected = cameraService.currentZoomFactor == factor
                                Button {
                                    triggerHaptic()
                                    cameraService.setZoomFactor(factor)
                                } label: {
                                    Text(factor == 0.5 ? "0.5x" : String(format: "%.0fx", factor))
                                        .font(AppTypography.font(size: 13))
                                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.95))
                                        .frame(width: 42, height: 32)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? AppColors.accentRose : Color.black.opacity(0.72))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? Color.white : Color.white.opacity(0.35), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.bottom, AppSpacing.xs)
                    }
                    #endif

                    // Nhắc nhở bảo mật với nền đậm, chữ trắng rõ nét 100%
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.secondaryPink)
                        Text("Chỉ chụp không gian lớp học hoặc bài vở")
                            .font(AppTypography.font(size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, AppSpacing.sm)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, AppSpacing.md)

            Spacer(minLength: 4)

            // Thanh điều khiển chụp ảnh dưới cùng rõ ràng kèm nhãn tiếng Việt
            bottomControlsBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
        }
    }

    private var headerInfoCard: some View {
        AppCard {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppColors.secondaryPink)
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.accentRose)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(className)
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.accentRose))
                            .foregroundColor(.white)

                        Text(session.title)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.accentRose)
                        Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(AppTypography.caption1)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                Spacer()
            }
        }
    }

    private var bottomControlsBar: some View {
        HStack(alignment: .center) {
            // Nút Đèn Flash
            #if canImport(AVFoundation)
            if cameraService.isFlashSupported {
                Button {
                    triggerHaptic()
                    cameraService.toggleFlash()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(cameraService.flashMode == .on ? AppColors.warningBackground : AppColors.surfaceCard)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Circle()
                                        .stroke(cameraService.flashMode == .on ? AppColors.warning : AppColors.divider, lineWidth: 1.5)
                                )
                            Image(systemName: flashIconName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(cameraService.flashMode == .on ? AppColors.warning : AppColors.primaryText)
                        }
                        Text(flashLabelText)
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                .frame(width: 72)
            } else {
                Spacer().frame(width: 72)
            }
            #else
            Spacer().frame(width: 72)
            #endif

            Spacer()

            // Nút Chụp chính ở giữa
            Button {
                triggerHaptic()
                cameraService.capturePhoto()
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.accentRose, lineWidth: 4)
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(cameraService.isCapturingPhoto ? AppColors.primaryPink.opacity(0.5) : AppColors.primaryPink)
                            .frame(width: 66, height: 66)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(cameraService.isCapturingPhoto ? "Đang chụp..." : "Chụp ảnh")
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.accentRose)
                }
            }
            .disabled(cameraService.isCapturingPhoto)

            Spacer()

            // Nút Lật Camera
            Button {
                triggerHaptic()
                cameraService.flipCamera()
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(AppColors.surfaceCard)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Circle()
                                    .stroke(AppColors.divider, lineWidth: 1.5)
                            )
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                    }
                    Text("Lật cam")
                        .font(AppTypography.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.primaryText)
                }
            }
            .frame(width: 72)
            .disabled(cameraService.isCapturingPhoto)
        }
    }

    // MARK: - Post-Capture Review & Note Screen

    private func reviewScreen(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // Thẻ thông tin buổi dạy gọn gàng
                headerInfoCard
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.xs)

                // Ảnh vừa chụp (Tỷ lệ 1:1): Bấm vào ảnh để thôi ghi chú / đóng bàn phím ngay lập tức
                ZStack(alignment: .bottom) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg)
                                .stroke(AppColors.primaryPink.opacity(0.5), lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                    // Nhãn hướng dẫn tương tác trực tiếp trên ảnh
                    HStack(spacing: 6) {
                        Image(systemName: isNoteExpanded ? "hand.tap.fill" : "square.and.pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text(isNoteExpanded ? "Chạm vào ảnh để thôi ghi chú" : (noteText.isEmpty ? "Chạm vào ảnh để thêm ghi chú" : "Đã có ghi chú • Chạm để sửa"))
                            .font(AppTypography.font(size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.md)
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerHaptic()
                    if isNoteFocused || isNoteExpanded {
                        // Khi bấm lại vào ảnh: tắt bàn phím và thu gọn/thôi ghi chú ngay
                        dismissKeyboard()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isNoteExpanded = false
                        }
                    } else {
                        // Bấm lại lần nữa nếu muốn mở lại ô ghi chú
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isNoteExpanded = true
                        }
                    }
                }

                // Khung Ghi chú buổi dạy (Sắc nét, dễ đọc, có thể ẩn/bỏ ngay khi bấm vào ảnh hoặc nút Thôi ghi chú)
                if isNoteExpanded {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack {
                                Label("Ghi chú ảnh minh chứng", systemImage: "note.text")
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.primaryText)

                                Spacer()

                                Text("\(noteText.count)/300")
                                    .font(AppTypography.caption1)
                                    .fontWeight(.semibold)
                                    .foregroundColor(noteText.count >= 300 ? AppColors.error : AppColors.secondaryText)

                                Button {
                                    triggerHaptic()
                                    noteText = ""
                                    dismissKeyboard()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                        isNoteExpanded = false
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                        Text("Thôi ghi chú")
                                            .font(AppTypography.caption1)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(AppColors.surfaceSubtle))
                                    .foregroundColor(AppColors.accentRose)
                                }
                            }

                            TextField(
                                "Nhập nội dung bài học, nhận xét hoặc dặn dò (không bắt buộc)...",
                                text: $noteText,
                                axis: .vertical
                            )
                            .focused($isNoteFocused)
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(2...4)
                            .padding(AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .fill(AppColors.surfaceSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .stroke(isNoteFocused ? AppColors.accentRose : AppColors.divider, lineWidth: 1.5)
                            )
                            .onChange(of: noteText) { _, newVal in
                                if newVal.count > 300 {
                                    noteText = String(newVal.prefix(300))
                                }
                            }

                            Text("Mẹo: Bạn có thể chạm trực tiếp vào bức ảnh phía trên để đóng ghi chú bất cứ lúc nào.")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // Thanh trạng thái khi đã thôi ghi chú
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isNoteExpanded = true
                            isNoteFocused = true
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: noteText.isEmpty ? "plus.bubble.fill" : "text.bubble.fill")
                                .foregroundColor(AppColors.accentRose)
                            Text(noteText.isEmpty ? "Không kèm ghi chú (Bấm để thêm ghi chú nếu cần)" : "Ghi chú: \(noteText)")
                                .font(AppTypography.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            if !noteText.isEmpty {
                                Button {
                                    noteText = ""
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(AppColors.error)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .fill(AppColors.surfaceCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .stroke(AppColors.divider, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, AppSpacing.md)
                }

                // 2 Nút thao tác lớn: Chụp lại & Dùng ảnh này
                HStack(spacing: AppSpacing.md) {
                    SecondaryButton("Chụp lại", icon: "arrow.clockwise") {
                        dismissKeyboard()
                        cameraService.capturedImage = nil
                        cameraService.startSession()
                    }

                    PrimaryButton(
                        isSaving ? "Đang lưu..." : "Lưu ảnh minh chứng",
                        icon: "checkmark.circle.fill",
                        isEnabled: !isSaving
                    ) {
                        dismissKeyboard()
                        saveAndConfirmPhoto()
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func saveAndConfirmPhoto() {
        guard let image = cameraService.capturedImage, !isSaving else { return }
        isSaving = true
        cameraService.stopSession()
        let finalNote = isNoteExpanded ? noteText.trimmingCharacters(in: .whitespacesAndNewlines) : noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let fileName = try await PhotoStorageService.shared.saveImage(image, forSessionId: session.id)
                await MainActor.run {
                    onPhotoConfirmed(fileName, finalNote)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }

    #if canImport(AVFoundation)
    private var flashIconName: String {
        switch cameraService.flashMode {
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off:  return "bolt.slash.fill"
        @unknown default: return "bolt.fill"
        }
    }

    private var flashLabelText: String {
        switch cameraService.flashMode {
        case .on:   return "Bật Flash"
        case .auto: return "Tự động"
        case .off:  return "Tắt Flash"
        @unknown default: return "Flash"
        }
    }
    #endif

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    #endif
}
