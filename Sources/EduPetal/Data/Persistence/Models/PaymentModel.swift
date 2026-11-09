import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Khoản tiền thực thu
@Model
public final class PaymentModel {
    @Attribute(.unique) public var id: UUID
    public var studentId: UUID
    public var amount: Int64
    public var paidAt: Date
    public var paymentMethod: String
    public var note: String
    public var ownerId: String = ""
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PaymentAllocationModel.payment)
    public var allocations: [PaymentAllocationModel] = []

    public init(
        id: UUID = UUID(),
        studentId: UUID,
        amount: Int64,
        paidAt: Date = Date(),
        paymentMethod: String = "Tiền mặt",
        note: String = "",
        ownerId: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.amount = amount
        self.paidAt = paidAt
        self.paymentMethod = paymentMethod
        self.note = note
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.allocations = []
    }
}

