import Foundation

/// Thực thể thuần Swift đại diện cho Khoản tiền thực thu từ học sinh / phụ huynh (Domain Entity)
public struct PaymentEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let studentId: UUID
    public var amount: Int64          // Số tiền thực thu (Int64 VND)
    public var paidAt: Date           // Ngày nhận tiền thực tế
    public var paymentMethod: String  // Tiền mặt, Chuyển khoản ngân hàng...
    public var note: String
    public var ownerId: String
    public var createdAt: Date

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
    }
}

