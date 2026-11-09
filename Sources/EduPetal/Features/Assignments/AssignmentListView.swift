import SwiftUI

/// Màn hình Danh sách Bài tập theo Lớp học (Module 5 — Assignment Management)
public struct AssignmentListView: View {
    @State public var viewModel: AssignmentViewModel
    @State private var isShowingCreateSheet: Bool = false

    public init(viewModel: AssignmentViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView("Đang tải danh sách bài tập...")
                Spacer()
            } else if viewModel.assignments.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.plus",
                    title: "Chưa có bài tập",
                    message: "Giao bài tập đầu tiên kèm hạn nộp và điểm tối đa cho học sinh trong lớp.",
                    actionTitle: "Giao bài tập mới"
                ) {
                    isShowingCreateSheet = true
                }
            } else {
                List {
                    ForEach(viewModel.assignments) { assignment in
                        AppCard {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                HStack {
                                    Text(assignment.title)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)

                                    Spacer()

                                    Text("Điểm tối đa: \(String(format: "%.1f", assignment.maxScore))")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.accentRose)
                                        .fontWeight(.semibold)
                                }

                                if !assignment.descriptionText.isEmpty {
                                    Text(assignment.descriptionText)
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(2)
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11))
                                    Text("Hạn nộp: \(assignment.dueDate.formatted(date: .abbreviated, time: .shortened))")
                                }
                                .font(AppTypography.caption2)
                                .foregroundColor(assignment.dueDate < Date() ? AppColors.error : AppColors.secondaryText)
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
        .navigationTitle("Bài tập")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accentRose)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            createAssignmentSheet
        }
        .task {
            await viewModel.loadAssignments()
        }
    }

    private var createAssignmentSheet: some View {
        NavigationStack {
            CreateAssignmentForm(classId: viewModel.classId) { newAssignment in
                Task {
                    await viewModel.saveAssignment(newAssignment)
                }
            }
        }
    }
}

private struct CreateAssignmentForm: View {
    @Environment(\.dismiss) private var dismiss
    let classId: UUID
    let onSave: (AssignmentEntity) -> Void

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var dueDate: Date = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var maxScore: Double = 10.0

    var body: some View {
        Form {
            Section("Thông tin bài tập") {
                TextField("Tiêu đề bài tập *", text: $title)

                TextField("Mô tả / Đề bài", text: $descriptionText)

                DatePicker("Hạn nộp", selection: $dueDate)

                Stepper("Điểm tối đa: \(String(format: "%.1f", maxScore))", value: $maxScore, in: 5...100, step: 5)
            }
        }
        .navigationTitle("Giao bài tập mới")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Hủy") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    let assignment = AssignmentEntity(
                        classId: classId,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        descriptionText: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                        dueDate: dueDate,
                        maxScore: maxScore
                    )
                    onSave(assignment)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundColor(AppColors.accentRose)
            }
        }
    }
}

