import SwiftUI

/// Màn hình Tạo mới / Chỉnh sửa Lớp học (Sheet Modal)
public struct ClassEditView: View {
    @Environment(\.dismiss) private var dismiss

    public let initialClass: ClassGroupEntity?
    public let onSave: (ClassGroupEntity) -> Void

    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var defaultPrice: Int64 = 150000
    @State private var durationMinutes: Int = 90
    @State private var selectedColorHex: String = "#E88FA8"
    @State private var notes: String = ""
    @State private var isSaving: Bool = false

    private let availableColors = [
        "#E88FA8", "#D63384", "#B84D73", "#EF4444",
        "#F97316", "#E69F00", "#10B981", "#27B48B",
        "#14B8A6", "#06B6D4", "#3B82F6", "#4A90E2",
        "#6366F1", "#8B5CF6", "#A855F7", "#64748B"
    ]

    private let quickPrices: [Int64] = [150_000, 200_000, 250_000, 300_000]

    public init(
        classGroup: ClassGroupEntity? = nil,
        onSave: @escaping (ClassGroupEntity) -> Void
    ) {
        self.initialClass = classGroup
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && defaultPrice > 0
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(L("Thông tin bắt buộc", "Required Info")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Tên lớp *", "Class Name *"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(L("Ví dụ: Toán 12 Nâng cao", "e.g. Math 12"), text: $name)
                            .font(AppTypography.body)
                    }

                    CurrencyTextField(
                        L("Đơn giá mặc định mỗi buổi (VND) *", "Default Price per Session (VND) *"),
                        placeholder: "150.000",
                        value: $defaultPrice
                    )

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(quickPrices, id: \.self) { preset in
                                Button {
                                    defaultPrice = preset
                                } label: {
                                    Text(preset.formattedVND)
                                        .font(AppTypography.caption1)
                                        .fontWeight(defaultPrice == preset ? .bold : .medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(
                                                defaultPrice == preset
                                                    ? AppColors.accentRose
                                                    : AppColors.secondaryPink.opacity(0.6)
                                            )
                                        )
                                        .foregroundColor(defaultPrice == preset ? .white : AppColors.accentRose)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if defaultPrice <= 0 {
                        Label(
                            L("Vui lòng nhập đơn giá lớn hơn 0 ₫.", "Please enter a price greater than 0 ₫."),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(AppTypography.caption1)
                        .foregroundColor(AppColors.error)
                    }
                }

                Section(L("Thông tin bổ sung (Tùy chọn)", "Optional Info")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Môn học", "Subject"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(
                            L("Ví dụ: Toán, Tiếng Anh, Vật lý", "e.g. Math, English, Physics"),
                            text: $subject
                        )
                        .font(AppTypography.body)
                    }

                    Stepper(value: $durationMinutes, in: 30...300, step: 15) {
                        HStack {
                            Text(L("Thời lượng buổi học:", "Session Duration:"))
                                .font(AppTypography.body)
                            Spacer()
                            Text(L("\(durationMinutes) phút", "\(durationMinutes) mins"))
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.accentRose)
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(L("Màu nhận diện lớp (\(availableColors.count) màu)", "Class Color (\(availableColors.count) colors)"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8),
                            spacing: 12
                        ) {
                            ForEach(availableColors, id: \.self) { hex in
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColorHex == hex ? 2.5 : 0)
                                        )

                                    if selectedColorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .onTapGesture {
                                    selectedColorHex = hex
                                }
                            }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Ghi chú lớp học", "Class Notes"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextEditor(text: $notes)
                            .frame(minHeight: 72)
                            .font(AppTypography.body)
                    }
                }
            }
            .navigationTitle(initialClass == nil ? L("Tạo lớp mới", "Create Class") : L("Sửa thông tin lớp", "Edit Class"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Hủy", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Lưu", "Save")) {
                        guard !isSaving, isValid else { return }
                        isSaving = true
                        let toSave = ClassGroupEntity(
                            id: initialClass?.id ?? UUID(),
                            name: trimmedName,
                            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                            defaultPricePerSession: defaultPrice,
                            sessionDurationMinutes: durationMinutes,
                            colorHex: selectedColorHex,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            isArchived: initialClass?.isArchived ?? false,
                            createdAt: initialClass?.createdAt ?? Date(),
                            updatedAt: Date()
                        )
                        onSave(toSave)
                        dismiss()
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.accentRose)
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if let c = initialClass {
                    name = c.name
                    subject = c.subject
                    defaultPrice = c.defaultPricePerSession
                    durationMinutes = c.sessionDurationMinutes
                    selectedColorHex = c.colorHex
                    notes = c.notes
                }
            }
        }
    }
}

