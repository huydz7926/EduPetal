import SwiftUI

/// Màn hình hiển thị mã QR thanh toán học phí (VietQR & On-Device QR Generator)
public struct PaymentQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let studentName: String
    public let amount: Int64
    public let note: String

    @State private var bankConfig: BankAccountConfig = BankAccountConfig()
    @State private var isShowingBankSetupSheet: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var copiedMessage: String = ""

    private let bankConfigService = BankConfigService.shared
    private let qrGeneratorService = QRCodeGeneratorService.shared

    public init(
        studentName: String,
        amount: Int64,
        note: String = ""
    ) {
        self.studentName = studentName
        self.amount = amount
        self.note = note.isEmpty ? "Hoc phi \(studentName)" : note
    }

    private var vietQRURL: URL? {
        bankConfigService.generateVietQRURL(config: bankConfig, amount: amount, note: note)
    }

    private var fullTransferMessage: String {
        bankConfigService.generateTransferMessage(config: bankConfig, amount: amount, studentName: studentName, note: note)
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        if !bankConfig.isConfigured {
                            // MARK: - Unconfigured Bank State
                            AppCard {
                                VStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 48))
                                        .foregroundColor(AppColors.accentRose)
                                        .padding(.top, AppSpacing.sm)

                                    Text("Chưa cài đặt tài khoản ngân hàng")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)

                                    Text("Cài đặt ngân hàng để tạo mã VietQR.")
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.secondaryText)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, AppSpacing.sm)

                                    PrimaryButton("Cài đặt tài khoản ngân hàng", icon: "gearshape.fill") {
                                        isShowingBankSetupSheet = true
                                    }
                                    .padding(.top, AppSpacing.xs)
                                }
                                .padding(.vertical, AppSpacing.md)
                            }
                        } else {
                            // MARK: - VietQR Display Card
                            AppCard {
                                VStack(spacing: AppSpacing.sm) {
                                    // Header: Logo VietQR & Ngân hàng
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bankConfig.bankName)
                                                .font(AppTypography.headline)
                                                .foregroundColor(AppColors.primaryText)
                                            Text(bankConfig.accountHolderName)
                                                .font(AppTypography.caption1)
                                                .foregroundColor(AppColors.secondaryText)
                                                .textCase(.uppercase)
                                        }

                                        Spacer()

                                        Button {
                                            isShowingBankSetupSheet = true
                                        } label: {
                                            Image(systemName: "pencil.circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(AppColors.accentRose)
                                        }
                                    }

                                    Divider().background(AppColors.divider)

                                    // QR Code Image
                                    ZStack {
                                        Color.white
                                            .cornerRadius(AppRadius.md)
                                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)

                                        if let url = vietQRURL {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .empty:
                                                    ProgressView()
                                                        .frame(width: 220, height: 220)
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 230, height: 230)
                                                        .padding(8)
                                                case .failure:
                                                    // Fallback to on-device QR generator
                                                    offlineQRFallback
                                                @unknown default:
                                                    offlineQRFallback
                                                }
                                            }
                                        } else {
                                            offlineQRFallback
                                        }
                                    }
                                    .frame(width: 246, height: 246)
                                    .padding(.vertical, AppSpacing.xs)

                                    // Amount display
                                    VStack(spacing: 2) {
                                        Text("Số tiền thanh toán")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(amount.formattedVND)
                                            .font(AppTypography.font(size: 26))
                                            .foregroundColor(AppColors.accentRose)
                                    }
                                }
                                .padding(.vertical, AppSpacing.xs)
                            }

                            // MARK: - Bank Details Details Card (Copyable)
                            AppCard {
                                VStack(spacing: AppSpacing.sm) {
                                    detailRowWithCopy(
                                        title: "Số tài khoản",
                                        value: bankConfig.accountNumber,
                                        copyValue: bankConfig.accountNumber,
                                        toastText: "Đã sao chép số tài khoản"
                                    )

                                    Divider().background(AppColors.divider)

                                    detailRowWithCopy(
                                        title: "Chủ tài khoản",
                                        value: bankConfig.accountHolderName,
                                        copyValue: bankConfig.accountHolderName,
                                        toastText: "Đã sao chép tên chủ tài khoản"
                                    )

                                    Divider().background(AppColors.divider)

                                    detailRowWithCopy(
                                        title: "Nội dung chuyển khoản",
                                        value: note,
                                        copyValue: note,
                                        toastText: "Đã sao chép nội dung chuyển khoản"
                                    )
                                }
                            }

                            // MARK: - Notice Banner
                            HStack(alignment: .top, spacing: AppSpacing.xs) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(AppColors.warning)
                                    .font(AppTypography.font(size: 14))

                                Text("Sau khi phụ huynh chuyển tiền, hãy bấm xác nhận thu.")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineSpacing(2)
                            }
                            .padding(.horizontal, AppSpacing.xs)

                            // MARK: - Action Buttons
                            HStack(spacing: AppSpacing.md) {
                                SecondaryButton("Sao chép thông tin", icon: "doc.on.doc") {
                                    copyToClipboard(fullTransferMessage, toast: "Đã sao chép toàn bộ thông tin chuyển khoản")
                                }

                                Button {
                                    #if canImport(UIKit)
                                    if let qrImg = qrGeneratorService.generateQRCode(from: fullTransferMessage) {
                                        ShareSheetPresenter.present(items: [qrImg, fullTransferMessage])
                                    } else {
                                        ShareSheetPresenter.present(items: [fullTransferMessage])
                                    }
                                    #endif
                                } label: {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Chia sẻ")
                                    }
                                    .font(AppTypography.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(AppColors.accentRose)
                                    .foregroundColor(AppColors.onPrimary)
                                    .cornerRadius(AppRadius.md)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, AppSpacing.xs)
                        }
                    }
                    .padding(AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }

                // MARK: - Toast Banner
                if showCopiedToast {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.onPrimary)
                        Text(copiedMessage)
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.onPrimary)
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
            .navigationTitle("Mã QR chuyển khoản")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentRose)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                self.bankConfig = bankConfigService.loadConfig()
            }
            .sheet(isPresented: $isShowingBankSetupSheet) {
                BankSetupSheet(config: $bankConfig) {
                    self.bankConfig = bankConfigService.loadConfig()
                }
            }
        }
    }

    @ViewBuilder
    private var offlineQRFallback: some View {
        #if canImport(UIKit)
        if let offlineImg = qrGeneratorService.generateQRCode(from: fullTransferMessage) {
            Image(uiImage: offlineImg)
                .resizable()
                .scaledToFit()
                .frame(width: 230, height: 230)
                .padding(8)
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundColor(AppColors.secondaryText)
        }
        #else
        Image(systemName: "qrcode")
            .font(.system(size: 80))
            .foregroundColor(AppColors.secondaryText)
        #endif
    }

    private func detailRowWithCopy(title: String, value: String, copyValue: String, toastText: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.secondaryText)
                Text(value)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.primaryText)
            }

            Spacer()

            Button {
                copyToClipboard(copyValue, toast: toastText)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Chép")
                }
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.accentRose)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 4)
                .background(AppColors.secondaryPink.opacity(0.8))
                .cornerRadius(AppRadius.sm)
            }
        }
    }

    private func copyToClipboard(_ text: String, toast: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        copiedMessage = toast
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

/// Sheet cài đặt tài khoản ngân hàng của giáo viên
public struct BankSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var config: BankAccountConfig
    public let onSave: () -> Void

    @State private var selectedBankCode: String = "VCB"
    @State private var accountNumber: String = ""
    @State private var accountHolderName: String = ""

    private let bankService = BankConfigService.shared

    public init(config: Binding<BankAccountConfig>, onSave: @escaping () -> Void) {
        self._config = config
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Thông tin tài khoản nhận học phí")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)

                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text("Ngân hàng")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)

                                Picker("Ngân hàng", selection: $selectedBankCode) {
                                    ForEach(BankConfigService.supportedBanks) { bank in
                                        Text(bank.name).tag(bank.code)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs)
                                .background(AppColors.surfaceSubtle)
                                .cornerRadius(AppRadius.sm)
                            }

                            Divider().background(AppColors.divider)

                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text("Số tài khoản ngân hàng")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)

                                TextField("Ví dụ: 0123456789...", text: $accountNumber)
                                    .font(AppTypography.body)
                                    #if canImport(UIKit)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(AppColors.surfaceSubtle)
                                    .cornerRadius(AppRadius.sm)
                            }

                            Divider().background(AppColors.divider)

                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text("Tên chủ tài khoản (in hoa không dấu)")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)

                                TextField("Ví dụ: NGUYEN VAN A", text: $accountHolderName)
                                    .font(AppTypography.body)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(AppColors.surfaceSubtle)
                                    .cornerRadius(AppRadius.sm)
                            }
                        }
                    }

                    PrimaryButton("Lưu tài khoản", icon: "checkmark.circle.fill", isEnabled: !accountNumber.isEmpty && !accountHolderName.isEmpty) {
                        save()
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Cài đặt tài khoản ngân hàng")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            .onAppear {
                self.selectedBankCode = config.bankCode
                self.accountNumber = config.accountNumber
                self.accountHolderName = config.accountHolderName
            }
        }
    }

    private func save() {
        let bankName = BankConfigService.supportedBanks.first(where: { $0.code == selectedBankCode })?.name ?? selectedBankCode
        let newConfig = BankAccountConfig(
            bankCode: selectedBankCode,
            bankName: bankName,
            accountNumber: accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            accountHolderName: accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
        bankService.saveConfig(newConfig)
        config = newConfig
        onSave()
        dismiss()
    }
}
