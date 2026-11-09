import Foundation

/// Các lỗi có thể xảy ra khi ghi nhận thanh toán học phí
public enum RecordPaymentError: Error, LocalizedError, Equatable {
    case invalidAmount(min: Int64)
    case exceedsOutstandingBalance(outstanding: Int64, attempted: Int64)
    case studentHasNoOutstandingBalance
    case noChargesSelected

    public var errorDescription: String? {
        switch self {
        case .invalidAmount(let min):
            return "Số tiền thanh toán không hợp lệ (phải tối thiểu \(min) ₫)."
        case .exceedsOutstandingBalance(let outstanding, let attempted):
            return "Số tiền thu (\(attempted.formattedVND)) vượt quá dư nợ của các khoản đã chọn (\(outstanding.formattedVND)). Hệ thống không cho phép thu thừa/trả trước."
        case .studentHasNoOutstandingBalance:
            return "Học sinh hiện không có dư nợ học phí cần thanh toán."
        case .noChargesSelected:
            return "Vui lòng chọn ít nhất một buổi học còn nợ cần thanh toán."
        }
    }
}

/// Kết quả sau khi ghi nhận thanh toán thành công
public struct RecordPaymentResult: Sendable, Equatable {
    public let payment: PaymentEntity
    public let allocations: [PaymentAllocationEntity]
    public let updatedCharges: [ChargeEntity]

    public init(
        payment: PaymentEntity,
        allocations: [PaymentAllocationEntity],
        updatedCharges: [ChargeEntity]
    ) {
        self.payment = payment
        self.allocations = allocations
        self.updatedCharges = updatedCharges
    }
}

/// Ca sử dụng Ghi nhận Thanh toán & Phân bổ công nợ cho các khoản học phí (Mục 5 /duan)
/// Bắt buộc đảm bảo:
/// 1. Số tiền > 0 và <= dư nợ còn lại của các buổi được chọn (Không cho phép thu thừa / trả trước).
/// 2. Hỗ trợ chọn các buổi cụ thể cần thanh toán (`selectedChargeIds`) hoặc phân bổ FIFO toàn bộ các buổi còn nợ.
/// 3. Cập nhật đúng trạng thái của từng khoản nợ (unpaid -> partiallyPaid -> paid).
/// 4. Chống ghi nhận/phân bổ trùng khi gọi lại với cùng `paymentId`.
public struct RecordPaymentUseCase: Sendable {
    public init() {}

    public func execute(
        paymentId: UUID = UUID(),
        studentId: UUID,
        amount: Int64,
        paidAt: Date = Date(),
        paymentMethod: String = "Tiền mặt",
        note: String = "",
        studentCharges: [ChargeEntity],
        existingAllocations: [PaymentAllocationEntity],
        selectedChargeIds: Set<UUID>? = nil
    ) throws -> RecordPaymentResult {
        guard amount > 0 else {
            throw RecordPaymentError.invalidAmount(min: 1)
        }

        // Chống phân bổ trùng nếu paymentId này đã được xử lý trước đó
        let existingForPayment = existingAllocations.filter { $0.paymentId == paymentId }
        if !existingForPayment.isEmpty {
            let existingPayment = PaymentEntity(
                id: paymentId,
                studentId: studentId,
                amount: amount,
                paidAt: paidAt,
                paymentMethod: paymentMethod,
                note: note,
                createdAt: paidAt
            )
            return RecordPaymentResult(
                payment: existingPayment,
                allocations: [],
                updatedCharges: []
            )
        }

        // Nếu giáo viên có truyền danh sách buổi được chọn, kiểm tra không được rỗng
        if let selectedIds = selectedChargeIds, selectedIds.isEmpty {
            throw RecordPaymentError.noChargesSelected
        }

        // Lọc các khoản phí mục tiêu (theo các buổi đã chọn hoặc toàn bộ các buổi của học sinh)
        let targetCharges: [ChargeEntity]
        if let selectedIds = selectedChargeIds {
            targetCharges = studentCharges.filter { selectedIds.contains($0.id) }
        } else {
            targetCharges = studentCharges
        }

        // Tính tổng tiền nợ phát sinh và đã phân bổ của các khoản mục tiêu
        let targetChargeIds = Set(targetCharges.map { $0.id })
        let relevantAllocations = existingAllocations.filter { targetChargeIds.contains($0.chargeId) }

        let targetOutstanding = targetCharges.reduce(0 as Int64) { sum, charge in
            let paidForCharge = relevantAllocations
                .filter { $0.chargeId == charge.id }
                .reduce(0 as Int64) { $0 + $1.allocatedAmount }
            return sum + max(0, charge.amount - paidForCharge)
        }

        // Kiểm tra tổng dư nợ toàn bộ của học sinh
        let allChargeIds = Set(studentCharges.map { $0.id })
        let allRelevantAllocations = existingAllocations.filter { allChargeIds.contains($0.chargeId) }
        let totalStudentOutstanding = studentCharges.reduce(0 as Int64) { sum, charge in
            let paid = allRelevantAllocations
                .filter { $0.chargeId == charge.id }
                .reduce(0 as Int64) { $0 + $1.allocatedAmount }
            return sum + max(0, charge.amount - paid)
        }

        guard totalStudentOutstanding > 0 else {
            throw RecordPaymentError.studentHasNoOutstandingBalance
        }

        guard targetOutstanding > 0 else {
            throw RecordPaymentError.noChargesSelected
        }

        guard amount <= targetOutstanding else {
            throw RecordPaymentError.exceedsOutstandingBalance(outstanding: targetOutstanding, attempted: amount)
        }

        // Tạo bản ghi Payment
        let payment = PaymentEntity(
            id: paymentId,
            studentId: studentId,
            amount: amount,
            paidAt: paidAt,
            paymentMethod: paymentMethod,
            note: note,
            createdAt: Date()
        )

        // Phân bổ FIFO trong phạm vi các buổi đã chọn (sắp xếp theo thời gian cũ nhất trước)
        let sortedCharges = targetCharges.sorted { $0.createdAt < $1.createdAt }

        var remainingToAllocate = amount
        var newAllocations: [PaymentAllocationEntity] = []
        var updatedCharges: [ChargeEntity] = []

        for charge in sortedCharges {
            guard remainingToAllocate > 0 else { break }

            let chargeAllocations = relevantAllocations.filter { $0.chargeId == charge.id }
            let alreadyPaid = chargeAllocations.reduce(0 as Int64) { $0 + $1.allocatedAmount }
            let remainingDue = charge.amount - alreadyPaid

            if remainingDue <= 0 {
                continue
            }

            let allocationAmount = min(remainingToAllocate, remainingDue)
            let allocation = PaymentAllocationEntity(
                paymentId: paymentId,
                chargeId: charge.id,
                allocatedAmount: allocationAmount,
                allocatedAt: paidAt
            )
            newAllocations.append(allocation)

            var updatedCharge = charge
            if alreadyPaid + allocationAmount >= charge.amount {
                updatedCharge.status = .paid
            } else {
                updatedCharge.status = .partiallyPaid
            }
            updatedCharge.updatedAt = paidAt
            updatedCharges.append(updatedCharge)

            remainingToAllocate -= allocationAmount
        }

        return RecordPaymentResult(
            payment: payment,
            allocations: newAllocations,
            updatedCharges: updatedCharges
        )
    }
}
