import Foundation

/// DTO liên kết điểm số của học sinh với thông tin bài đánh giá
public struct StudentGradeItem: Sendable, Equatable {
    public let grade: GradeEntity
    public let assessment: AssessmentEntity

    public init(grade: GradeEntity, assessment: AssessmentEntity) {
        self.grade = grade
        self.assessment = assessment
    }
}

/// Ca sử dụng tính điểm trung bình theo trọng số (thang điểm 10 chuẩn)
public struct CalculateWeightedAverageUseCase: Sendable {
    public init() {}

    public func execute(items: [StudentGradeItem]) -> Double? {
        guard !items.isEmpty else { return nil }

        var totalWeightedScore: Double = 0.0
        var totalWeight: Double = 0.0

        for item in items {
            guard item.assessment.maxScore > 0, item.assessment.weight > 0 else { continue }
            // Quy đổi về thang điểm 10 chuẩn
            let normalizedScore = (item.grade.score / item.assessment.maxScore) * 10.0
            totalWeightedScore += normalizedScore * item.assessment.weight
            totalWeight += item.assessment.weight
        }

        guard totalWeight > 0 else { return nil }
        let average = totalWeightedScore / totalWeight
        // Làm tròn đến 1 chữ số thập phân
        return (average * 10).rounded() / 10
    }
}

