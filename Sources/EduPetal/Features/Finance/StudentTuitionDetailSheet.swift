import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Chi tiết Học phí, Số buổi dạy, Ảnh minh chứng & Lịch sử thu tiền của Học sinh (Mục 5 /duan)
public struct StudentTuitionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let studentId: UUID
    public let viewModel: FinanceViewModel
    public let onTapRecordPayment: (StudentEntity) -> Void
    public let onTapPaymentReceipt: (PaymentEntity) -> Void

    @State private var showOnlySelectedPeriodSessions: Bool = false
    @State private var selectedProofPreview: ProofPreviewContext? = nil
    @State private var selectedSessionForDetail: TeachingSessionEntity? = nil

    public struct ProofPreviewContext: Identifiable {
        public let id = UUID()
        public let attachment: SessionAttachmentEntity
        public let sessionTitle: String
        public let sessionDate: Date
        public let className: String
    }

    public init(
        studentId: UUID,
        viewModel: FinanceViewModel,
        onTapRecordPayment: @escaping (StudentEntity) -> Void,
        onTapPaymentReceipt: @escaping (PaymentEntity) -> Void
    ) {
        self.studentId = studentId
        self.viewModel = viewModel
        self.onTapRecordPayment = onTapRecordPayment
        self.onTapPaymentReceipt = onTapPaymentReceipt
    }

    private var studentItem: StudentFinanceItem? {
        viewModel.studentFinanceItem(for: studentId) ?? fallbackStudentFinanceItem
    }

    private var fallbackStudentFinanceItem: StudentFinanceItem? {
        guard let student = viewModel.student(for: studentId) else { return nil }
        let studentCharges = viewModel.charges.filter { $0.studentId == studentId }
        let studentPayments = viewModel.payments.filter { $0.studentId == studentId }
        let accrued = studentCharges.reduce(0 as Int64) { $0 + $1.amount }
        let collected = studentPayments.reduce(0 as Int64) { $0 + $1.amount }
        let outstanding = max(0, accrued - collected)
        return StudentFinanceItem(
            student: student,
            accrued: accrued,
            collected: collected,
            outstanding: outstanding,
            completedSessionsInPeriodCount: studentCharges.filter { viewModel.isDateInSelectedPeriod(viewModel.effectiveSessionDate(for: $0)) }.count,
            totalCompletedSessionsCount: studentCharges.count
        )
    }

    private var sessionItems: [StudentChargeSessionDetailItem] {
        viewModel.chargeSessionDetails(for: studentId, onlySelectedPeriod: showOnlySelectedPeriodSessions)
    }

    private var studentPayments: [PaymentEntity] {
        viewModel.paymentsForStudent(studentId)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if let item = studentItem {
                    VStack(spacing: AppSpacing.md) {
                        // 1. Thẻ Hồ sơ & Tổng quan đối soát Học phí
                        studentSummaryHeaderCard(item: item)

                        // 2. Danh sách từng buổi học phát sinh học phí & Ảnh minh chứng
                        sessionsAndProofsSection(item: item)

                        // 3. Lịch sử thu tiền & Bản kê học phí
                        paymentHistorySection(item: item)
                    }
                    .padding(AppSpacing.md)
                } else {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "Không tìm thấy học sinh",
                        message: "Thông tin học sinh không còn tồn tại."
                    )
                    .padding(.top, AppSpacing.xl)
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Chi tiết học phí học sinh")
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
            .sheet(item: $selectedProofPreview) { context in
                FinanceProofFullscreenViewer(context: context)
            }
            .sheet(item: $selectedSessionForDetail) { session in
                if let schRepo = viewModel.scheduleRepository,
                   let clsRepo = viewModel.classRepository {
                    NavigationStack {
                        SessionDetailView(
                            viewModel: SessionDetailViewModel(
                                session: session,
                                scheduleRepository: schRepo,
                                classRepository: clsRepo,
                                studentRepository: viewModel.studentRepository,
                                financeRepository: viewModel.financeRepository
                            ),
                            scheduleRepository: schRepo,
                            classRepository: clsRepo,
                            studentRepository: viewModel.studentRepository,
                            financeRepository: viewModel.financeRepository
                        )
                    }
                }
            }
        }
    }

    // MARK: - 1. Student Summary Card

    private func studentSummaryHeaderCard(item: StudentFinanceItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    studentAvatarView(student: item.student, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.student.fullName)
                            .font(AppTypography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)

                        if !item.enrolledClassNames.isEmpty {
                            Text("Lớp: \(item.enrolledClassNames.joined(separator: ", "))")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    paymentStatusBadge(status: item.paymentStatus)
                }

                Divider()
                    .background(AppColors.divider)

                // Khối 1: Số liệu Đã thu & Còn nợ gọn gàng (Đã bỏ tiền phát sinh)
                HStack(spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.selectedTimeFilter == .allTime ? "Đã thu" : "Đã thu (\(viewModel.periodDisplayLabel))")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(item.collectedInPeriod.formattedVND)
                            .font(AppTypography.headline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.success)
                        Text("\(item.completedSessionsInPeriodCount) buổi hoàn thành")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.surfaceSubtle)
                    )

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Tổng còn nợ hiện tại")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(item.outstanding.formattedVND)
                            .font(AppTypography.headline)
                            .fontWeight(.bold)
                            .foregroundColor(item.outstanding > 0 ? AppColors.warning : AppColors.success)
                        Text("Tổng đã thu: \(item.collected.formattedVND)")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(AppColors.surfaceSubtle)
                    )
                }

                if item.outstanding > 0 {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onTapRecordPayment(item.student)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "banknote.fill")
                            Text("Ghi nhận thu học phí (\(item.outstanding.formattedVND))")
                        }
                        .font(AppTypography.subheadline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: AppRadius.md).fill(AppColors.primaryPink))
                        .foregroundColor(AppColors.onPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 2. Sessions & Proof Attachments Section

    private func sessionsAndProofsSection(item: StudentFinanceItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chi tiết buổi học & Ảnh minh chứng")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text("Chạm vào ảnh để phóng to minh chứng điểm danh")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                if viewModel.selectedTimeFilter != .allTime {
                    Picker("Phạm vi buổi", selection: $showOnlySelectedPeriodSessions) {
                        Text("Tất cả (\(item.totalCompletedSessionsCount))").tag(false)
                        Text("Trong kỳ (\(item.completedSessionsInPeriodCount))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }

            if sessionItems.isEmpty {
                AppCard {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: "Chưa có buổi học phát sinh học phí",
                        message: "Các buổi học sau khi hoàn thành và học sinh có mặt sẽ hiển thị kèm đơn giá và ảnh minh chứng tại đây."
                    )
                }
            } else {
                LazyVStack(spacing: AppSpacing.xs) {
                    ForEach(sessionItems) { sItem in
                        sessionChargeCard(sItem: sItem)
                    }
                }
            }
        }
    }

    private func sessionChargeCard(sItem: StudentChargeSessionDetailItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: sItem.classColorHex))
                                .frame(width: 9, height: 9)
                            Text(sItem.className)
                                .font(AppTypography.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.accentRose)

                            if !sItem.isInSelectedPeriod && viewModel.selectedTimeFilter != .allTime {
                                Text("• Kỳ trước")
                                    .font(AppTypography.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.warning)
                            }
                        }

                        Text(sItem.sessionTitle)
                            .font(AppTypography.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)

                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                            if let session = sItem.session {
                                Text("\(session.startTime.formatted(date: .numeric, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)
                            } else {
                                Text(sItem.sessionDate.formatted(date: .numeric, time: .shortened))
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(sItem.charge.amount.formattedVND)
                            .font(AppTypography.headline)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.primaryText)

                        StatusBadge(
                            title: sItem.charge.status.displayName,
                            icon: sItem.charge.status == .paid ? "checkmark.circle.fill" : (sItem.charge.status == .partiallyPaid ? "circle.dotted" : "clock"),
                            textColor: sItem.charge.status == .paid ? AppColors.success : (sItem.charge.status == .partiallyPaid ? AppColors.warning : AppColors.error),
                            backgroundColor: (sItem.charge.status == .paid ? AppColors.success : (sItem.charge.status == .partiallyPaid ? AppColors.warning : AppColors.error)).opacity(0.12)
                        )
                    }
                }

                // Dòng đối soát Đơn giá chốt - Đã thu - Còn nợ của buổi học
                HStack {
                    Text("Đơn giá chốt: \(sItem.unitPriceSnapshot.formattedVND)")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.secondaryText)

                    Spacer()

                    if sItem.allocatedPaidAmount > 0 {
                        Text("Đã thu: \(sItem.allocatedPaidAmount.formattedVND)")
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.success)
                    }

                    if sItem.remainingAmount > 0 {
                        Text("• Còn nợ: \(sItem.remainingAmount.formattedVND)")
                            .font(AppTypography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.warning)
                    }
                }
                .padding(.top, 2)

                Divider()
                    .background(AppColors.divider)

                // Khung Ảnh minh chứng của buổi học
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: sItem.attachments.isEmpty ? "photo.badge.exclamationmark" : "camera.Macro.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(sItem.attachments.isEmpty ? AppColors.secondaryText : AppColors.accentRose)
                        Text(sItem.attachments.isEmpty ? "Không có ảnh minh chứng" : "Ảnh minh chứng (\(sItem.attachments.count))")
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(sItem.attachments.isEmpty ? AppColors.secondaryText : AppColors.primaryText)
                    }

                    Spacer()

                    if let session = sItem.session, viewModel.scheduleRepository != nil, viewModel.classRepository != nil {
                        Button {
                            selectedSessionForDetail = session
                        } label: {
                            HStack(spacing: 3) {
                                Text("Mở buổi học")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(AppTypography.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.accentRose)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !sItem.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(sItem.attachments) { attachment in
                                Button {
                                    selectedProofPreview = ProofPreviewContext(
                                        attachment: attachment,
                                        sessionTitle: sItem.sessionTitle,
                                        sessionDate: sItem.sessionDate,
                                        className: sItem.className
                                    )
                                } label: {
                                    proofThumbnailCard(attachment: attachment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func proofThumbnailCard(attachment: SessionAttachmentEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                #if canImport(UIKit)
                if let uiImg = PhotoStorageService.shared.loadImage(named: attachment.filePath) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                } else {
                    placeholderProofBox
                }
                #else
                placeholderProofBox
                #endif

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.onPrimary)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .padding(4)
            }

            if !attachment.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(attachment.caption)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .leading)
            }
        }
    }

    private var placeholderProofBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColors.secondaryPink.opacity(0.4))
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accentRose)
                Text("Minh chứng")
                    .font(AppTypography.font(size: 10))
                    .foregroundColor(AppColors.accentRose)
            }
        }
    }

    // MARK: - 3. Payment History Section

    private func paymentHistorySection(item: StudentFinanceItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Lịch sử thu tiền & Bản kê (\(studentPayments.count))")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
            }

            if studentPayments.isEmpty {
                AppCard {
                    Text("Chưa có phiếu thu học phí nào cho học sinh này.")
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVStack(spacing: AppSpacing.xs) {
                    ForEach(studentPayments) { payment in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onTapPaymentReceipt(payment)
                            }
                        } label: {
                            AppCard {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(AppColors.success)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("#REC-\(payment.id.uuidString.prefix(8).uppercased())")
                                                .font(AppTypography.caption1)
                                                .fontWeight(.bold)
                                                .foregroundColor(AppColors.primaryText)

                                            Text(payment.paymentMethod)
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.accentRose)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppColors.secondaryPink.opacity(0.6))
                                                .cornerRadius(4)
                                        }

                                        Text("Ngày thu: \(payment.paidAt.formatted(date: .numeric, time: .shortened))")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)

                                        if !payment.note.isEmpty {
                                            Text(payment.note)
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.tertiaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Text("+\(payment.amount.formattedVND)")
                                            .font(AppTypography.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(AppColors.success)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppColors.tertiaryText)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func studentAvatarView(student: StudentEntity, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(AppColors.secondaryPink)
                .frame(width: size, height: size)
            #if canImport(UIKit)
            if let path = student.avatarPath, !path.isEmpty,
               let uiImg = AvatarStorageService.shared.loadAvatar(named: path) ?? PhotoStorageService.shared.loadImage(named: path) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials(for: student.fullName))
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(AppColors.accentRose)
            }
            #else
            Text(initials(for: student.fullName))
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(AppColors.accentRose)
            #endif
        }
    }

    private func paymentStatusBadge(status: StudentTuitionPaymentStatus) -> some View {
        switch status {
        case .paid:
            StatusBadge(title: status.rawValue, icon: "checkmark.circle.fill", textColor: AppColors.success, backgroundColor: AppColors.success.opacity(0.12))
        case .partiallyPaid:
            StatusBadge(title: status.rawValue, icon: "circle.lefthalf.filled", textColor: AppColors.warning, backgroundColor: AppColors.warning.opacity(0.12))
        case .unpaid:
            StatusBadge(title: status.rawValue, icon: "exclamationmark.circle.fill", textColor: AppColors.error, backgroundColor: AppColors.error.opacity(0.12))
        case .noCharges:
            StatusBadge(title: status.rawValue, icon: "minus.circle", textColor: AppColors.secondaryText, backgroundColor: AppColors.surfaceSubtle)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let last = parts.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "S"
    }
}

