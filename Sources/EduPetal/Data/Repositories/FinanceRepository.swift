import Foundation
import SwiftData

/// Hiện thực hóa FinanceRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class FinanceRepository: FinanceRepositoryProtocol {
    private let modelContext: ModelContext
    private let explicitOwnerId: String?

    public var activeOwnerId: String {
        explicitOwnerId ?? UserSessionManager.shared.currentOwnerId
    }

    public init(modelContainer: ModelContainer, ownerId: String? = nil) {
        self.modelContext = modelContainer.mainContext
        self.explicitOwnerId = ownerId
    }

    public init(modelContext: ModelContext, ownerId: String? = nil) {
        self.modelContext = modelContext
        self.explicitOwnerId = ownerId
    }

    // MARK: - Charge Operations

    public func fetchCharges() async throws -> [ChargeEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ChargeModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { FinanceMapper.toChargeEntity($0) }
    }

    public func fetchChargesForStudent(studentId: UUID) async throws -> [ChargeEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ChargeModel>(
            predicate: #Predicate<ChargeModel> { $0.studentId == studentId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { FinanceMapper.toChargeEntity($0) }
    }

    public func fetchChargesForSession(sessionId: UUID) async throws -> [ChargeEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ChargeModel>(
            predicate: #Predicate<ChargeModel> { $0.sessionId == sessionId }
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { FinanceMapper.toChargeEntity($0) }
    }

    public func fetchCharge(sessionId: UUID, studentId: UUID) async throws -> ChargeEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ChargeModel>(
            predicate: #Predicate<ChargeModel> { $0.sessionId == sessionId && $0.studentId == studentId }
        )
        guard let model = try modelContext.fetch(descriptor).first(where: { $0.ownerId == currentOwner }) else {
            return nil
        }
        return FinanceMapper.toChargeEntity(model)
    }

    public func saveCharge(_ charge: ChargeEntity) async throws {
        try await saveCharges([charge])
    }

    public func saveCharges(_ charges: [ChargeEntity]) async throws {
        let currentOwner = activeOwnerId
        for charge in charges {
            if !charge.ownerId.isEmpty && charge.ownerId != currentOwner {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: charge.ownerId,
                    currentUserId: currentOwner
                )
            }

            let chargeId = charge.id
            let descriptor = FetchDescriptor<ChargeModel>(
                predicate: #Predicate<ChargeModel> { $0.id == chargeId }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                guard existing.ownerId == currentOwner else {
                    throw SessionIsolationError.unauthorizedRecordAccess(
                        ownerId: existing.ownerId,
                        currentUserId: currentOwner
                    )
                }
                var owned = charge
                owned.ownerId = currentOwner
                FinanceMapper.updateChargeModel(existing, from: owned)
                continue
            }

            // Chống trùng theo (sessionId + studentId + ownerId)
            let targetSessionId = charge.sessionId
            let targetStudentId = charge.studentId
            let pairDesc = FetchDescriptor<ChargeModel>(
                predicate: #Predicate<ChargeModel> {
                    $0.sessionId == targetSessionId && $0.studentId == targetStudentId
                }
            )
            if let existingPair = try modelContext.fetch(pairDesc).first(where: { $0.ownerId == currentOwner }) {
                if existingPair.statusRaw == ChargeStatus.unpaid.rawValue {
                    existingPair.amount = charge.amount
                    existingPair.unitPriceSnapshot = charge.unitPriceSnapshot
                }
                continue
            }

            var owned = charge
            owned.ownerId = currentOwner
            let newModel = FinanceMapper.toChargeModel(owned)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func deleteUnpaidCharge(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<ChargeModel>(
            predicate: #Predicate<ChargeModel> { $0.id == id }
        )
        guard let existing = try modelContext.fetch(descriptor).first else { return }
        guard existing.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: existing.ownerId,
                currentUserId: currentOwner
            )
        }

        let allocations = try await fetchAllocationsForCharge(chargeId: id)
        guard existing.statusRaw == ChargeStatus.unpaid.rawValue && existing.allocations.isEmpty && allocations.isEmpty else {
            throw NSError(
                domain: "FinanceProtection",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Khoản học phí đã được thanh toán, không thể xóa hoặc hủy."]
            )
        }

        modelContext.delete(existing)
        try modelContext.save()
    }

    // MARK: - Payment Operations

    public func fetchPayments() async throws -> [PaymentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<PaymentModel>(
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { FinanceMapper.toPaymentEntity($0) }
    }

    public func fetchPaymentsForStudent(studentId: UUID) async throws -> [PaymentEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<PaymentModel>(
            predicate: #Predicate<PaymentModel> { $0.studentId == studentId },
            sortBy: [SortDescriptor(\.paidAt, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { FinanceMapper.toPaymentEntity($0) }
    }

    public func savePayment(_ payment: PaymentEntity) async throws {
        let currentOwner = activeOwnerId
        if !payment.ownerId.isEmpty && payment.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: payment.ownerId,
                currentUserId: currentOwner
            )
        }

        let paymentId = payment.id
        let descriptor = FetchDescriptor<PaymentModel>(
            predicate: #Predicate<PaymentModel> { $0.id == paymentId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            existing.amount = payment.amount
            existing.paidAt = payment.paidAt
            existing.paymentMethod = payment.paymentMethod
            existing.note = payment.note
        } else {
            var owned = payment
            owned.ownerId = currentOwner
            let newModel = FinanceMapper.toPaymentModel(owned)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    public func deletePayment(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<PaymentModel>(
            predicate: #Predicate<PaymentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Allocation Operations

    public func fetchAllocationsForPayment(paymentId: UUID) async throws -> [PaymentAllocationEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<PaymentAllocationModel>()
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { $0.payment?.id == paymentId && $0.payment?.ownerId == currentOwner }
        return filtered.map { FinanceMapper.toAllocationEntity($0) }
    }

    public func fetchAllocationsForCharge(chargeId: UUID) async throws -> [PaymentAllocationEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<PaymentAllocationModel>()
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { $0.charge?.id == chargeId && $0.charge?.ownerId == currentOwner }
        return filtered.map { FinanceMapper.toAllocationEntity($0) }
    }

    public func saveAllocations(_ allocations: [PaymentAllocationEntity]) async throws {
        let currentOwner = activeOwnerId
        let allExistingAllocations = (try? modelContext.fetch(FetchDescriptor<PaymentAllocationModel>())) ?? []
        for alloc in allocations {
            let pid = alloc.paymentId
            let cid = alloc.chargeId

            if let existingAlloc = allExistingAllocations.first(where: {
                $0.id == alloc.id || ($0.payment?.id == pid && $0.charge?.id == cid)
            }) {
                guard existingAlloc.payment?.ownerId == currentOwner else {
                    throw SessionIsolationError.unauthorizedRecordAccess(
                        ownerId: existingAlloc.payment?.ownerId ?? "",
                        currentUserId: currentOwner
                    )
                }
                existingAlloc.allocatedAmount = alloc.allocatedAmount
                existingAlloc.allocatedAt = alloc.allocatedAt
                continue
            }

            let pDesc = FetchDescriptor<PaymentModel>(predicate: #Predicate<PaymentModel> { $0.id == pid })
            let cDesc = FetchDescriptor<ChargeModel>(predicate: #Predicate<ChargeModel> { $0.id == cid })

            guard let paymentModel = try modelContext.fetch(pDesc).first,
                  let chargeModel = try modelContext.fetch(cDesc).first else { continue }

            guard paymentModel.ownerId == currentOwner && chargeModel.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: paymentModel.ownerId != currentOwner ? paymentModel.ownerId : chargeModel.ownerId,
                    currentUserId: currentOwner
                )
            }

            let newModel = PaymentAllocationModel(
                id: alloc.id,
                payment: paymentModel,
                charge: chargeModel,
                allocatedAmount: alloc.allocatedAmount,
                allocatedAt: alloc.allocatedAt
            )
            modelContext.insert(newModel)
            paymentModel.allocations.append(newModel)
            chargeModel.allocations.append(newModel)
        }
        try modelContext.save()
    }
}
