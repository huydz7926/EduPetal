import SwiftUI
import Charts

/// Biểu đồ tiến bộ học tập của học sinh sử dụng Swift Charts Native
public struct GradeProgressChartView: View {
    public let items: [StudentGradeItem]
    public let average: Double?

    public init(items: [StudentGradeItem], average: Double?) {
        self.items = items
        self.average = average
    }

    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tiến độ Điểm số & Đánh giá")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)

                        Text("Quy đổi thang điểm 10 chuẩn")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }

                    Spacer()

                    if let avg = average {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ĐTB Trọng số")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)

                            Text(String(format: "%.1f", avg))
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.accentRose)
                                .fontWeight(.bold)
                        }
                    }
                }

                if items.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Chưa có dữ liệu điểm",
                        message: "Nhập điểm các bài kiểm tra để theo dõi biểu đồ tiến bộ học tập."
                    )
                } else {
                    Chart {
                        // Đường trung bình ngang
                        if let avg = average {
                            RuleMark(y: .value("ĐTB", avg))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(AppColors.accentRose.opacity(0.6))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("ĐTB: \(String(format: "%.1f", avg))")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.accentRose)
                                        .padding(.trailing, 4)
                                }
                        }

                        // Đường nối điểm số
                        ForEach(items, id: \.grade.id) { item in
                            let normalized = (item.grade.score / item.assessment.maxScore) * 10.0

                            LineMark(
                                x: .value("Bài kiểm tra", item.assessment.title),
                                y: .value("Điểm quy đổi", normalized)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppColors.accentRose)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            PointMark(
                                x: .value("Bài kiểm tra", item.assessment.title),
                                y: .value("Điểm quy đổi", normalized)
                            )
                            .foregroundStyle(AppColors.accentRose)
                            .annotation(position: .top) {
                                Text(String(format: "%.1f", item.grade.score))
                                    .font(AppTypography.font(size: 10))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .frame(height: 200)
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
    }
}

