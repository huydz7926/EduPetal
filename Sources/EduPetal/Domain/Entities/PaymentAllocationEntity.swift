import Foundation

/// Thực thể thuần Swift đại diện cho Bản ghi Phân bổ tiền thanh toán vào từng khoản phí (Domain Entity)
public struct PaymentAllocationEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let paymentId: UUID
    public let chargeId: UUID
    public var allocatedAmount: Int64   // Số tiền phân bổ cho khoản phí này (Int64 VND)
    public var allocatedAt: Date

    public init(
        id: UUID = UUID(),
        paymentId: UUID,
        chargeId: UUID,
        allocatedAmount: Int64,
        allocatedAt: Date = Date()
    ) {
        self.id = id
        self.paymentId = paymentId
        self.chargeId = chargeId
        self.allocatedAmount = allocatedAmount
        self.allocatedAt = allocatedAt
    }
}

/// DTO chứa 3 chỉ số tài chính cốt lõi bất biến của EduPetal
public struct FinanceSummaryEntity: Sendable, Equatable {
    public let accruedTuition: Int64      // Tổng học phí phát sinh từ các buổi học hoàn thành
    public let collectedTuition: Int64    // Tổng số tiền giáo viên đã thực sự nhận
    public let outstandingBalance: Int64   // Dư nợ còn phải thu (Accrued - Collected)

    public init(
        accruedTuition: Int64,
        collectedTuition: Int64
    ) {
        self.accruedTuition = accruedTuition
        self.collectedTuition = collectedTuition
        self.outstandingBalance = accruedTuition - collectedTuition
    }

    public static let zero = FinanceSummaryEntity(accruedTuition: 0, collectedTuition: 0)
}

