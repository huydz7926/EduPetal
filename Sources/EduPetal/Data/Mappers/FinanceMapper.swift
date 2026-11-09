import Foundation

/// Bộ chuyển đổi giữa ChargeModel / PaymentModel / PaymentAllocationModel và Domain Entities
public enum FinanceMapper {
    public static func toChargeEntity(_ model: ChargeModel) -> ChargeEntity {
        ChargeEntity(
            id: model.id,
            sessionId: model.sessionId,
            studentId: model.studentId,
            amount: model.amount,
            unitPriceSnapshot: model.unitPriceSnapshot,
            status: ChargeStatus(rawValue: model.statusRaw) ?? .unpaid,
            ownerId: model.ownerId,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    public static func updateChargeModel(_ model: ChargeModel, from entity: ChargeEntity) {
        model.amount = entity.amount
        model.unitPriceSnapshot = entity.unitPriceSnapshot
        model.statusRaw = entity.status.rawValue
        if !entity.ownerId.isEmpty {
            model.ownerId = entity.ownerId
        }
        model.updatedAt = entity.updatedAt
    }

    public static func toChargeModel(_ entity: ChargeEntity) -> ChargeModel {
        ChargeModel(
            id: entity.id,
            sessionId: entity.sessionId,
            studentId: entity.studentId,
            amount: entity.amount,
            unitPriceSnapshot: entity.unitPriceSnapshot,
            statusRaw: entity.status.rawValue,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    public static func toPaymentEntity(_ model: PaymentModel) -> PaymentEntity {
        PaymentEntity(
            id: model.id,
            studentId: model.studentId,
            amount: model.amount,
            paidAt: model.paidAt,
            paymentMethod: model.paymentMethod,
            note: model.note,
            ownerId: model.ownerId,
            createdAt: model.createdAt
        )
    }

    public static func toPaymentModel(_ entity: PaymentEntity) -> PaymentModel {
        PaymentModel(
            id: entity.id,
            studentId: entity.studentId,
            amount: entity.amount,
            paidAt: entity.paidAt,
            paymentMethod: entity.paymentMethod,
            note: entity.note,
            ownerId: entity.ownerId,
            createdAt: entity.createdAt
        )
    }

    public static func toAllocationEntity(_ model: PaymentAllocationModel) -> PaymentAllocationEntity {
        PaymentAllocationEntity(
            id: model.id,
            paymentId: model.payment?.id ?? UUID(),
            chargeId: model.charge?.id ?? UUID(),
            allocatedAmount: model.allocatedAmount,
            allocatedAt: model.allocatedAt
        )
    }
}

