import SwiftUI

/// Item hiển thị học sinh tham gia buổi học kèm đơn giá hiệu dụng
public struct SessionParticipantItem: Identifiable, Sendable, Equatable {
    public let student: StudentEntity
    public let effectivePrice: Int64
    public let isCustomPrice: Bool
    public var id: UUID { student.id }

    public init(student: StudentEntity, effectivePrice: Int64, isCustomPrice: Bool) {
        self.student = student
        self.effectivePrice = effectivePrice
        self.isCustomPrice = isCustomPrice
    }
}

/// Màn hình Lên lịch / Chỉnh sửa Buổi dạy với Kiểm tra Trùng lịch (Overlap Check) tức thì
/// Hỗ trợ cả buổi học đơn lẻ và Lịch dạy cố định lặp lại theo tuần (Recurring Series)
/// Tự động snapshot danh sách học sinh tham gia, đơn giá và cho phép phân biệt "Chỉ buổi này" vs "Buổi này cùng các buổi tương lai"
public struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss

    public let initialSession: TeachingSessionEntity?
    public let classes: [ClassGroupEntity]
    public let existingSessions: [TeachingSessionEntity]
    public let classRepository: ClassRepositoryProtocol?
    public let studentRepository: StudentRepositoryProtocol?
    public let onSaveWithParticipants: ((TeachingSessionEntity, [UUID]) -> Void)?
    public let onSaveBatch: (([TeachingSessionEntity], [UUID]) -> Void)?
    public let onSaveSeriesOption: ((TeachingSessionEntity, Bool, [UUID]) -> Void)?
    public let onSaveLegacy: ((TeachingSessionEntity) -> Void)?

    @State private var selectedClassId: UUID
    @State private var title: String = ""
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(90 * 60)
    @State private var lessonNotes: String = ""
    @State private var homeworkAssigned: String = ""
    @State private var participants: [SessionParticipantItem] = []
    @State private var isLoadingParticipants: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    // MARK: - State cho Lịch lặp cố định
    @State private var isRecurring: Bool = false
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var recurrenceStartDate: Date = Date()
    @State private var recurrenceEndDate: Date = Date()
    @State private var isPreviewExpanded: Bool = false
    @State private var showSeriesDialog: Bool = false
    @State private var pendingSessionToSave: TeachingSessionEntity? = nil

    private let overlapUseCase = CheckScheduleOverlapUseCase()
    private let priceUseCase = GetEffectiveStudentPriceUseCase()
    private let recurringUseCase = GenerateRecurringSessionsUseCase()

    public init(
        session: TeachingSessionEntity? = nil,
        classes: [ClassGroupEntity],
        existingSessions: [TeachingSessionEntity],
        defaultDate: Date = Date(),
        classRepository: ClassRepositoryProtocol? = nil,
        studentRepository: StudentRepositoryProtocol? = nil,
        onSaveBatch: (([TeachingSessionEntity], [UUID]) -> Void)? = nil,
        onSaveSeriesOption: ((TeachingSessionEntity, Bool, [UUID]) -> Void)? = nil,
        onSave: @escaping (TeachingSessionEntity, [UUID]) -> Void
    ) {
        self.initialSession = session
        self.classes = classes
        self.existingSessions = existingSessions
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.onSaveWithParticipants = onSave
        self.onSaveBatch = onSaveBatch
        self.onSaveSeriesOption = onSaveSeriesOption
        self.onSaveLegacy = nil

        let firstClassId = session?.classId ?? classes.first?.id ?? UUID()
        self._selectedClassId = State(initialValue: firstClassId)

        let calendar = Calendar.current
        let defaultEndDate = calendar.date(byAdding: .month, value: 2, to: defaultDate) ?? defaultDate
        self._recurrenceStartDate = State(initialValue: defaultDate)
        self._recurrenceEndDate = State(initialValue: defaultEndDate)

        // Mặc định chọn ngày trong tuần của defaultDate
        let currentWeekday = calendar.component(.weekday, from: defaultDate)
        if let matchDay = DayOfWeek(rawValue: currentWeekday) {
            self._selectedDays = State(initialValue: [matchDay])
        }

        if let s = session {
            self._title = State(initialValue: s.title)
            self._startTime = State(initialValue: s.startTime)
            self._endTime = State(initialValue: s.endTime)
            self._lessonNotes = State(initialValue: s.userDisplayNotes)
            self._homeworkAssigned = State(initialValue: s.homeworkAssigned)
        } else {
            var components = calendar.dateComponents([.year, .month, .day], from: defaultDate)
            components.hour = 17
            components.minute = 30
            let start = calendar.date(from: components) ?? defaultDate
            let duration = (classes.first?.sessionDurationMinutes ?? 90) * 60
            self._startTime = State(initialValue: start)
            self._endTime = State(initialValue: start.addingTimeInterval(TimeInterval(duration)))
        }
    }

    /// Khởi tạo thuận tiện khi tạo chuỗi lịch lặp
    public init(
        classes: [ClassGroupEntity],
        existingSessions: [TeachingSessionEntity],
        defaultDate: Date = Date(),
        classRepository: ClassRepositoryProtocol? = nil,
        studentRepository: StudentRepositoryProtocol? = nil,
        onSaveBatch: @escaping ([TeachingSessionEntity], [UUID]) -> Void
    ) {
        self.initialSession = nil
        self.classes = classes
        self.existingSessions = existingSessions
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.onSaveWithParticipants = nil
        self.onSaveBatch = onSaveBatch
        self.onSaveSeriesOption = nil
        self.onSaveLegacy = nil

        let firstClassId = classes.first?.id ?? UUID()
        self._selectedClassId = State(initialValue: firstClassId)

        let calendar = Calendar.current
        let defaultEndDate = calendar.date(byAdding: .month, value: 2, to: defaultDate) ?? defaultDate
        self._recurrenceStartDate = State(initialValue: defaultDate)
        self._recurrenceEndDate = State(initialValue: defaultEndDate)

        let currentWeekday = calendar.component(.weekday, from: defaultDate)
        if let matchDay = DayOfWeek(rawValue: currentWeekday) {
            self._selectedDays = State(initialValue: [matchDay])
        }

        var components = calendar.dateComponents([.year, .month, .day], from: defaultDate)
        components.hour = 17
        components.minute = 30
        let start = calendar.date(from: components) ?? defaultDate
        let duration = (classes.first?.sessionDurationMinutes ?? 90) * 60
        self._startTime = State(initialValue: start)
        self._endTime = State(initialValue: start.addingTimeInterval(TimeInterval(duration)))
    }

    /// Khởi tạo tương thích ngược cho các nơi chỉ cần callback (TeachingSessionEntity) -> Void
    public init(
        session: TeachingSessionEntity? = nil,
        classes: [ClassGroupEntity],
        existingSessions: [TeachingSessionEntity],
        defaultDate: Date = Date(),
        classRepository: ClassRepositoryProtocol? = nil,
        studentRepository: StudentRepositoryProtocol? = nil,
        onSave: @escaping (TeachingSessionEntity) -> Void
    ) {
        self.initialSession = session
        self.classes = classes
        self.existingSessions = existingSessions
        self.classRepository = classRepository
        self.studentRepository = studentRepository
        self.onSaveWithParticipants = nil
        self.onSaveBatch = nil
        self.onSaveSeriesOption = nil
        self.onSaveLegacy = onSave

        let firstClassId = session?.classId ?? classes.first?.id ?? UUID()
        self._selectedClassId = State(initialValue: firstClassId)

        let calendar = Calendar.current
        let defaultEndDate = calendar.date(byAdding: .month, value: 2, to: defaultDate) ?? defaultDate
        self._recurrenceStartDate = State(initialValue: defaultDate)
        self._recurrenceEndDate = State(initialValue: defaultEndDate)

        let currentWeekday = calendar.component(.weekday, from: defaultDate)
        if let matchDay = DayOfWeek(rawValue: currentWeekday) {
            self._selectedDays = State(initialValue: [matchDay])
        }

        if let s = session {
            self._title = State(initialValue: s.title)
            self._startTime = State(initialValue: s.startTime)
            self._endTime = State(initialValue: s.endTime)
            self._lessonNotes = State(initialValue: s.userDisplayNotes)
            self._homeworkAssigned = State(initialValue: s.homeworkAssigned)
        } else {
            var components = calendar.dateComponents([.year, .month, .day], from: defaultDate)
            components.hour = 17
            components.minute = 30
            let start = calendar.date(from: components) ?? defaultDate
            let duration = (classes.first?.sessionDurationMinutes ?? 90) * 60
            self._startTime = State(initialValue: start)
            self._endTime = State(initialValue: start.addingTimeInterval(TimeInterval(duration)))
        }
    }

    /// Lớp học hiện đang được chọn
    private var selectedClass: ClassGroupEntity? {
        classes.first(where: { $0.id == selectedClassId })
    }

    /// Kiểm tra xem thời gian buổi học hiện tại có bị trùng với buổi khác không
    private var overlappingSession: TeachingSessionEntity? {
        overlapUseCase.execute(
            newStartTime: startTime,
            newEndTime: endTime,
            existingSessions: existingSessions,
            excludeSessionId: initialSession?.id
        )
    }

    /// Danh sách buổi học xem trước khi chọn chế độ lặp
    private var previewRecurringSessions: [TeachingSessionEntity] {
        guard isRecurring, !selectedDays.isEmpty, recurrenceEndDate >= recurrenceStartDate else {
            return []
        }
        let template = TeachingSessionEntity(
            classId: selectedClassId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (selectedClass?.name ?? "Buổi học")
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            startTime: startTime,
            endTime: endTime,
            status: .scheduled,
            lessonNotes: lessonNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            homeworkAssigned: homeworkAssigned.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return recurringUseCase.execute(
            templateSession: template,
            selectedDays: selectedDays,
            startDate: recurrenceStartDate,
            endDate: recurrenceEndDate,
            existingSessions: existingSessions
        )
    }

    /// Kiểm tra tính hợp lệ của Form
    private var isValid: Bool {
        guard !classes.isEmpty && endTime > startTime && !isSaving else { return false }
        if isRecurring && initialSession == nil {
            return !selectedDays.isEmpty && recurrenceEndDate >= recurrenceStartDate && !previewRecurringSessions.isEmpty
        }
        return true
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Kiểm tra chưa có lớp học
                if classes.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppColors.warning)
                                Text("Chưa có lớp học")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }

                            Text("Bạn cần tạo ít nhất một lớp học trước khi lên lịch buổi dạy.")
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }
                }

                // MARK: - Warning Banner nếu trùng lịch (cho buổi đơn lẻ)
                if !isRecurring, let overlap = overlappingSession {
                    Section {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.warning)
                                .font(AppTypography.font(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cảnh báo trùng lịch dạy!")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.warning)

                                Text("Trùng với '\(overlap.title.isEmpty ? "Buổi dạy" : overlap.title)' (\(overlap.startTime.formatted(date: .omitted, time: .shortened)) - \(overlap.endTime.formatted(date: .omitted, time: .shortened))).")
                                    .font(AppTypography.footnote)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }
                }

                // MARK: - Banner thông báo nếu buổi này thuộc chuỗi lặp cố định
                if let initial = initialSession, initial.seriesId != nil {
                    Section {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "repeat.circle.fill")
                                .foregroundColor(AppColors.accentRose)
                                .font(AppTypography.font(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buổi học thuộc chuỗi lịch lặp cố định")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)

                                Text("Khi bấm 'Lưu', bạn có thể chọn áp dụng thay đổi cho riêng buổi này hoặc cập nhật toàn bộ các buổi học tiếp theo.")
                                    .font(AppTypography.footnote)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }
                }

                // MARK: - Chọn Lớp học & Tiêu đề
                Section("Lớp học & Tiêu đề buổi dạy") {
                    if !classes.isEmpty {
                        Picker("Lớp học *", selection: $selectedClassId) {
                            ForEach(classes) { c in
                                HStack {
                                    Circle().fill(Color(hex: c.colorHex)).frame(width: 8, height: 8)
                                    Text(c.name).tag(c.id)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedClassId) { _, newId in
                            handleClassChange(newId: newId)
                        }
                    }

                    TextField("Tiêu đề buổi dạy (ví dụ: Chuyên đề Tích phân)", text: $title)
                        .font(AppTypography.body)

                    if let selectedClass {
                        HStack {
                            Text("Đơn giá mặc định lớp:")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text("\(selectedClass.defaultPricePerSession.formattedVND)/buổi")
                                .font(AppTypography.caption1)
                                .foregroundColor(AppColors.accentRose)
                                .fontWeight(.semibold)
                        }
                    }
                }

                // MARK: - Thời gian buổi học
                Section("Thời gian buổi dạy") {
                    DatePicker("Bắt đầu", selection: $startTime)
                        .font(AppTypography.body)
                        .onChange(of: startTime) { _, newStart in
                            if let selectedClass {
                                endTime = newStart.addingTimeInterval(TimeInterval(selectedClass.sessionDurationMinutes * 60))
                            }
                        }

                    DatePicker("Kết thúc", selection: $endTime)
                        .font(AppTypography.body)

                    if endTime <= startTime {
                        Text("Giờ kết thúc phải sau giờ bắt đầu.")
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                    }

                    HStack {
                        Text("Thời lượng:")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        let duration = max(0, Int(endTime.timeIntervalSince(startTime) / 60))
                        Text("\(duration) phút")
                            .font(AppTypography.headline)
                            .foregroundColor(endTime > startTime ? AppColors.accentRose : AppColors.error)
                    }
                }

                // MARK: - Lịch dạy lặp cố định (Chỉ hiển thị khi tạo mới buổi dạy)
                if initialSession == nil {
                    Section("Lịch lặp lại cố định") {
                        Toggle(isOn: $isRecurring.animation(.easeInOut(duration: 0.2))) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "repeat")
                                    .foregroundColor(AppColors.accentRose)
                                Text("Lặp lại theo ngày trong tuần")
                                    .font(AppTypography.body)
                            }
                        }
                        .tint(AppColors.accentRose)

                        if isRecurring {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Chọn các ngày học trong tuần *")
                                    .font(AppTypography.caption1)
                                    .foregroundColor(AppColors.secondaryText)

                                weekdayPicker
                            }
                            .padding(.vertical, 2)

                            DatePicker("Từ ngày", selection: $recurrenceStartDate, displayedComponents: [.date])
                                .font(AppTypography.body)

                            DatePicker("Đến ngày", selection: $recurrenceEndDate, in: recurrenceStartDate..., displayedComponents: [.date])
                                .font(AppTypography.body)

                            // Tóm tắt số lượng buổi học sẽ sinh ra
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                HStack {
                                    Image(systemName: "calendar.badge.checkmark")
                                        .foregroundColor(AppColors.accentRose)
                                    Text("Dự kiến tạo:")
                                        .font(AppTypography.subheadline)
                                    Spacer()
                                    Text("\(previewRecurringSessions.count) buổi học")
                                        .font(AppTypography.headline)
                                        .foregroundColor(previewRecurringSessions.isEmpty ? AppColors.error : AppColors.accentRose)
                                }

                                if previewRecurringSessions.isEmpty && !selectedDays.isEmpty {
                                    Text("Không có ngày nào khớp hoặc các buổi trong khoảng này đã tồn tại.")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(AppColors.warning)
                                }
                            }
                            .padding(.vertical, 2)

                            // Bản xem trước danh sách các buổi học sẽ tạo
                            if !previewRecurringSessions.isEmpty {
                                DisclosureGroup(isExpanded: $isPreviewExpanded) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(previewRecurringSessions.prefix(8)) { previewSession in
                                            HStack {
                                                Circle()
                                                    .fill(AppColors.accentRose)
                                                    .frame(width: 6, height: 6)
                                                Text(previewSession.startTime.formatted(date: .abbreviated, time: .omitted))
                                                    .font(AppTypography.caption1)
                                                    .foregroundColor(AppColors.primaryText)
                                                Spacer()
                                                Text("\(previewSession.startTime.formatted(date: .omitted, time: .shortened)) - \(previewSession.endTime.formatted(date: .omitted, time: .shortened))")
                                                    .font(AppTypography.caption2)
                                                    .foregroundColor(AppColors.secondaryText)
                                            }
                                        }
                                        if previewRecurringSessions.count > 8 {
                                            Text("... và thêm \(previewRecurringSessions.count - 8) buổi học khác.")
                                                .font(AppTypography.caption2)
                                                .foregroundColor(AppColors.secondaryText)
                                                .italic()
                                        }
                                    }
                                    .padding(.top, 4)
                                } label: {
                                    Text("Xem trước danh sách các buổi học")
                                        .font(AppTypography.caption1)
                                        .foregroundColor(AppColors.accentRose)
                                }
                            }
                        }
                    }
                }

                // MARK: - Danh sách Học sinh tham gia
                Section {
                    if isLoadingParticipants {
                        HStack {
                            Spacer()
                            ProgressView("Đang tải danh sách học sinh...")
                                .font(AppTypography.caption1)
                            Spacer()
                        }
                    } else if participants.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lớp chưa có học sinh ghi danh")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Bạn vẫn có thể lên lịch buổi dạy. Học sinh ghi danh sau sẽ được tự động đồng bộ.")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, 2)
                    } else {
                        ForEach(participants) { item in
                            HStack(spacing: AppSpacing.sm) {
                                // Avatar circle
                                ZStack {
                                    Circle()
                                        .fill(AppColors.secondaryPink)
                                        .frame(width: 32, height: 32)
                                    Text(initials(for: item.student.fullName))
                                        .font(AppTypography.font(size: 11))
                                        .foregroundColor(AppColors.accentRose)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.student.fullName)
                                        .font(AppTypography.body)
                                        .foregroundColor(AppColors.primaryText)

                                    if !item.student.phoneNumber.isEmpty {
                                        Text("SĐT: \(item.student.phoneNumber)")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.effectivePrice.formattedVND)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColors.accentRose)

                                    Text(item.isCustomPrice ? "Đơn giá riêng" : "Theo lớp")
                                        .font(AppTypography.font(size: 10))
                                        .foregroundColor(item.isCustomPrice ? AppColors.accentRose : AppColors.secondaryText)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    HStack {
                        Text("Học sinh tham gia")
                        if !participants.isEmpty {
                            Text("(\(participants.count))")
                                .foregroundColor(AppColors.accentRose)
                        }
                    }
                } footer: {
                    if !participants.isEmpty {
                        Text("Đơn giá tại thời điểm hoàn thành buổi học sẽ được snapshot làm căn cứ tính học phí bất biến.")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                // MARK: - Ghi chú & Bài tập
                Section("Ghi chú & Bài tập (Tùy chọn)") {
                    TextField("Nội dung bài học dự kiến", text: $lessonNotes)
                        .font(AppTypography.body)
                    TextField("Bài tập về nhà giao sau buổi", text: $homeworkAssigned)
                        .font(AppTypography.body)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTypography.caption1)
                            .foregroundColor(AppColors.error)
                    }
                }
            }
            .navigationTitle(initialSession == nil ? (isRecurring ? "Lịch dạy cố định" : "Lên lịch buổi dạy") : "Sửa buổi dạy")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAction()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Lưu")
                                .font(AppTypography.headline)
                                .foregroundColor(isValid ? AppColors.accentRose : AppColors.secondaryText)
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .confirmationDialog(
                "Cập nhật chuỗi lịch dạy",
                isPresented: $showSeriesDialog,
                titleVisibility: .visible
            ) {
                Button("Chỉ áp dụng buổi này") {
                    if var session = pendingSessionToSave {
                        session.setSeriesId(nil) // Tách buổi này ra làm ngoại lệ đơn lẻ
                        let participantIds = participants.map { $0.student.id }
                        if let onSaveSeriesOption {
                            onSaveSeriesOption(session, false, participantIds)
                        } else if let onSaveWithParticipants {
                            onSaveWithParticipants(session, participantIds)
                        } else if let onSaveLegacy {
                            onSaveLegacy(session)
                        }
                        dismiss()
                    }
                }

                Button("Buổi này cùng các buổi tương lai") {
                    if let session = pendingSessionToSave {
                        let participantIds = participants.map { $0.student.id }
                        if let onSaveSeriesOption {
                            onSaveSeriesOption(session, true, participantIds)
                        } else if let onSaveWithParticipants {
                            onSaveWithParticipants(session, participantIds)
                        } else if let onSaveLegacy {
                            onSaveLegacy(session)
                        }
                        dismiss()
                    }
                }

                Button("Hủy", role: .cancel) {
                    isSaving = false
                }
            } message: {
                Text("Buổi học này thuộc chuỗi lịch dạy cố định. Bạn muốn áp dụng thay đổi này như thế nào?")
            }
            .task {
                await loadParticipants(for: selectedClassId)
            }
        }
    }

    // MARK: - Subviews & Controls

    private var weekdayPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(DayOfWeek.allCases.sorted()) { day in
                let isSelected = selectedDays.contains(day)
                Button {
                    #if canImport(UIKit)
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                    #endif
                    if isSelected {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(day.shortName)
                        .font(AppTypography.caption1)
                        .fontWeight(isSelected ? .bold : .medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(isSelected ? AppColors.accentRose : AppColors.surfaceCard)
                        )
                        .foregroundColor(isSelected ? .white : AppColors.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .stroke(isSelected ? AppColors.accentRose : AppColors.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions & Helpers

    private func handleClassChange(newId: UUID) {
        if let selected = classes.first(where: { $0.id == newId }) {
            if title.isEmpty || title.hasPrefix("Buổi dạy") {
                title = "Buổi dạy: \(selected.name)"
            }
            endTime = startTime.addingTimeInterval(TimeInterval(selected.sessionDurationMinutes * 60))
        }
        Task {
            await loadParticipants(for: newId)
        }
    }

    private func loadParticipants(for classId: UUID) async {
        guard let classRepo = classRepository,
              let studentRepo = studentRepository,
              let targetClass = classes.first(where: { $0.id == classId }) else {
            return
        }

        isLoadingParticipants = true
        do {
            let enrollments = try await classRepo.fetchEnrollments(forClassId: classId, activeOnly: true)
            var items: [SessionParticipantItem] = []
            for e in enrollments {
                if let student = try await studentRepo.fetchStudent(byId: e.studentId), !student.isArchived {
                    let effPrice = priceUseCase.execute(student: student, classGroup: targetClass)
                    let isCustom = (student.defaultPricePerSession != nil && student.defaultPricePerSession! > 0)
                    items.append(SessionParticipantItem(student: student, effectivePrice: effPrice, isCustomPrice: isCustom))
                }
            }
            self.participants = items
        } catch {
            print("Failed to load participants: \(error)")
        }
        isLoadingParticipants = false
    }

    private func saveAction() {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedClass?.name ?? "Buổi học")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let participantIds = participants.map { $0.student.id }

        // TRƯỜNG HỢP 1: Tạo mới lịch lặp cố định theo các ngày trong tuần
        if initialSession == nil && isRecurring {
            let sessionsToSave = previewRecurringSessions
            if let onSaveBatch {
                onSaveBatch(sessionsToSave, participantIds)
                dismiss()
                return
            } else if let onSaveWithParticipants, let first = sessionsToSave.first {
                onSaveWithParticipants(first, participantIds)
                dismiss()
                return
            }
        }

        // TRƯỜNG HỢP 2: Chỉnh sửa buổi học thuộc chuỗi lặp cố định
        if let initial = initialSession, initial.seriesId != nil {
            var toSave = TeachingSessionEntity(
                id: initial.id,
                classId: selectedClassId,
                title: finalTitle,
                startTime: startTime,
                endTime: endTime,
                status: initial.status,
                lessonNotes: lessonNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                homeworkAssigned: homeworkAssigned.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: initial.createdAt,
                updatedAt: Date()
            )
            toSave.setSeriesId(initial.seriesId)
            self.pendingSessionToSave = toSave
            self.showSeriesDialog = true
            isSaving = false
            return
        }

        // TRƯỜNG HỢP 3: Lưu buổi học đơn lẻ thông thường
        var toSave = TeachingSessionEntity(
            id: initialSession?.id ?? UUID(),
            classId: selectedClassId,
            title: finalTitle,
            startTime: startTime,
            endTime: endTime,
            status: initialSession?.status ?? .scheduled,
            lessonNotes: lessonNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            homeworkAssigned: homeworkAssigned.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: initialSession?.createdAt ?? Date(),
            updatedAt: Date()
        )
        if let existingSeries = initialSession?.seriesId {
            toSave.setSeriesId(existingSeries)
        }

        if let onSaveWithParticipants {
            onSaveWithParticipants(toSave, participantIds)
        } else if let onSaveBatch {
            onSaveBatch([toSave], participantIds)
        } else if let onSaveLegacy {
            onSaveLegacy(toSave)
        }
        dismiss()
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        if let last = parts.last, let firstChar = last.first {
            return String(firstChar).uppercased()
        }
        return "S"
    }
}
