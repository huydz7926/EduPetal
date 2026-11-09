import Foundation

/// Trạng thái thanh toán của một khoản học phí
public enum ChargeStatus: String, Codable, CaseIterable, Sendable {
    case unpaid = "unpaid"               // Chưa thanh toán
    case partiallyPaid = "partially_paid" // Đã thanh toán một phần
    case paid = "paid"                   // Đã thanh toán đầy đủ

    public var displayName: String {
        switch self {
        case .unpaid: return "Chưa thu"
        case .partiallyPaid: return "Thu một phần"
        case .paid: return "Đã thu"
        }
    }
}

/// Thực thể thuần Swift đại diện cho Khoản học phí phát sinh từ buổi học (Domain Entity)
/// Bắt buộc sử dụng Int64 cho tiền VND và lưu trữ snapshot đơn giá
public struct ChargeEntity: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sessionId: UUID
    public let studentId: UUID
    public var amount: Int64              // Số tiền phải nộp (Int64 VND)
    public var unitPriceSnapshot: Int64    // Đơn giá tại thời điểm buổi học diễn ra
    public var status: ChargeStatus
    public var ownerId: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        studentId: UUID,
        amount: Int64,
        unitPriceSnapshot: Int64,
        status: ChargeStatus = .unpaid,
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.studentId = studentId
        self.amount = amount
        self.unitPriceSnapshot = unitPriceSnapshot
        self.status = status
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

