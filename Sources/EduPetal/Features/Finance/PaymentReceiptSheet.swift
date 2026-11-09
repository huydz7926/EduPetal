import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Chi tiết Hóa đơn / Phiếu thu học phí chuyên nghiệp
public struct PaymentReceiptSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let payment: PaymentEntity
    public let viewModel: FinanceViewModel

    @State private var allocations: [PaymentAllocationEntity] = []
    @State private var isLoadingAllocations: Bool = true
    @State private var showCopiedToast: Bool = false
    @State private var receiptPDFURL: URL? = nil

    public init(payment: PaymentEntity, viewModel: FinanceViewModel) {
        self.payment = payment
        self.viewModel = viewModel
    }

    private var studentName: String {
        viewModel.studentName(for: payment.studentId)
    }

    private var receiptCode: String {
        "#REC-\(payment.id.uuidString.prefix(8).uppercased())"
    }

    private var snapshotRemainingBalance: Int64 {
        viewModel.snapshotRemainingBalanceAfterPayment(payment)
    }

    private var currentOutstanding: Int64 {
        viewModel.outstandingBalance(for: payment.studentId)
    }

    private var receiptText: String {
        let sessionLines = allocations.enumerated().map { idx, alloc -> String in
            let charge = viewModel.charge(for: alloc.chargeId)
            let title = charge != nil ? viewModel.sessionTitle(for: charge!.sessionId) : "Buổi học"
            let sDate = charge != nil ? viewModel.effectiveSessionDate(for: charge!) : alloc.allocatedAt
            return "  \(idx + 1). \(title) (\(sDate.formatted(date: .numeric, time: .omitted))): \(alloc.allocatedAmount.formattedVND)"
        }.joined(separator: "\n")

        return """
        ━━━━━━━━━━━━━━━━━━━━━━
        PHIẾU THU & BẢNG KÊ HỌC PHÍ
        Hệ thống quản lý lớp học EduPetal
        ━━━━━━━━━━━━━━━━━━━━━━
        • Số chứng từ: \(receiptCode)
        • Học sinh: \(studentName)
        • Ngày thanh toán: \(payment.paidAt.formatted(date: .numeric, time: .shortened))
        • Phương thức: \(payment.paymentMethod)
        \(sessionLines.isEmpty ? "" : "──────────────────────\nChi tiết các buổi học:\n\(sessionLines)\n")──────────────────────
        • TỔNG ĐÃ THU: \(payment.amount.formattedVND)
        • Dư nợ còn lại: \(snapshotRemainingBalance.formattedVND)
        \(payment.note.isEmpty ? "" : "• Ghi chú: \(payment.note)\n")━━━━━━━━━━━━━━━━━━━━━━
        Trân trọng cảm ơn Quý Phụ huynh & Học sinh!
        """
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        // MARK: - 1. Khung Header Hóa đơn Chuyên nghiệp
                        VStack(spacing: 0) {
                            // Dải màu thương hiệu trên đỉnh hóa đơn
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("EDUPETAL EDUCATION")
                                        .font(AppTypography.font(size: 11))
                                        .foregroundColor(.white.opacity(0.88))
                                        .tracking(1.0)
                                    Text("PHIẾU THU HỌC PHÍ")
                                        .font(AppTypography.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(receiptCode)
                                        .font(AppTypography.font(size: 12))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.2)))
                                        .foregroundColor(.white)
                                    Text("Đã xác nhận")
                                        .font(AppTypography.font(size: 11))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            .padding(16)
                            .background(AppColors.primaryPink)

                            // Phần Tổng tiền nổi bật
                            VStack(spacing: 6) {
                                Text("SỐ TIỀN ĐÃ THANH TOÁN")
                                    .font(AppTypography.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.secondaryText)
                                    .tracking(0.8)

                                Text(payment.amount.formattedVND)
                                    .font(AppTypography.font(size: 32))
                                    .foregroundColor(AppColors.success)

                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.success)
                                    Text("Ngày thu: \(payment.paidAt.formatted(date: .numeric, time: .shortened))")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppColors.surfaceCard)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)

                        // MARK: - 2. Thông tin Học sinh & Thanh toán
                        AppCard {
                            VStack(spacing: 10) {
                                invoiceRow(label: "Học sinh", value: studentName, isBold: true)
                                Divider().background(AppColors.divider)
                                invoiceRow(label: "Phương thức thanh toán", value: payment.paymentMethod)
                                Divider().background(AppColors.divider)
                                invoiceRow(
                                    label: "Dư nợ còn lại sau thu",
                                    value: snapshotRemainingBalance.formattedVND,
                                    valueColor: snapshotRemainingBalance > 0 ? AppColors.warning : AppColors.success,
                                    isBold: true
                                )
                                if !payment.note.isEmpty {
                                    Divider().background(AppColors.divider)
                                    invoiceRow(label: "Nội dung / Ghi chú", value: payment.note)
                                }
                            }
                        }

                        // MARK: - 3. Bảng kê chi tiết các buổi học
                        AppCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Bảng kê buổi học thanh toán (\(allocations.count))", systemImage: "list.bullet.rectangle.portrait")
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.primaryText)
                                    Spacer()
                                }

                                if isLoadingAllocations {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppSpacing.sm)
                                } else if allocations.isEmpty {
                                    Text("Khoản thu ghi nhận trực tiếp vào học phí của học sinh \(studentName).")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.secondaryText)
                                        .padding(.vertical, 4)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(Array(allocations.enumerated()), id: \.element.id) { idx, alloc in
                                            HStack {
                                                Text("\(idx + 1).")
                                                    .font(AppTypography.caption1)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColors.secondaryText)
                                                    .frame(width: 22, alignment: .leading)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    let charge = viewModel.charge(for: alloc.chargeId)
                                                    let title = charge != nil ? viewModel.sessionTitle(for: charge!.sessionId) : "Buổi học"
                                                    let sessionDate = charge != nil ? viewModel.effectiveSessionDate(for: charge!) : alloc.allocatedAt
                                                    Text(title)
                                                        .font(AppTypography.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(AppColors.primaryText)
                                                    Text("Ngày học: \(sessionDate.formatted(date: .numeric, time: .omitted))")
                                                        .font(AppTypography.caption2)
                                                        .foregroundColor(AppColors.secondaryText)
                                                }

                                                Spacer()

                                                Text(alloc.allocatedAmount.formattedVND)
                                                    .font(AppTypography.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColors.primaryText)
                                            }
                                            .padding(.vertical, 4)

                                            if alloc.id != allocations.last?.id {
                                                Divider().background(AppColors.divider)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // MARK: - 4. Nút Xuất & Chia sẻ Hóa đơn (Sử dụng UIActivityViewController trực tiếp)
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                SecondaryButton("Sao chép", icon: "doc.on.doc") {
                                    copyReceiptToClipboard()
                                }

                                Button {
                                    shareInvoiceNow()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up.fill")
                                        Text("Xuất & Chia sẻ Hóa đơn")
                                    }
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(AppColors.primaryPink)
                                    .foregroundColor(.white)
                                    .cornerRadius(AppRadius.md)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }

                if showCopiedToast {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("Đã sao chép nội dung phiếu thu!")
                            .font(AppTypography.caption1)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(AppRadius.full)
                    .padding(.bottom, AppSpacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Phiếu thu học phí")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentRose)
                    .fontWeight(.semibold)
                }
            }
            .task {
                allocations = await viewModel.fetchAllocations(for: payment.id)
                isLoadingAllocations = false
                regeneratePDFIfNeeded()
            }
        }
    }

    private func invoiceRow(
        label: String,
        value: String,
        valueColor: Color = AppColors.primaryText,
        isBold: Bool = false
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.caption1)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(value)
                .font(AppTypography.subheadline)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func regeneratePDFIfNeeded() {
        if let pdfData = viewModel.generateReceiptPDF(payment: payment, allocations: allocations) {
            let tempDir = FileManager.default.temporaryDirectory
            let safeCode = receiptCode.replacingOccurrences(of: "#", with: "")
            let fileURL = tempDir.appendingPathComponent("Phieu_Thu_Hoc_Phi_\(safeCode).pdf")
            try? pdfData.write(to: fileURL, options: .atomic)
            self.receiptPDFURL = fileURL
        }
    }

    private func shareInvoiceNow() {
        if receiptPDFURL == nil {
            regeneratePDFIfNeeded()
        }
        #if canImport(UIKit)
        if let url = receiptPDFURL {
            ShareSheetPresenter.present(items: [url, receiptText])
        } else {
            ShareSheetPresenter.present(items: [receiptText])
        }
        #endif
    }

    private func copyReceiptToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = receiptText
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        withAnimation {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}
