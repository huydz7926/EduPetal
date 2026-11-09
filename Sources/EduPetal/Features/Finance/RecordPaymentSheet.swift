import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Sheet ghi nhận thu học phí & đối soát công nợ 7 bước (Presentation Layer — Mục 5 /duan):
/// 1. Chọn học sinh
/// 2. Hiển thị các khoản còn nợ
/// 3. Chọn buổi cần thanh toán
/// 4. Hiện tổng tiền và phần còn lại
/// 5. Tạo yêu cầu thanh toán / QR / Bản kê PDF nháp (không tự coi là đã nhận tiền)
/// 6. Giáo viên xác nhận thực tế đã nhận tiền
/// 7. Lưu giao dịch và phân bổ đúng khoản nợ
public struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let students: [StudentEntity]
    public let preselectedStudentId: UUID?
    public let getOutstandingBalance: (UUID) -> Int64
    public let getUnpaidSessionItems: (UUID) -> [StudentChargeSessionDetailItem]
    public let onSave: (UUID, Int64, Date, String, String) async throws -> Void
    public let onSaveWithSelection: ((UUID, Int64, Date, String, String, Set<UUID>?) async throws -> Void)?

    @State private var selectedStudentId: UUID
    @State private var selectedChargeIds: Set<UUID> = []
    @State private var amount: Int64 = 0
    @State private var paidAt: Date = Date()
    @State private var paymentMethod: String = "Tiền mặt"
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var isShowingQRCodeSheet: Bool = false
    @State private var isShowingConfirmReceivedDialog: Bool = false
    @State private var errorMessage: String? = nil

    // Bản nháp Bản kê yêu cầu nộp học phí (chưa thu tiền, chỉ xóa bản nháp có xác nhận cuối)
    @State private var draftStatementCode: String? = nil
    @State private var draftStatementPDFURL: URL? = nil
    @State private var draftStatementCreatedAt: Date? = nil
    @State private var isShowingDeleteDraftDialog: Bool = false

    private let paymentMethods = ["Tiền mặt", "Chuyển khoản", "Ví điện tử", "Khác"]

    public init(
        students: [StudentEntity],
        preselectedStudentId: UUID? = nil,
        getOutstandingBalance: @escaping (UUID) -> Int64,
        getUnpaidSessionItems: @escaping (UUID) -> [StudentChargeSessionDetailItem] = { _ in [] },
        onSave: @escaping (UUID, Int64, Date, String, String) async throws -> Void,
        onSaveWithSelection: ((UUID, Int64, Date, String, String, Set<UUID>?) async throws -> Void)? = nil
    ) {
        self.students = students
        self.preselectedStudentId = preselectedStudentId
        self.getOutstandingBalance = getOutstandingBalance
        self.getUnpaidSessionItems = getUnpaidSessionItems
        self.onSave = onSave
        self.onSaveWithSelection = onSaveWithSelection

        let defaultId = preselectedStudentId
            ?? students.first(where: { getOutstandingBalance($0.id) > 0 })?.id
            ?? students.first?.id
            ?? UUID()
        self._selectedStudentId = State(initialValue: defaultId)

        let initialItems = getUnpaidSessionItems(defaultId)
        let initialIds = Set(initialItems.map { $0.charge.id })
        self._selectedChargeIds = State(initialValue: initialIds)
        let initialTargetAmount = initialItems.isEmpty
            ? getOutstandingBalance(defaultId)
            : initialItems.reduce(0 as Int64) { $0 + $1.remainingAmount }
        self._amount = State(initialValue: initialTargetAmount)
    }

    private var sortedStudents: [StudentEntity] {
        students.sorted { s1, s2 in
            let bal1 = getOutstandingBalance(s1.id)
            let bal2 = getOutstandingBalance(s2.id)
            if bal1 != bal2 {
                return bal1 > bal2
            }
            return s1.fullName < s2.fullName
        }
    }

    private var currentStudentName: String {
        students.first(where: { $0.id == selectedStudentId })?.fullName ?? "Học sinh"
    }

    /// Tổng dư nợ toàn bộ của học sinh
    private var currentOutstanding: Int64 {
        getOutstandingBalance(selectedStudentId)
    }

    /// Danh sách các buổi còn nợ của học sinh đang chọn
    private var unpaidItems: [StudentChargeSessionDetailItem] {
        getUnpaidSessionItems(selectedStudentId)
    }

    /// Các buổi còn nợ được giáo viên tích chọn để thanh toán
    private var selectedUnpaidItems: [StudentChargeSessionDetailItem] {
        unpaidItems.filter { selectedChargeIds.contains($0.charge.id) }
    }

    /// Tổng tiền còn nợ của các buổi đã chọn (nếu không có chi tiết buổi thì dùng `currentOutstanding`)
    private var selectedOutstanding: Int64 {
        if unpaidItems.isEmpty {
            return currentOutstanding
        }
        return selectedUnpaidItems.reduce(0 as Int64) { $0 + $1.remainingAmount }
    }

    /// Phần còn lại chưa trả của riêng các buổi đã chọn sau khi thu `amount`
    private var remainingForSelectedCharges: Int64 {
        max(0, selectedOutstanding - amount)
    }

    /// Tổng dư nợ còn lại của học sinh sau khi thu `amount`
    private var remainingAfterPayment: Int64 {
        max(0, currentOutstanding - amount)
    }

    private var isValid: Bool {
        if !unpaidItems.isEmpty && selectedChargeIds.isEmpty {
            return false
        }
        return amount > 0 && amount <= selectedOutstanding && selectedOutstanding > 0
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // MARK: - Bước 1: Chọn học sinh
                    studentSelectorSection

                    // MARK: - Bước 2 & 3: Hiển thị các khoản còn nợ & Chọn buổi cần thanh toán
                    if !unpaidItems.isEmpty {
                        unpaidSessionsSelectionSection
                    }

                    // MARK: - Bước 4: Hiện tổng tiền, số tiền thực thu và phần còn lại
                    paymentAmountAndReconciliationSection

                    // MARK: - Bước 5: Tạo yêu cầu thanh toán / QR / Bản kê PDF nháp (Chưa coi là đã nhận tiền)
                    paymentRequestAndDraftStatementSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.md)
                    }

                    // MARK: - Bước 6 & 7: Giáo viên xác nhận thực tế đã nhận tiền -> Lưu & Phân bổ
                    PrimaryButton(
                        "Xác nhận thực tế đã nhận tiền",
                        icon: "checkmark.seal.fill",
                        isLoading: isSubmitting,
                        isEnabled: isValid && !isSubmitting,
                        action: {
                            isShowingConfirmReceivedDialog = true
                        }
                    )
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Ghi nhận thu tiền")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            .onChange(of: selectedStudentId) { _, newId in
                let items = getUnpaidSessionItems(newId)
                selectedChargeIds = Set(items.map { $0.charge.id })
                amount = items.isEmpty
                    ? getOutstandingBalance(newId)
                    : items.reduce(0 as Int64) { $0 + $1.remainingAmount }
                clearDraftStatement()
            }
            .onChange(of: selectedChargeIds) { _, _ in
                if draftStatementPDFURL != nil {
                    clearDraftStatement()
                }
            }
            .onChange(of: amount) { _, _ in
                if draftStatementPDFURL != nil {
                    clearDraftStatement()
                }
            }
            .sheet(isPresented: $isShowingQRCodeSheet) {
                let targetAmount = amount > 0 ? amount : selectedOutstanding
                PaymentQRCodeSheet(
                    studentName: currentStudentName,
                    amount: targetAmount,
                    note: note.isEmpty ? "Hoc phi \(currentStudentName)" : note
                )
            }
            // Hộp thoại Bước 6: Giáo viên xác nhận thực tế đã nhận tiền
            .alert(
                "Xác nhận thực tế đã nhận tiền",
                isPresented: $isShowingConfirmReceivedDialog
            ) {
                Button("Kiểm tra lại", role: .cancel) {}
                Button("Đã nhận tiền & Lưu giao dịch") {
                    submitPayment()
                }
            } message: {
                let sessionCountText = unpaidItems.isEmpty ? "" : " cho \(selectedChargeIds.count) buổi đã chọn"
                Text("Xác nhận đã nhận \(amount.formattedVND) (\(paymentMethod)) từ \(currentStudentName)\(sessionCountText)?\n\n• Phần còn lại của các buổi đã chọn: \(remainingForSelectedCharges.formattedVND)\n• Tổng dư nợ còn lại của học sinh: \(remainingAfterPayment.formattedVND)")
            }
            // Hộp thoại xác nhận cuối khi xóa bản nháp Bản kê học phí
            .alert(
                "Xóa bản nháp bản kê học phí?",
                isPresented: $isShowingDeleteDraftDialog
            ) {
                Button("Hủy", role: .cancel) {}
                Button("Xóa bản nháp", role: .destructive) {
                    clearDraftStatement()
                }
            } message: {
                Text("Bạn có chắc chắn muốn xóa bản nháp bản kê \(draftStatementCode ?? "") không? Thao tác này chỉ xóa bản nháp tạm tính và không làm thay đổi công nợ hay giao dịch.")
            }
        }
    }

    // MARK: - Bước 1: Student Selector Section

    private var studentSelectorSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(L("Học sinh", "Student"))
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    StatusBadge(
                        title: currentOutstanding > 0 ? "Còn nợ" : "Đã hoàn tất",
                        icon: currentOutstanding > 0 ? "clock.fill" : "checkmark.circle.fill",
                        textColor: currentOutstanding > 0 ? AppColors.warning : AppColors.success,
                        backgroundColor: (currentOutstanding > 0 ? AppColors.warning : AppColors.success).opacity(0.12)
                    )
                }

                if preselectedStudentId != nil, let student = students.first(where: { $0.id == selectedStudentId }) {
                    HStack {
                        Text(student.fullName)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Text("Tổng nợ: \(currentOutstanding.formattedVND)")
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(currentOutstanding > 0 ? AppColors.warning : AppColors.success)
                    }
                } else {
                    Picker("Học sinh", selection: $selectedStudentId) {
                        ForEach(sortedStudents) { student in
                            let bal = getOutstandingBalance(student.id)
                            Text("\(student.fullName) (Nợ: \(bal.formattedVND))")
                                .tag(student.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - Bước 2 & 3: Unpaid Sessions Selection Section

    private var unpaidSessionsSelectionSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Các buổi còn nợ", "Unpaid Sessions"))
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text("Đã chọn \(selectedChargeIds.count)/\(unpaidItems.count) buổi • Tổng: \(selectedOutstanding.formattedVND)")
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                    }

                    Spacer()

                    Button {
                        if selectedChargeIds.count == unpaidItems.count {
                            selectedChargeIds.removeAll()
                            amount = 0
                        } else {
                            selectedChargeIds = Set(unpaidItems.map { $0.charge.id })
                            amount = selectedOutstanding
                        }
                    } label: {
                        Text(selectedChargeIds.count == unpaidItems.count ? "Bỏ chọn" : "Chọn tất cả")
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.accentRose)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppColors.secondaryPink))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ForEach(unpaidItems) { item in
                        let isSelected = selectedChargeIds.contains(item.charge.id)
                        Button {
                            toggleSessionSelection(item: item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? AppColors.primaryPink : AppColors.tertiaryText)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.sessionTitle)
                                            .font(AppTypography.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(1)

                                        Text("• \(item.className)")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.accentRose)
                                            .lineLimit(1)
                                    }

                                    HStack(spacing: 6) {
                                        Text(item.sessionDate.formatted(date: .numeric, time: .shortened))
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)

                                        if item.allocatedPaidAmount > 0 {
                                            Text("• Đã trả \(item.allocatedPaidAmount.formattedVND)/\(item.charge.amount.formattedVND)")
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.success)
                                        }
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.remainingAmount.formattedVND)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)

                                    Text(item.allocatedPaidAmount > 0 ? "Còn thiếu" : "Chưa thu")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(item.allocatedPaidAmount > 0 ? AppColors.warning : AppColors.error)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .fill(isSelected ? AppColors.secondaryPink.opacity(0.35) : AppColors.surfaceSubtle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .stroke(isSelected ? AppColors.primaryPink : AppColors.divider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Bước 4: Payment Amount & Reconciliation Section

    private var paymentAmountAndReconciliationSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(L("Số tiền thu & Đối soát", "Payment Amount & Summary"))
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)

                CurrencyTextField("Số tiền thu thực tế", value: $amount)

                // Phím tắt chọn số tiền nhanh (Hỗ trợ cả thu đủ và thu một phần)
                if selectedOutstanding > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            quickAmountChip(title: "Thu đủ đã chọn (\(selectedOutstanding.formattedVND))", targetAmount: selectedOutstanding)

                            if selectedOutstanding > 200_000 {
                                quickAmountChip(title: "200.000 ₫", targetAmount: 200_000)
                            }

                            if selectedOutstanding > 500_000 {
                                quickAmountChip(title: "500.000 ₫", targetAmount: 500_000)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !unpaidItems.isEmpty && selectedChargeIds.isEmpty {
                    Text("Vui lòng chọn ít nhất 1 buổi học còn nợ để ghi nhận thanh toán.")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.error)
                } else if amount > selectedOutstanding && selectedOutstanding > 0 {
                    Text("Tối đa \(selectedOutstanding.formattedVND).")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.error)
                }

                // Bảng đối soát Tổng tiền đã chọn - Thực thu - Phần còn lại
                VStack(spacing: 6) {
                    HStack {
                        Text("Tổng nợ các buổi đã chọn:")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(selectedOutstanding.formattedVND)
                            .font(AppTypography.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)
                    }

                    HStack {
                        Text("Số tiền thực thu lần này:")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(amount.formattedVND)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.success)
                    }

                    HStack {
                        Text("Còn lại của các buổi đã chọn:")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(remainingForSelectedCharges.formattedVND)
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(remainingForSelectedCharges == 0 ? AppColors.success : AppColors.warning)
                    }

                    Divider().background(AppColors.divider)

                    HStack {
                        Text("Tổng dư nợ học sinh sau thu:")
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Text(remainingAfterPayment.formattedVND)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(remainingAfterPayment == 0 ? AppColors.success : AppColors.warning)
                    }
                }
                .padding(AppSpacing.xs)
                .background(AppColors.surfaceSubtle)
                .cornerRadius(AppRadius.sm)

                Divider()
                    .background(AppColors.divider)

                DatePicker("Ngày thu tiền", selection: $paidAt, displayedComponents: [.date])
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)

                Divider()
                    .background(AppColors.divider)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Hình thức thanh toán")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)

                    Picker("Hình thức", selection: $paymentMethod) {
                        ForEach(paymentMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()
                    .background(AppColors.divider)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Ghi chú")
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.secondaryText)

                    TextField("Ví dụ: Phụ huynh chuyển khoản...", text: $note)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.surfaceSubtle)
                        .cornerRadius(AppRadius.sm)
                }
            }
        }
    }

    // MARK: - Bước 5: Payment Request / QR / Draft PDF Section

    private var paymentRequestAndDraftStatementSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundColor(AppColors.accentRose)
                    Text(L("Mã QR & Bản kê PDF", "QR Code & Draft Statement"))
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }

                HStack(spacing: AppSpacing.sm) {
                    Button {
                        isShowingQRCodeSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                            Text("Mã QR chuyển khoản")
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.sm).fill(AppColors.secondaryPink))
                        .foregroundColor(AppColors.accentRose)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedOutstanding <= 0)

                    Button {
                        createDraftStatementPDF()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus")
                            Text("Tạo Bản kê nháp PDF")
                        }
                        .font(AppTypography.caption1)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: AppRadius.sm).fill(AppColors.surfaceSubtle))
                        .foregroundColor(AppColors.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .stroke(AppColors.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }

                // Hiển thị thẻ Bản nháp Bản kê học phí nếu đã tạo
                if let draftCode = draftStatementCode, let pdfURL = draftStatementPDFURL {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusBadge(
                                title: "Bản nháp • Chưa thu tiền",
                                icon: "doc.text",
                                textColor: AppColors.warning,
                                backgroundColor: AppColors.warning.opacity(0.14)
                            )
                            Spacer()
                            Text(draftCode)
                                .font(AppTypography.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.secondaryText)
                        }

                        Text("Bản kê học phí tạm tính cho \(currentStudentName) • Số tiền yêu cầu: \(amount.formattedVND)")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.primaryText)

                        HStack(spacing: AppSpacing.sm) {
                            Button {
                                #if canImport(UIKit)
                                ShareSheetPresenter.present(items: [pdfURL])
                                #endif
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Chia sẻ PDF nháp")
                                }
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(AppColors.secondaryPink))
                                .foregroundColor(AppColors.accentRose)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(role: .destructive) {
                                isShowingDeleteDraftDialog = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Xóa bản nháp")
                                }
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.error)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.surfaceSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(AppColors.warning.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Helpers & Actions

    private func toggleSessionSelection(item: StudentChargeSessionDetailItem) {
        if selectedChargeIds.contains(item.charge.id) {
            selectedChargeIds.remove(item.charge.id)
        } else {
            selectedChargeIds.insert(item.charge.id)
        }
        amount = selectedUnpaidItems.reduce(0 as Int64) { $0 + $1.remainingAmount }
    }

    private func createDraftStatementPDF() {
        let code = "#DRAFT-\(UUID().uuidString.prefix(6).uppercased())"
        var remainingToSimulate = amount
        let simulatedItems: [(title: String, date: Date, amount: Int64)] = selectedUnpaidItems.compactMap { sItem in
            guard remainingToSimulate > 0 else { return nil }
            let allocAmount = min(remainingToSimulate, sItem.remainingAmount)
            remainingToSimulate -= allocAmount
            return (title: "\(sItem.sessionTitle) (\(sItem.className))", date: sItem.sessionDate, amount: allocAmount)
        }

        let pdfData = ReceiptPDFData(
            receiptCode: code,
            studentName: currentStudentName,
            amount: amount,
            paidAt: Date(),
            paymentMethod: "\(paymentMethod) (BẢN NHÁP - YÊU CẦU NỘP HỌC PHÍ)",
            note: note.isEmpty ? "Bản kê học phí tạm tính gửi phụ huynh đối chiếu (Chưa thu tiền)" : note,
            remainingBalance: remainingAfterPayment,
            items: simulatedItems
        )

        if let data = try? ReceiptPDFRenderer().renderReceiptPDF(data: pdfData) {
            let tempDir = FileManager.default.temporaryDirectory
            let safeCode = code.replacingOccurrences(of: "#", with: "")
            let url = tempDir.appendingPathComponent("Ban_ke_nhap_\(safeCode).pdf")
            try? data.write(to: url)
            draftStatementCode = code
            draftStatementPDFURL = url
            draftStatementCreatedAt = Date()
        }
    }

    private func clearDraftStatement() {
        if let url = draftStatementPDFURL {
            try? FileManager.default.removeItem(at: url)
        }
        draftStatementCode = nil
        draftStatementPDFURL = nil
        draftStatementCreatedAt = nil
    }

    private func quickAmountChip(title: String, targetAmount: Int64) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            amount = targetAmount
        } label: {
            Text(title)
                .font(AppTypography.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 4)
                .background(amount == targetAmount ? AppColors.accentRose : AppColors.secondaryPink.opacity(0.8))
                .foregroundColor(amount == targetAmount ? .white : AppColors.accentRose)
                .cornerRadius(AppRadius.sm)
        }
    }

    private func submitPayment() {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        let chosenIds: Set<UUID>? = unpaidItems.isEmpty ? nil : selectedChargeIds

        Task {
            do {
                if let onSaveWithSelection {
                    try await onSaveWithSelection(selectedStudentId, amount, paidAt, paymentMethod, note, chosenIds)
                } else {
                    try await onSave(selectedStudentId, amount, paidAt, paymentMethod, note)
                }
                clearDraftStatement()
                isSubmitting = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
