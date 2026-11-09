import SwiftUI
#if canImport(UIKit)
import UIKit

/// Gói ảnh để mở trình chỉnh sửa bằng `fullScreenCover(item:)` hoặc `sheet(item:)`
public struct AvatarEditItem: Identifiable {
    public let id = UUID()
    public let image: UIImage
    public init(image: UIImage) { self.image = image }
}

/// Trình chỉnh ảnh đại diện (kéo, phóng to/thu nhỏ, xoay trong khung tròn — tương tự Meta)
public struct AvatarEditorView: View {
    private let outputSize: CGFloat = 512

    @State private var baseImage: UIImage
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropDiameter: CGFloat = 280

    private let onCancel: () -> Void
    private let onDone: (UIImage) -> Void

    public init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onDone: @escaping (UIImage) -> Void
    ) {
        _baseImage = State(initialValue: Self.normalized(image))
        self.onCancel = onCancel
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let diameter = min(geo.size.width - 40, 310)

                VStack(spacing: 0) {
                    // Khung cắt ảnh tròn ở trung tâm màn hình
                    ZStack {
                        Color.black

                        cropCanvas(diameter: diameter)
                            .frame(width: geo.size.width, height: diameter + 36)
                    }
                    .frame(height: diameter + 36)
                    .clipped()

                    // Khu vực thanh trượt thu phóng, xoay và nút xác nhận nằm gọn ở nửa dưới màn hình (dễ bấm bằng 1 tay)
                    VStack(spacing: 18) {
                        Text(L("Kéo để di chuyển • Chụm 2 ngón hoặc kéo thanh trượt để phóng to", "Drag to move • Pinch or slide to zoom"))
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 14) {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(AppColors.secondaryText)
                            Slider(value: zoomBinding(diameter: diameter), in: 1...4)
                                .tint(AppColors.accentRose)
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        HStack(spacing: 12) {
                            toolButton(L("Xoay 90°", "Rotate 90°"), icon: "rotate.right") { rotate() }
                            toolButton(L("Đặt lại", "Reset"), icon: "arrow.counterclockwise") { reset() }
                        }

                        // Cụm nút Hủy / Lưu ảnh đặt ở vị trí thấp vừa tầm ngón cái, không bao giờ vướng Dynamic Island / tai thỏ
                        HStack(spacing: 12) {
                            Button(action: onCancel) {
                                Text(L("Hủy", "Cancel"))
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColors.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(AppColors.surfaceCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppColors.divider, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                finish()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text(L("Lưu ảnh đại diện", "Save Avatar"))
                                }
                                .font(AppTypography.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(AppColors.primaryPink)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    Spacer(minLength: 12)
                }
                .background(AppColors.background.ignoresSafeArea())
                .onAppear { cropDiameter = diameter }
                .onChange(of: geo.size) { _, _ in cropDiameter = diameter }
            }
            .navigationTitle(L("Chỉnh ảnh đại diện", "Edit Avatar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Hủy", "Cancel"), action: onCancel)
                        .foregroundStyle(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Xong", "Done")) {
                        finish()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.accentRose)
                }
            }
        }
    }

    // MARK: - Subviews

    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func cropCanvas(diameter: CGFloat) -> some View {
        let scale = displayScale(diameter: diameter)
        let size = baseImage.size

        return ZStack {
            Image(uiImage: baseImage)
                .resizable()
                .frame(width: size.width * scale, height: size.height * scale)
                .offset(offset)

            // Lớp phủ tối với lỗ tròn ở giữa
            Rectangle()
                .fill(Color.black.opacity(0.62))
                .reverseMask {
                    Circle().frame(width: diameter, height: diameter)
                }
                .allowsHitTesting(false)

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(diameter: diameter))
        .simultaneousGesture(magnifyGesture(diameter: diameter))
    }

    // MARK: - Gestures

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    ),
                    diameter: diameter
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func magnifyGesture(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(lastZoom * value.magnification, 1), 4)
                offset = clamped(offset, diameter: diameter)
            }
            .onEnded { _ in
                lastZoom = zoom
                lastOffset = offset
            }
    }

    private func zoomBinding(diameter: CGFloat) -> Binding<CGFloat> {
        Binding(
            get: { zoom },
            set: { newValue in
                zoom = newValue
                lastZoom = newValue
                offset = clamped(offset, diameter: diameter)
                lastOffset = offset
            }
        )
    }

    // MARK: - Geometry

    /// Tỉ lệ để ảnh vừa phủ kín khung tròn ở mức zoom 1
    private func displayScale(diameter: CGFloat) -> CGFloat {
        let minSide = max(min(baseImage.size.width, baseImage.size.height), 1)
        return diameter / minSide * zoom
    }

    /// Giữ ảnh luôn phủ kín khung tròn (không lộ nền trống)
    private func clamped(_ value: CGSize, diameter: CGFloat) -> CGSize {
        let scale = displayScale(diameter: diameter)
        let maxX = max((baseImage.size.width * scale - diameter) / 2, 0)
        let maxY = max((baseImage.size.height * scale - diameter) / 2, 2)
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    // MARK: - Actions

    private func reset() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = 1
            lastZoom = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    private func rotate() {
        baseImage = Self.rotated90(baseImage)
        offset = .zero
        lastOffset = .zero
    }

    private func finish() {
        let diameter = cropDiameter
        let scale = displayScale(diameter: diameter)
        let ratio = outputSize / diameter
        let drawW = baseImage.size.width * scale * ratio
        let drawH = baseImage.size.height * scale * ratio
        let originX = outputSize / 2 - drawW / 2 + offset.width * ratio
        let originY = outputSize / 2 - drawH / 2 + offset.height * ratio

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize), format: format)
        let result = renderer.image { _ in
            baseImage.draw(in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
        }
        onDone(result)
    }

    // MARK: - Image helpers

    /// Chuẩn hóa hướng ảnh (EXIF) và giới hạn kích thước để chỉnh sửa mượt
    private static func normalized(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let ratio = longest > maxSide ? maxSide / longest : 1
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func rotated90(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }
}

private extension View {
    /// Cắt một lỗ (mask đảo) trên view hiện tại
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        )
    }
}
#endif
