import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Khoản học phí
@Model
public final class ChargeModel {
    @Attribute(.unique) public var id: UUID
    public var sessionId: UUID
    public var studentId: UUID
    public var amount: Int64
    public var unitPriceSnapshot: Int64
    public var statusRaw: String
    public var ownerId: String = ""
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PaymentAllocationModel.charge)
    public var allocations: [PaymentAllocationModel] = []

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        studentId: UUID,
        amount: Int64,
        unitPriceSnapshot: Int64,
        statusRaw: String = ChargeStatus.unpaid.rawValue,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.studentId = studentId
        self.amount = amount
        self.unitPriceSnapshot = unitPriceSnapshot
        self.statusRaw = statusRaw
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.allocations = []
    }
}

