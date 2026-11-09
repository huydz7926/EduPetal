import Foundation

/// Use case tính toán bảng tổng kết tài chính (Accrued, Collected, Outstanding)
/// Đảm bảo tính nhất quán Single-Source: Accrued - Collected = Outstanding
public struct CalculateFinanceSummaryUseCase: Sendable {
    public init() {}

    /// Tính toán tổng quan tài chính toàn hệ thống từ danh sách charges và payments
    public func execute(
        charges: [ChargeEntity],
        payments: [PaymentEntity]
    ) -> FinanceSummaryEntity {
        let totalAccrued = charges.reduce(0 as Int64) { $0 + $1.amount }
        let totalCollected = payments.reduce(0 as Int64) { $0 + $1.amount }
        return FinanceSummaryEntity(
            accruedTuition: totalAccrued,
            collectedTuition: totalCollected
        )
    }

    /// Tính toán tài chính cho một học sinh cụ thể
    public func executeForStudent(
        studentId: UUID,
        charges: [ChargeEntity],
        payments: [PaymentEntity]
    ) -> FinanceSummaryEntity {
        let studentCharges = charges.filter { $0.studentId == studentId }
        let studentPayments = payments.filter { $0.studentId == studentId }
        return execute(charges: studentCharges, payments: studentPayments)
    }

    /// Tính toán tài chính trong một khoảng thời gian (dựa theo thời điểm phát sinh hoặc thanh toán)
    public func executeInDateRange(
        from startDate: Date,
        to endDate: Date,
        charges: [ChargeEntity],
        payments: [PaymentEntity]
    ) -> FinanceSummaryEntity {
        let filteredCharges = charges.filter { $0.createdAt >= startDate && $0.createdAt <= endDate }
        let filteredPayments = payments.filter { $0.paidAt >= startDate && $0.paidAt <= endDate }
        return execute(charges: filteredCharges, payments: filteredPayments)
    }
}

