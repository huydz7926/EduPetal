import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Bản ghi phân bổ thanh toán
@Model
public final class PaymentAllocationModel {
    @Attribute(.unique) public var id: UUID
    public var allocatedAmount: Int64
    public var allocatedAt: Date

    public var payment: PaymentModel?
    public var charge: ChargeModel?

    public init(
        id: UUID = UUID(),
        payment: PaymentModel? = nil,
        charge: ChargeModel? = nil,
        allocatedAmount: Int64,
        allocatedAt: Date = Date()
    ) {
        self.id = id
        self.payment = payment
        self.charge = charge
        self.allocatedAmount = allocatedAmount
        self.allocatedAt = allocatedAt
    }
}