/// Màn hình xem ảnh minh chứng điểm danh toàn màn hình từ mục Học phí
public struct FinanceProofFullscreenViewer: View {
    @Environment(\.dismiss) private var dismiss
    public let context: StudentTuitionDetailSheet.ProofPreviewContext
    @State private var zoomScale: CGFloat = 1.0

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: AppSpacing.md) {
                    Spacer()

                    #if canImport(UIKit)
                    if let uiImage = PhotoStorageService.shared.loadImage(named: context.attachment.filePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = min(max(value, 1.0), 4.0)
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring()) {
                                            if zoomScale < 1.1 { zoomScale = 1.0 }
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    zoomScale = zoomScale > 1.0 ? 1.0 : 2.2
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .padding(.horizontal, AppSpacing.sm)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.7))
                            Text(" Tệp minh chứng: \(context.attachment.filePath)")
                                .font(AppTypography.footnote)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    #endif

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(context.className)
                                .font(AppTypography.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.accentRose)
                            Spacer()
                            Text(context.attachment.createdAt.formatted(date: .numeric, time: .shortened))
                                .font(AppTypography.caption2)
                                .foregroundColor(.white.opacity(0.75))
                        }

                        Text(context.sessionTitle)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.onPrimary)

                        if !context.attachment.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Ghi chú: \(context.attachment.caption)")
                                .font(AppTypography.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.md)
                }
            }
            .navigationTitle("Ảnh minh chứng buổi học")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.onPrimary)
                }
            }
        }
    }
}
