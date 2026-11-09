import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình xem lớn và thu phóng ảnh minh chứng buổi dạy kèm ghi chú chi tiết
public struct ProofPhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss

    public let attachment: SessionAttachmentEntity
    public let sessionTitle: String
    public let className: String

    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0

    public init(
        attachment: SessionAttachmentEntity,
        sessionTitle: String,
        className: String
    ) {
        self.attachment = attachment
        self.sessionTitle = sessionTitle
        self.className = className
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        // Thông tin buổi dạy & thời gian chụp
                        AppCard {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(AppColors.accentRose)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(className) • \(sessionTitle)")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)

                                    Text("Chụp lúc: \(attachment.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)

                        #if canImport(UIKit)
                        if let uiImage = PhotoStorageService.shared.loadImage(named: attachment.filePath) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.lg)
                                        .stroke(AppColors.primaryPink.opacity(0.4), lineWidth: 1.5)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                .scaleEffect(currentScale * finalScale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            currentScale = value
                                        }
                                        .onEnded { value in
                                            finalScale = max(1.0, min(finalScale * value, 4.0))
                                            currentScale = 1.0
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring()) {
                                        finalScale = (finalScale > 1.0) ? 1.0 : 2.0
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                        } else {
                            // Fallback icon khi không tìm thấy tệp ảnh
                            AppCard {
                                VStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.system(size: 56))
                                        .foregroundColor(AppColors.accentRose)
                                    Text("Ảnh minh chứng cục bộ")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xl)
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                        #endif

                        // Ghi chú đính kèm của ảnh
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "text.quote")
                                        .foregroundColor(AppColors.accentRose)
                                    Text("Ghi chú ảnh minh chứng")
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.primaryText)
                                    Spacer()
                                }

                                Text(attachment.caption.isEmpty ? "Không có ghi chú đính kèm cho bức ảnh này." : attachment.caption)
                                    .font(AppTypography.body)
                                    .foregroundColor(attachment.caption.isEmpty ? AppColors.secondaryText : AppColors.primaryText)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationTitle("Chi tiết ảnh minh chứng")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accentRose)
                }
            }
        }
    }
}
