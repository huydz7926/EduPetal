import Foundation

/// Lỗi xác thực dữ liệu điểm số
public enum GradeValidationError: Error, LocalizedError, Equatable {
    case negativeScore
    case scoreExceedsMax(score: Double, maxScore: Double)
    case invalidMaxScore

    public var errorDescription: String? {
        switch self {
        case .negativeScore:
            return "Điểm số không được là số âm (phải >= 0)."
        case .scoreExceedsMax(let score, let maxScore):
            return "Điểm số nhập vào (\(score)) vượt quá điểm tối đa cho phép (\(maxScore))."
        case .invalidMaxScore:
            return "Điểm tối đa của bài đánh giá phải lớn hơn 0."
        }
    }
}

/// Ca sử dụng thẩm định tính hợp lệ của Điểm số trước khi lưu
/// Quy tắc: 0 <= score <= maxScore
public struct ValidateGradeInputUseCase: Sendable {
    public init() {}

    public func execute(score: Double, maxScore: Double) throws {
        guard maxScore > 0 else {
            throw GradeValidationError.invalidMaxScore
        }
        guard score >= 0 else {
            throw GradeValidationError.negativeScore
        }
        guard score <= maxScore else {
            throw GradeValidationError.scoreExceedsMax(score: score, maxScore: maxScore)
        }
    }
}

