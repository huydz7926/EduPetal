import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Màn hình Tạo mới / Chỉnh sửa Hồ sơ Học sinh (Sheet Modal)
public struct StudentEditView: View {
    @Environment(\.dismiss) private var dismiss

    public let initialStudent: StudentEntity?
    public let onSave: (StudentEntity) -> Void

    @State private var fullName: String = ""
    @State private var phoneNumber: String = ""
    @State private var parentPhone: String = ""
    @State private var email: String = ""
    @State private var hasCustomPrice: Bool = false
    @State private var customPrice: Int64 = 0
    @State private var notes: String = ""
    @State private var avatarPath: String? = nil

    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    #if canImport(UIKit)
    @State private var avatarEditItem: AvatarEditItem? = nil
    #endif
    #endif
    #if canImport(UIKit)
    @State private var previewImage: UIImage? = nil
    #endif
    @State private var isAvatarRemoved: Bool = false
    @State private var isAvatarChanged: Bool = false
    @State private var isSaving: Bool = false

    private var isValidStudentForm: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasCustomPrice || customPrice > 0)
    }

    public init(
        student: StudentEntity? = nil,
        onSave: @escaping (StudentEntity) -> Void
    ) {
        self.initialStudent = student
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Avatar Section (Feature 12)
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: AppSpacing.sm) {
                            ZStack {
                                #if canImport(UIKit)
                                if let image = previewImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(Circle())
                                } else if !isAvatarRemoved, let path = avatarPath, let loaded = AvatarStorageService.shared.loadAvatar(named: path) {
                                    Image(uiImage: loaded)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(Circle())
                                } else {
                                    defaultInitialsView
                                }
                                #else
                                defaultInitialsView
                                #endif
                            }
                            .overlay(Circle().stroke(AppColors.accentRose.opacity(0.35), lineWidth: 2))
                            #if canImport(UIKit)
                            .onTapGesture {
                                if let img = previewImage {
                                    avatarEditItem = AvatarEditItem(image: img)
                                } else if !isAvatarRemoved, let path = avatarPath,
                                          let loaded = AvatarStorageService.shared.loadAvatar(named: path) {
                                    avatarEditItem = AvatarEditItem(image: loaded)
                                }
                            }
                            #endif

                            let photoButtonLabel = hasActivePhoto ? L("Đổi ảnh", "Change Photo") : L("Chọn ảnh", "Choose Photo")
                            HStack(spacing: AppSpacing.md) {
                                #if canImport(PhotosUI)
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Label(photoButtonLabel, systemImage: "photo.on.rectangle")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.accentRose)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AppColors.secondaryPink.opacity(0.4))
                                        .cornerRadius(AppRadius.full)
                                }
                                .buttonStyle(.borderless)
                                #endif

                                if hasActivePhoto {
                                    #if canImport(UIKit)
                                    Button {
                                        if let img = previewImage {
                                            avatarEditItem = AvatarEditItem(image: img)
                                        } else if let path = avatarPath,
                                                  let loaded = AvatarStorageService.shared.loadAvatar(named: path) {
                                            avatarEditItem = AvatarEditItem(image: loaded)
                                        }
                                    } label: {
                                        Label(L("Chỉnh sửa", "Edit"), systemImage: "crop")
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.accentRose)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppColors.secondaryPink.opacity(0.4))
                                            .cornerRadius(AppRadius.full)
                                    }
                                    .buttonStyle(.borderless)
                                    #endif

                                    Button(role: .destructive) {
                                        #if canImport(PhotosUI)
                                        selectedPhotoItem = nil
                                        #endif
                                        #if canImport(UIKit)
                                        previewImage = nil
                                        #endif
                                        isAvatarRemoved = true
                                        isAvatarChanged = true
                                    } label: {
                                        Label(L("Xóa ảnh", "Remove"), systemImage: "trash")
                                            .font(AppTypography.caption1)
                                            .foregroundColor(AppColors.error)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppColors.error.opacity(0.08))
                                            .cornerRadius(AppRadius.full)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section(L("Thông tin học sinh", "Student Info")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Họ và tên *", "Full Name *"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(L("Nhập họ và tên", "Enter full name"), text: $fullName)
                            .font(AppTypography.body)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Số điện thoại học sinh", "Student Phone"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(L("Nhập số điện thoại", "Enter phone number"), text: $phoneNumber)
                            #if canImport(UIKit)
                            .keyboardType(.phonePad)
                            #endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Số điện thoại phụ huynh", "Parent Phone"))
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(L("Nhập số điện thoại phụ huynh", "Enter parent phone"), text: $parentPhone)
                            #if canImport(UIKit)
                            .keyboardType(.phonePad)
                            #endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.secondaryText)
                        TextField(L("Nhập địa chỉ email", "Enter email address"), text: $email)
                            #if canImport(UIKit)
                            .keyboardType(.emailAddress)
                            #endif
                    }
                }

                Section(L("Học phí riêng (Tùy chọn)", "Custom Tuition (Optional)")) {
                    Toggle(L("Thiết lập đơn giá riêng", "Use custom session price"), isOn: $hasCustomPrice)
                        .tint(AppColors.primaryPink)

                    if hasCustomPrice {
                        CurrencyTextField(L("Đơn giá mỗi buổi (VND)", "Price per Session (VND)"), placeholder: "150.000", value: $customPrice)
                        if customPrice <= 0 {
                            Label(L("Vui lòng nhập đơn giá lớn hơn 0 ₫.", "Please enter a price greater than 0 ₫."), systemImage: "exclamationmark.triangle.fill")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.error)
                        }
                    }
                }

                Section(L("Ghi chú", "Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(AppTypography.body)
                }
            }
            .navigationTitle(initialStudent == nil ? "Thêm học sinh" : "Sửa hồ sơ")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveStudentAction()
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.accentRose)
                    .disabled(!isValidStudentForm || isSaving)
                }
            }
            .onAppear {
                if let s = initialStudent {
                    fullName = s.fullName
                    phoneNumber = s.phoneNumber
                    parentPhone = s.parentPhone
                    email = s.email
                    notes = s.notes
                    avatarPath = s.avatarPath
                    if let price = s.defaultPricePerSession {
                        hasCustomPrice = true
                        customPrice = price
                    }
                }
            }
            #if canImport(UIKit)
            .fullScreenCover(item: $avatarEditItem) { item in
                AvatarEditorView(
                    image: item.image,
                    onCancel: { avatarEditItem = nil },
                    onDone: { edited in
                        previewImage = edited
                        isAvatarChanged = true
                        isAvatarRemoved = false
                        avatarEditItem = nil
                    }
                )
            }
            #endif
            #if canImport(PhotosUI)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        #if canImport(UIKit)
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                self.avatarEditItem = AvatarEditItem(image: image)
                                self.selectedPhotoItem = nil
                            }
                        }
                        #endif
                    }
                }
            }
            #endif
        }
    }

    private var hasActivePhoto: Bool {
        #if canImport(UIKit)
        if previewImage != nil { return true }
        #endif
        return !isAvatarRemoved && avatarPath != nil && !(avatarPath?.isEmpty ?? true)
    }

    private var defaultInitialsView: some View {
        ZStack {
            Circle()
                .fill(AppColors.secondaryPink)
                .frame(width: 84, height: 84)

            Text(initials(for: fullName))
                .font(AppTypography.title1)
                .foregroundColor(AppColors.accentRose)
                .fontWeight(.bold)
        }
    }

    private func saveStudentAction() {
        guard !isSaving, isValidStudentForm else { return }
        isSaving = true
        var finalAvatarPath = avatarPath
        #if canImport(UIKit)
        if isAvatarRemoved {
            if let old = initialStudent?.avatarPath {
                AvatarStorageService.shared.deleteAvatar(named: old)
            }
            finalAvatarPath = nil
        } else if isAvatarChanged, let image = previewImage {
            let studentPrefix = "stu_\(initialStudent?.id.uuidString.prefix(6) ?? UUID().uuidString.prefix(6))"
            if let saved = try? AvatarStorageService.shared.saveAvatar(
                image: image,
                prefix: studentPrefix,
                oldAvatarPath: initialStudent?.avatarPath
            ) {
                finalAvatarPath = saved
            }
        }
        #endif

        let studentToSave = StudentEntity(
            id: initialStudent?.id ?? UUID(),
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            parentPhone: parentPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultPricePerSession: hasCustomPrice ? customPrice : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isArchived: initialStudent?.isArchived ?? false,
            avatarPath: finalAvatarPath,
            createdAt: initialStudent?.createdAt ?? Date(),
            updatedAt: Date()
        )
        onSave(studentToSave)
        dismiss()
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if let last = parts.last, let first = last.first {
            return String(first).uppercased()
        }
        return "EP"
    }
}
