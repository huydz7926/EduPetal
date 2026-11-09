import Foundation

/// Giao thức truy xuất dữ liệu Tài chính & Học phí (Domain Repository Protocol)
@MainActor
public protocol FinanceRepositoryProtocol: AnyObject {
    // Charge Operations
    func fetchCharges() async throws -> [ChargeEntity]
    func fetchChargesForStudent(studentId: UUID) async throws -> [ChargeEntity]
    func fetchChargesForSession(sessionId: UUID) async throws -> [ChargeEntity]
    func fetchCharge(sessionId: UUID, studentId: UUID) async throws -> ChargeEntity?
    func saveCharge(_ charge: ChargeEntity) async throws
    func saveCharges(_ charges: [ChargeEntity]) async throws
    func deleteUnpaidCharge(id: UUID) async throws

    // Payment Operations
    func fetchPayments() async throws -> [PaymentEntity]
    func fetchPaymentsForStudent(studentId: UUID) async throws -> [PaymentEntity]
    func savePayment(_ payment: PaymentEntity) async throws
    func deletePayment(id: UUID) async throws

    // Allocation Operations
    func fetchAllocationsForPayment(paymentId: UUID) async throws -> [PaymentAllocationEntity]
    func fetchAllocationsForCharge(chargeId: UUID) async throws -> [PaymentAllocationEntity]
    func saveAllocations(_ allocations: [PaymentAllocationEntity]) async throws
}

public extension FinanceRepositoryProtocol {
    func deleteUnpaidCharge(id: UUID) async throws {}
}

