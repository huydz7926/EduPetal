import SwiftUI

/// Màn hình Quản lý Bảng điểm & Bài đánh giá theo Lớp học (Module 6 — Grade Management)
public struct GradeListView: View {
    @State public var viewModel: GradeViewModel
    @State private var isShowingCreateAssessmentSheet: Bool = false
    @State private var selectedAssessmentForGrading: AssessmentEntity?

    public init(viewModel: GradeViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView("Đang tải bảng điểm...")
                Spacer()
            } else if viewModel.assessments.isEmpty {
                EmptyStateView(
                    icon: "chart.bar.doc.horizontal",
                    title: "Chưa có bài đánh giá",
                    message: "Tạo bài kiểm tra đầu tiên (15 phút, 1 tiết, giữa kỳ) để nhập điểm cho học sinh.",
                    actionTitle: "Tạo cột điểm mới"
                ) {
                    isShowingCreateAssessmentSheet = true
                }
            } else {
                List {
                    ForEach(viewModel.assessments) { assessment in
                        AppCard {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                HStack {
                                    Text(assessment.title)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)

                                    Spacer()

                                    Text("Hệ số \(String(format: "%.1f", assessment.weight))")
                                        .font(AppTypography.caption2)
                                        .padding(.horizontal, AppSpacing.xs)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(AppColors.secondaryPink))
                                        .foregroundColor(AppColors.accentRose)
                                }

                                HStack {
                                    Text("Điểm tối đa: \(String(format: "%.1f", assessment.maxScore))")
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.secondaryText)

                                    Spacer()

                                    Text(assessment.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.tertiaryText)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Bảng điểm")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateAssessmentSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accentRose)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateAssessmentSheet) {
            createAssessmentSheet
        }
        .task {
            await viewModel.loadAssessments()
        }
    }

    private var createAssessmentSheet: some View {
        NavigationStack {
            CreateAssessmentForm { newAssessment in
                Task {
                    await viewModel.saveAssessment(newAssessment)
                }
            }
        }
    }
}

private struct CreateAssessmentForm: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AssessmentEntity) -> Void

    @State private var title: String = ""
    @State private var maxScore: Double = 10.0
    @State private var weight: Double = 1.0
    @State private var date: Date = Date()

    var body: some View {
        Form {
            Section("Thông tin bài đánh giá") {
                TextField("Tên bài kiểm tra (ví dụ: Kiểm tra 15 phút Số 1) *", text: $title)

                Stepper("Điểm tối đa: \(String(format: "%.1f", maxScore))", value: $maxScore, in: 5...100, step: 5)

                Stepper("Trọng số (Hệ số): \(String(format: "%.1f", weight))", value: $weight, in: 0.5...5.0, step: 0.5)

                DatePicker("Ngày kiểm tra", selection: $date, displayedComponents: [.date])
            }
        }
        .navigationTitle("Tạo cột điểm mới")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Hủy") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    let assessment = AssessmentEntity(
                        classId: UUID(), // Sẽ gắn theo class
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        maxScore: maxScore,
                        weight: weight,
                        date: date
                    )
                    onSave(assessment)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundColor(AppColors.accentRose)
            }
        }
    }
}

