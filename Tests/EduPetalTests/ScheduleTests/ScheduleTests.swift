import Testing
import Foundation
import SwiftData
#if canImport(UserNotifications)
import UserNotifications
#endif
@testable import EduPetal

@Suite("Schedule & Teaching Sessions Test Suite")
struct ScheduleTests {

    @MainActor
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self,
            SessionAttachmentModel.self,
            ChargeModel.self,
            PaymentModel.self,
            PaymentAllocationModel.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Overlap Check Tests

    @Test("Phát hiện trùng lịch khi thời gian bắt đầu nằm trong khoảng buổi học khác")
    func testOverlapCheck_OverlappingStart() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Toán 12",
            startTime: now,
            endTime: now.addingTimeInterval(90 * 60) // 0 - 90
        )

        // Session 2: 60 - 120 (trùng 60 - 90)
        let overlap = useCase.execute(
            newStartTime: now.addingTimeInterval(60 * 60),
            newEndTime: now.addingTimeInterval(120 * 60),
            existingSessions: [session1]
        )

        #expect(overlap != nil)
        #expect(overlap?.id == session1.id)
    }

    @Test("Phát hiện trùng lịch khi thời gian kết thúc nằm trong khoảng buổi học khác")
    func testOverlapCheck_OverlappingEnd() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Lý 10",
            startTime: now.addingTimeInterval(60 * 60),
            endTime: now.addingTimeInterval(150 * 60) // 60 - 150
        )

        // Session 2: 0 - 90 (trùng 60 - 90)
        let overlap = useCase.execute(
            newStartTime: now,
            newEndTime: now.addingTimeInterval(90 * 60),
            existingSessions: [session1]
        )

        #expect(overlap != nil)
        #expect(overlap?.id == session1.id)
    }

    @Test("Phát hiện trùng lịch khi buổi học mới bao trọn hoàn toàn buổi học cũ")
    func testOverlapCheck_CompletelyEnclosed() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Hóa 11",
            startTime: now.addingTimeInterval(30 * 60),
            endTime: now.addingTimeInterval(60 * 60)
        )

        // Session 2: 0 - 120 (bao trọn 30 - 60)
        let overlap = useCase.execute(
            newStartTime: now,
            newEndTime: now.addingTimeInterval(120 * 60),
            existingSessions: [session1]
        )

        #expect(overlap != nil)
        #expect(overlap?.id == session1.id)
    }

    @Test("Không trùng lịch khi giờ kết thúc của buổi trước trùng khớp với giờ bắt đầu của buổi sau")
    func testOverlapCheck_AdjacentSessionsDoNotOverlap() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Toán 10",
            startTime: now,
            endTime: now.addingTimeInterval(60 * 60) // 0 - 60
        )

        // Session 2: 60 - 120 (nối tiếp ngay sau, không giao thoa)
        let overlap = useCase.execute(
            newStartTime: now.addingTimeInterval(60 * 60),
            newEndTime: now.addingTimeInterval(120 * 60),
            existingSessions: [session1]
        )

        #expect(overlap == nil)
    }

    @Test("Bỏ qua buổi học đã bị hủy (Cancelled), không báo trùng")
    func testOverlapCheck_IgnoresCancelledSession() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Văn 12 (Đã hủy)",
            startTime: now,
            endTime: now.addingTimeInterval(90 * 60),
            status: .cancelled
        )

        let overlap = useCase.execute(
            newStartTime: now.addingTimeInterval(30 * 60),
            newEndTime: now.addingTimeInterval(60 * 60),
            existingSessions: [session1]
        )

        #expect(overlap == nil)
    }

    @Test("Bỏ qua chính buổi học đang sửa (excludeSessionId) khi cập nhật thời gian")
    func testOverlapCheck_ExcludesSelfWhenEditing() {
        let useCase = CheckScheduleOverlapUseCase()
        let now = Date()
        let session1 = TeachingSessionEntity(
            classId: UUID(),
            title: "Anh 11",
            startTime: now,
            endTime: now.addingTimeInterval(90 * 60)
        )

        let overlap = useCase.execute(
            newStartTime: now,
            newEndTime: now.addingTimeInterval(90 * 60),
            existingSessions: [session1],
            excludeSessionId: session1.id
        )

        #expect(overlap == nil)
    }

    // MARK: - Teaching Session CRUD & Attendance Tests

    @Test("Thêm mới và truy xuất buổi học thành công")
    @MainActor
    func testSaveAndFetchTeachingSession() async throws {
        let container = try createTestContainer()
        let repository = ScheduleRepository(modelContainer: container)

        let now = Date()
        let session = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi 1: Hàm số",
            startTime: now,
            endTime: now.addingTimeInterval(90 * 60),
            lessonNotes: "Lý thuyết khảo sát hàm số",
            homeworkAssigned: "Bài tập 1 đến 5 SGK"
        )

        try await repository.saveSession(session)
        let fetched = try await repository.fetchSession(byId: session.id)

        #expect(fetched != nil)
        #expect(fetched?.title == "Buổi 1: Hàm số")
        #expect(fetched?.status == .scheduled)
        #expect(fetched?.durationMinutes == 90)
    }

    @Test("Lưu và cập nhật điểm danh học sinh chính xác")
    @MainActor
    func testAttendanceRecordingAndMarking() async throws {
        let container = try createTestContainer()
        let repository = ScheduleRepository(modelContainer: container)

        let session = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi 2",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )
        try await repository.saveSession(session)

        let studentId = UUID()
        let initialAttendance = AttendanceEntity(
            sessionId: session.id,
            studentId: studentId,
            status: .pending
        )
        try await repository.saveAttendance(initialAttendance)

        var records = try await repository.fetchAttendances(forSessionId: session.id)
        #expect(records.count == 1)
        #expect(records.first?.status == .pending)

        // Cập nhật sang có mặt
        let updatedAttendance = AttendanceEntity(
            id: initialAttendance.id,
            sessionId: session.id,
            studentId: studentId,
            status: .present,
            note: "Đi học đúng giờ"
        )
        try await repository.saveAttendance(updatedAttendance)

        records = try await repository.fetchAttendances(forSessionId: session.id)
        #expect(records.first?.status == .present)
        #expect(records.first?.note == "Đi học đúng giờ")
    }

    // MARK: - Complete Session Flow Invariant Tests

    @Test("Chặn hoàn thành buổi học nếu còn bất kỳ học sinh nào chưa được điểm danh (pending)")
    func testCompleteSession_FailsWhenUnmarkedStudentsExist() {
        let useCase = CompleteTeachingSessionUseCase()
        let sessionId = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Buổi 3",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )

        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: student1, status: .present),
            AttendanceEntity(sessionId: sessionId, studentId: student2, status: .pending) // Chưa điểm danh
        ]

        #expect(throws: CompleteSessionError.self) {
            try useCase.execute(
                session: session,
                attendances: attendances,
                expectedStudentIds: [student1, student2]
            )
        }
    }

    @Test("Chặn hoàn thành buổi học nếu danh sách học sinh bị thiếu bản ghi điểm danh")
    func testCompleteSession_FailsWhenMissingStudent() {
        let useCase = CompleteTeachingSessionUseCase()
        let sessionId = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Buổi 4",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )

        // Chỉ có student1, thiếu student2
        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: student1, status: .present)
        ]

        #expect(throws: CompleteSessionError.self) {
            try useCase.execute(
                session: session,
                attendances: attendances,
                expectedStudentIds: [student1, student2]
            )
        }
    }

    @Test("Chặn hoàn thành buổi học đã bị hủy")
    func testCompleteSession_FailsWhenCancelled() {
        let useCase = CompleteTeachingSessionUseCase()
        let sessionId = UUID()
        let student1 = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Buổi 5",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60),
            status: .cancelled
        )

        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: student1, status: .present)
        ]

        #expect(throws: CompleteSessionError.self) {
            try useCase.execute(
                session: session,
                attendances: attendances,
                expectedStudentIds: [student1]
            )
        }
    }

    @Test("Hoàn thành buổi học thành công khi 100% học sinh đã được xác nhận điểm danh")
    func testCompleteSession_SucceedsWhenAllMarked() throws {
        let useCase = CompleteTeachingSessionUseCase()
        let sessionId = UUID()
        let student1 = UUID()
        let student2 = UUID()
        let student3 = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Buổi 6",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )

        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: student1, status: .present),
            AttendanceEntity(sessionId: sessionId, studentId: student2, status: .absent),
            AttendanceEntity(sessionId: sessionId, studentId: student3, status: .excused)
        ]

        let completedSession = try useCase.execute(
            session: session,
            attendances: attendances,
            expectedStudentIds: [student1, student2, student3]
        )

        #expect(completedSession.status == .completed)
    }

    @Test("Khởi tạo danh sách điểm danh ban đầu chuẩn xác cho các thành viên mới")
    func testInitializeSessionAttendance() {
        let useCase = InitializeSessionAttendanceUseCase()
        let sessionId = UUID()
        let student1 = UUID()
        let student2 = UUID()

        // student1 đã có điểm danh từ trước
        let existing = [
            AttendanceEntity(sessionId: sessionId, studentId: student1, status: .present)
        ]

        let full = useCase.execute(
            sessionId: sessionId,
            activeStudentIds: [student1, student2],
            existingAttendances: existing
        )

        #expect(full.count == 2)
        let s1 = full.first { $0.studentId == student1 }
        let s2 = full.first { $0.studentId == student2 }

        #expect(s1?.status == .present)
        #expect(s2?.status == .pending)
    }

    // MARK: - ScheduleViewModel Save & Snapshot Integration Tests

    @Test("ScheduleViewModel.saveSession lưu buổi học, snapshot điểm danh pending và tự động chuyển selectedDate")
    @MainActor
    func testScheduleViewModel_SaveSession_SnapshotsAttendanceAndJumpsToDate() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContext: container.mainContext)
        let classRepo = ClassRepository(modelContext: container.mainContext)

        let vm = ScheduleViewModel(scheduleRepository: scheduleRepo, classRepository: classRepo)

        let targetDate = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        let sessionId = UUID()
        let student1Id = UUID()
        let student2Id = UUID()

        let newSession = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Luyện thi Chuyên Toán",
            startTime: targetDate,
            endTime: targetDate.addingTimeInterval(90 * 60)
        )

        try await vm.saveSession(newSession, participantStudentIds: [student1Id, student2Id])

        // 1. Kiểm tra selectedDate tự động nhảy đến ngày của buổi học
        #expect(Calendar.current.isDate(vm.selectedDate, inSameDayAs: targetDate))

        // 2. Buổi học xuất hiện ngay trong sessions của ViewModel
        #expect(vm.sessions.contains(where: { $0.id == sessionId }))

        // 3. Snapshot điểm danh ban đầu được khởi tạo với trạng thái .pending cho từng học sinh tham gia
        let attendances = try await scheduleRepo.fetchAttendances(forSessionId: sessionId)
        #expect(attendances.count == 2)
        #expect(attendances.allSatisfy { $0.status == .pending })
        #expect(Set(attendances.map { $0.studentId }) == Set([student1Id, student2Id]))
    }

    @Test("GetEffectiveStudentPriceUseCase ưu tiên học phí riêng của học sinh so với đơn giá chung của lớp")
    func testGetEffectiveStudentPrice_Precedence() {
        let useCase = GetEffectiveStudentPriceUseCase()
        let classGroup = ClassGroupEntity(
            id: UUID(),
            name: "Lớp Toán Nâng Cao",
            subject: "Toán",
            defaultPricePerSession: 200_000,
            colorHex: "#FF69B4"
        )

        // Trường hợp 1: Học sinh có custom fee riêng
        let studentWithCustomPrice = StudentEntity(
            fullName: "Nguyễn Văn A",
            phoneNumber: "0901234567",
            defaultPricePerSession: 150_000
        )
        let price1 = useCase.execute(student: studentWithCustomPrice, classGroup: classGroup)
        #expect(price1 == 150_000)

        // Trường hợp 2: Học sinh không có custom fee -> dùng đơn giá chung của lớp
        let studentStandard = StudentEntity(
            fullName: "Trần Thị B",
            phoneNumber: "0907654321",
            defaultPricePerSession: nil
        )
        let price2 = useCase.execute(student: studentStandard, classGroup: classGroup)
        #expect(price2 == 200_000)
    }

    // MARK: - Attendance & Completion Workflow Tests

    @Test("Chặn mở tổng kết hoàn thành khi còn học sinh chưa được đánh dấu điểm danh (pending)")
    @MainActor
    func testSessionDetailViewModel_Validation_BlocksWhenUnmarked() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Nguyễn Văn Đang Chờ")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp 10A")
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi 1",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo
        )
        await vm.loadData()

        // Trạng thái ban đầu: điểm danh là pending
        #expect(vm.attendances.first?.status == .pending)
        let isValid = vm.validateBeforeCompletion()
        #expect(!isValid)
        #expect(vm.validationAlertMessage != nil)
    }

    @Test("Yêu cầu chụp ít nhất 1 ảnh minh chứng khi có học sinh tham gia buổi dạy")
    @MainActor
    func testSessionDetailViewModel_Validation_RequiresPhotoWhenPresent() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Trần Có Mặt")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp 11B")
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi 2",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo
        )
        await vm.loadData()

        // Điểm danh có mặt
        await vm.markAttendance(studentId: student.id, status: .present)
        #expect(vm.presentCount == 1)
        #expect(vm.attachments.isEmpty)

        // Không cho phép hoàn thành nếu chưa có ảnh
        let isValid = vm.validateBeforeCompletion()
        #expect(!isValid)
        #expect(vm.isPhotoRequiredAlertShowing == true)

        // Sau khi đính kèm ảnh minh chứng
        try await vm.addPhotoAttachment(filePath: "proof.jpg", caption: "Ảnh lớp học")
        #expect(vm.attachments.count == 1)

        let isValidAfterPhoto = vm.validateBeforeCompletion()
        #expect(isValidAfterPhoto == true)
    }

    @Test("Cho phép hoàn thành không cần ảnh minh chứng khi tất cả học sinh nghỉ (tổng tiền 0 VND)")
    @MainActor
    func testSessionDetailViewModel_Validation_AllowsNoPhotoWhenAllAbsent() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Lê Vắng Mặt")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp 12C")
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi 3",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo
        )
        await vm.loadData()

        // Điểm danh vắng
        await vm.markAttendance(studentId: student.id, status: .absent)
        #expect(vm.presentCount == 0)
        #expect(vm.absentCount == 1)
        #expect(vm.totalAccruedTuition == 0)

        // Khi tất cả vắng: hợp lệ ngay cả khi không có ảnh
        let isValid = vm.validateBeforeCompletion()
        #expect(isValid == true)
    }

    @Test("Hoàn thành buổi học tự động sinh khoản học phí chuẩn xác và chống tạo trùng idempotent")
    @MainActor
    func testSessionDetailViewModel_FinalizeCompletion_GeneratesChargesIdempotently() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        // 2 học sinh: 1 có mặt, 1 vắng
        let student1 = StudentEntity(fullName: "Học sinh Có Mặt", defaultPricePerSession: 220_000)
        let student2 = StudentEntity(fullName: "Học sinh Vắng", defaultPricePerSession: 180_000)
        try await studentRepo.saveStudent(student1)
        try await studentRepo.saveStudent(student2)

        let classGroup = ClassGroupEntity(name: "Lớp Toán Nhóm", defaultPricePerSession: 200_000)
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student1.id, classId: classGroup.id)
        try await classRepo.enrollStudent(studentId: student2.id, classId: classGroup.id)

        let sessionId = UUID()
        let session = TeachingSessionEntity(
            id: sessionId,
            classId: classGroup.id,
            title: "Buổi Đại Số",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60)
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo,
            financeRepository: financeRepo
        )
        await vm.loadData()

        await vm.markAttendance(studentId: student1.id, status: .present)
        await vm.markAttendance(studentId: student2.id, status: .absent)
        try await vm.addPhotoAttachment(filePath: "proof.jpg")

        // Thực hiện hoàn thành buổi học
        await vm.confirmAndFinalizeCompletion()

        // 1. Trạng thái buổi học chuyển sang .completed
        #expect(vm.session.status == .completed)
        #expect(vm.isCompletedSuccess == true)

        // 2. Chỉ có 1 khoản học phí duy nhất được sinh cho học sinh Có Mặt
        let charges = try await financeRepo.fetchChargesForSession(sessionId: sessionId)
        #expect(charges.count == 1)
        #expect(charges.first?.studentId == student1.id)
        #expect(charges.first?.amount == 220_000)
        #expect(charges.first?.unitPriceSnapshot == 220_000)

        // 3. Học sinh vắng không phát sinh học phí
        #expect(!charges.contains(where: { $0.studentId == student2.id }))

        // 4. Chống tạo trùng (Idempotency): Gọi lại hàm không bao giờ nhân đôi học phí
        await vm.confirmAndFinalizeCompletion()
        let chargesAfterRetry = try await financeRepo.fetchChargesForSession(sessionId: sessionId)
        #expect(chargesAfterRetry.count == 1)
    }

    // MARK: - Recurring Series & Exceptions Tests (Feature 8)

    @Test("Entity hỗ trợ mã chuỗi lặp [SERIES] và giữ nguyên nội dung ghi chú người dùng")
    func testTeachingSessionEntity_SeriesMetadataSupport() {
        var session = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi Toán",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60),
            lessonNotes: "Ôn tập phương trình mũ"
        )

        #expect(session.seriesId == nil)
        #expect(session.userDisplayNotes == "Ôn tập phương trình mũ")
        #expect(session.isRecurring == false)

        let seriesId = UUID()
        session.setSeriesId(seriesId)

        #expect(session.seriesId == seriesId)
        #expect(session.userDisplayNotes == "Ôn tập phương trình mũ")
        #expect(session.isRecurring == true)

        // Tách chuỗi (ngoại lệ đơn lẻ)
        session.setSeriesId(nil)
        #expect(session.seriesId == nil)
        #expect(session.userDisplayNotes == "Ôn tập phương trình mũ")
        #expect(session.isRecurring == false)
    }

    @Test("GenerateRecurringSessionsUseCase sinh đúng số lượng buổi theo ngày trong tuần và khoảng thời gian")
    func testGenerateRecurringSessionsUseCase_GeneratesCorrectDates() {
        let useCase = GenerateRecurringSessionsUseCase()
        let calendar = Calendar.current

        // Giả lập template session vào lúc 18:00
        var templateComp = DateComponents()
        templateComp.year = 2026
        templateComp.month = 11
        templateComp.day = 2 // Thứ Hai (T2)
        templateComp.hour = 18
        templateComp.minute = 0
        let templateStart = calendar.date(from: templateComp)!
        let templateEnd = templateStart.addingTimeInterval(90 * 60)

        let template = TeachingSessionEntity(
            classId: UUID(),
            title: "Toán Nâng Cao",
            startTime: templateStart,
            endTime: templateEnd,
            lessonNotes: "Lý thuyết & Bài tập"
        )

        // Lặp vào Thứ 2 (monday=2) và Thứ 4 (wednesday=4) trong vòng 2 tuần (từ 02/11/2026 đến 15/11/2026)
        let startDate = templateStart
        let endDate = calendar.date(byAdding: .day, value: 13, to: startDate)! // 2 tuần

        let generated = useCase.execute(
            templateSession: template,
            selectedDays: [.monday, .wednesday],
            startDate: startDate,
            endDate: endDate
        )

        // 2 tuần * 2 buổi/tuần = 4 buổi
        #expect(generated.count == 4)
        for s in generated {
            let weekday = calendar.component(.weekday, from: s.startTime)
            #expect(weekday == DayOfWeek.monday.rawValue || weekday == DayOfWeek.wednesday.rawValue)
            let hour = calendar.component(.hour, from: s.startTime)
            let minute = calendar.component(.minute, from: s.startTime)
            #expect(hour == 18)
            #expect(minute == 0)
            #expect(s.durationMinutes == 90)
            #expect(s.seriesId != nil)
            #expect(s.userDisplayNotes == "Lý thuyết & Bài tập")
        }
    }

    @Test("GenerateRecurringSessionsUseCase không tạo trùng lặp khi chạy lại nhiều lần")
    func testGenerateRecurringSessionsUseCase_PreventsDuplicates() {
        let useCase = GenerateRecurringSessionsUseCase()
        let calendar = Calendar.current

        let templateStart = Date()
        let template = TeachingSessionEntity(
            classId: UUID(),
            title: "Tiếng Anh Giao Tiếp",
            startTime: templateStart,
            endTime: templateStart.addingTimeInterval(60 * 60)
        )

        let endDate = calendar.date(byAdding: .day, value: 14, to: templateStart)!

        // Lần 1: Sinh danh sách
        let batch1 = useCase.execute(
            templateSession: template,
            selectedDays: [.tuesday, .thursday],
            startDate: templateStart,
            endDate: endDate
        )
        #expect(!batch1.isEmpty)

        // Lần 2: Chạy lại với existingSessions = batch1 -> Không được sinh thêm buổi nào bị trùng
        let batch2 = useCase.execute(
            templateSession: template,
            selectedDays: [.tuesday, .thursday],
            startDate: templateStart,
            endDate: endDate,
            existingSessions: batch1
        )
        #expect(batch2.isEmpty)
    }

    @Test("ScheduleViewModel lưu hàng loạt buổi lặp và tự động snapshot điểm danh pending")
    @MainActor
    func testScheduleViewModel_SaveRecurringSessions_CreatesPendingAttendances() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)

        let student1 = StudentEntity(fullName: "Nguyễn Văn A")
        let student2 = StudentEntity(fullName: "Trần Thị B")
        try await studentRepo.saveStudent(student1)
        try await studentRepo.saveStudent(student2)

        let classGroup = ClassGroupEntity(name: "Lớp 11A1")
        try await classRepo.saveClass(classGroup)

        let now = Date()
        let seriesId = UUID()
        var session1 = TeachingSessionEntity(
            id: UUID(),
            classId: classGroup.id,
            title: "Buổi 1",
            startTime: now,
            endTime: now.addingTimeInterval(90 * 60)
        )
        session1.setSeriesId(seriesId)

        var session2 = TeachingSessionEntity(
            id: UUID(),
            classId: classGroup.id,
            title: "Buổi 2",
            startTime: now.addingTimeInterval(24 * 3600),
            endTime: now.addingTimeInterval(24 * 3600 + 90 * 60)
        )
        session2.setSeriesId(seriesId)

        let vm = ScheduleViewModel(scheduleRepository: scheduleRepo, classRepository: classRepo)
        try await vm.saveRecurringSessions([session1, session2], participantStudentIds: [student1.id, student2.id])

        // Kiểm tra cả 2 buổi đều có danh sách điểm danh ban đầu
        let att1 = try await scheduleRepo.fetchAttendances(forSessionId: session1.id)
        let att2 = try await scheduleRepo.fetchAttendances(forSessionId: session2.id)

        #expect(att1.count == 2)
        #expect(att2.count == 2)
        #expect(att1.allSatisfy { $0.status == .pending })
        #expect(att2.allSatisfy { $0.status == .pending })
    }

    @Test("Cập nhật chuỗi tương lai (Buổi này cùng các buổi tương lai) không làm sai các buổi đã hoàn thành")
    @MainActor
    func testScheduleViewModel_UpdateSeriesFutureSessions_PreservesCompletedSessions() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let classGroup = ClassGroupEntity(name: "Lớp Vật Lý")
        try await classRepo.saveClass(classGroup)

        let calendar = Calendar.current
        let seriesId = UUID()
        let now = Date()

        // 1. Buổi quá khứ ĐÃ HOÀN THÀNH
        let pastDate = calendar.date(byAdding: .day, value: -7, to: now)!
        var pastSession = TeachingSessionEntity(
            id: UUID(),
            classId: classGroup.id,
            title: "Vật Lý Cũ",
            startTime: pastDate,
            endTime: pastDate.addingTimeInterval(60 * 60),
            status: .completed,
            lessonNotes: "Nội dung cũ đã dạy xong"
        )
        pastSession.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(pastSession)

        // 2. Buổi hiện tại ĐANG LÊN LỊCH
        var currentSession = TeachingSessionEntity(
            id: UUID(),
            classId: classGroup.id,
            title: "Vật Lý Tuần Này",
            startTime: now,
            endTime: now.addingTimeInterval(60 * 60),
            status: .scheduled
        )
        currentSession.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(currentSession)

        // 3. Buổi tương lai ĐANG LÊN LỊCH
        let futureDate = calendar.date(byAdding: .day, value: 7, to: now)!
        var futureSession = TeachingSessionEntity(
            id: UUID(),
            classId: classGroup.id,
            title: "Vật Lý Tuần Này",
            startTime: futureDate,
            endTime: futureDate.addingTimeInterval(60 * 60),
            status: .scheduled
        )
        futureSession.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(futureSession)

        // Giáo viên đổi giờ và tiêu đề từ buổi hiện tại:
        // Đổi tiêu đề thành "Vật Lý Nâng Cao 12", thời lượng tăng lên 90 phút
        let vm = ScheduleViewModel(scheduleRepository: scheduleRepo, classRepository: classRepo)

        var updatedCurrent = currentSession
        updatedCurrent.title = "Vật Lý Nâng Cao 12"
        updatedCurrent.endTime = currentSession.startTime.addingTimeInterval(90 * 60)
        updatedCurrent.lessonNotes = "Nội dung nâng cao mới"
        updatedCurrent.setSeriesId(seriesId)

        try await vm.updateSeriesFutureSessions(from: updatedCurrent, originalStartTime: currentSession.startTime)

        // 1. Buổi quá khứ hoàn thành KHÔNG BỊ THAY ĐỔI
        let reloadedPast = try await scheduleRepo.fetchSession(byId: pastSession.id)
        #expect(reloadedPast?.title == "Vật Lý Cũ")
        #expect(reloadedPast?.status == .completed)
        #expect(reloadedPast?.durationMinutes == 60)
        #expect(reloadedPast?.userDisplayNotes == "Nội dung cũ đã dạy xong")

        // 2. Buổi hiện tại được cập nhật
        let reloadedCurrent = try await scheduleRepo.fetchSession(byId: currentSession.id)
        #expect(reloadedCurrent?.title == "Vật Lý Nâng Cao 12")
        #expect(reloadedCurrent?.durationMinutes == 90)

        // 3. Buổi tương lai được tự động đồng bộ theo tiêu đề và thời lượng mới
        let reloadedFuture = try await scheduleRepo.fetchSession(byId: futureSession.id)
        #expect(reloadedFuture?.title == "Vật Lý Nâng Cao 12")
        #expect(reloadedFuture?.durationMinutes == 90)
    }

    @Test("Tách buổi học ra khỏi chuỗi (Chỉ buổi này) biến buổi học thành ngoại lệ độc lập")
    @MainActor
    func testScheduleViewModel_DetachSessionFromSeries() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let seriesId = UUID()
        var session = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi Học Thường Nhật",
            startTime: Date(),
            endTime: Date().addingTimeInterval(60 * 60),
            lessonNotes: "Ghi chú buổi học"
        )
        session.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(session)
        #expect(session.seriesId == seriesId)

        let vm = ScheduleViewModel(scheduleRepository: scheduleRepo, classRepository: classRepo)
        try await vm.detachSessionFromSeries(session)

        let reloaded = try await scheduleRepo.fetchSession(byId: session.id)
        #expect(reloaded?.seriesId == nil)
        #expect(reloaded?.isRecurring == false)
        #expect(reloaded?.userDisplayNotes == "Ghi chú buổi học")
    }

    @Test("Khi hủy một buổi học trong chuỗi lặp không làm mất hoặc hủy các buổi khác trong chuỗi")
    @MainActor
    func testScheduleViewModel_CancelSession_PreservesOtherSessionsInSeries() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let seriesId = UUID()
        let classId = UUID()
        let now = Date()

        var session1 = TeachingSessionEntity(
            classId: classId,
            title: "Buổi 1",
            startTime: now,
            endTime: now.addingTimeInterval(60 * 60)
        )
        session1.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(session1)

        var session2 = TeachingSessionEntity(
            classId: classId,
            title: "Buổi 2",
            startTime: now.addingTimeInterval(7 * 24 * 3600),
            endTime: now.addingTimeInterval(7 * 24 * 3600 + 60 * 60)
        )
        session2.setSeriesId(seriesId)
        try await scheduleRepo.saveSession(session2)

        let vm = ScheduleViewModel(scheduleRepository: scheduleRepo, classRepository: classRepo)
        // Hủy riêng buổi 1
        await vm.cancelSession(id: session1.id)

        let reloaded1 = try await scheduleRepo.fetchSession(byId: session1.id)
        let reloaded2 = try await scheduleRepo.fetchSession(byId: session2.id)

        // Buổi 1 đã bị hủy
        #expect(reloaded1?.status == .cancelled)

        // Buổi 2 vẫn ở trạng thái .scheduled, giữ nguyên seriesId
        #expect(reloaded2?.status == .scheduled)
        #expect(reloaded2?.seriesId == seriesId)
    }

    // MARK: - Local Notification Tests (Feature 9)

    @Test("ScheduleViewModel.saveSession tự động lập lịch nhắc trước 60 phút cho buổi dạy tương lai")
    @MainActor
    func testScheduleViewModel_SaveSession_SchedulesNotificationReminder() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let classGroup = ClassGroupEntity(name: "Lớp Tiếng Anh")
        try await classRepo.saveClass(classGroup)

        let futureStart = Date().addingTimeInterval(3 * 3600) // Sau 3 tiếng
        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Tiếng Anh Giao Tiếp",
            startTime: futureStart,
            endTime: futureStart.addingTimeInterval(90 * 60),
            status: .scheduled
        )

        let vm = ScheduleViewModel(
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            notificationService: mockNotification
        )

        try await vm.saveSession(session)

        #expect(mockNotification.scheduledSessions.contains(where: { $0.id == session.id }))
    }

    @Test("ScheduleViewModel.cancelSession tự động hủy thông báo nhắc nhở của buổi học")
    @MainActor
    func testScheduleViewModel_CancelSession_CancelsNotificationReminder() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let futureStart = Date().addingTimeInterval(4 * 3600)
        let session = TeachingSessionEntity(
            classId: UUID(),
            title: "Toán 11",
            startTime: futureStart,
            endTime: futureStart.addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)
        await mockNotification.scheduleSessionReminder(for: session)
        #expect(mockNotification.scheduledSessions.contains(where: { $0.id == session.id }))

        let vm = ScheduleViewModel(
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            notificationService: mockNotification
        )

        await vm.cancelSession(id: session.id)

        #expect(mockNotification.cancelledSessionIds.contains(session.id))
        #expect(!mockNotification.scheduledSessions.contains(where: { $0.id == session.id }))
    }

    @Test("ScheduleViewModel.deleteSession tự động hủy thông báo nhắc nhở của buổi học bị xóa")
    @MainActor
    func testScheduleViewModel_DeleteSession_CancelsNotificationReminder() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let session = TeachingSessionEntity(
            classId: UUID(),
            title: "Văn 12",
            startTime: Date().addingTimeInterval(5 * 3600),
            endTime: Date().addingTimeInterval(6 * 3600),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)
        await mockNotification.scheduleSessionReminder(for: session)

        let vm = ScheduleViewModel(
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            notificationService: mockNotification
        )

        await vm.deleteSession(id: session.id)

        #expect(mockNotification.cancelledSessionIds.contains(session.id))
    }

    @Test("SessionDetailViewModel.confirmAndFinalizeCompletion hủy nhắc nhở khi buổi học hoàn thành")
    @MainActor
    func testSessionDetailViewModel_CompleteSession_CancelsNotificationReminder() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let student = StudentEntity(fullName: "Học sinh A")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp Lý")
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Lý",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)
        await mockNotification.scheduleSessionReminder(for: session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo,
            financeRepository: financeRepo,
            notificationService: mockNotification
        )
        await vm.loadData()
        await vm.markAttendance(studentId: student.id, status: .present)
        try await vm.addPhotoAttachment(filePath: "proof.jpg")

        await vm.confirmAndFinalizeCompletion()

        #expect(mockNotification.cancelledSessionIds.contains(session.id))
    }

    @Test("LocalNotificationService không lập lịch cho buổi học có thời điểm nhắc trong quá khứ")
    func testLocalNotificationService_PastSessionReminderNotScheduled() async {
        let mockNotification = MockNotificationService()

        // Buổi học bắt đầu sau 30 phút -> Nhắc trước 60 phút sẽ nằm trong quá khứ (-30 phút trước)
        let soonStart = Date().addingTimeInterval(30 * 60)
        let session = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi Học Gấp",
            startTime: soonStart,
            endTime: soonStart.addingTimeInterval(60 * 60),
            status: .scheduled
        )

        await mockNotification.scheduleSessionReminder(for: session)

        #expect(mockNotification.scheduledSessions.isEmpty)
    }

    @Test("Khi tắt nhắc nhở trong Cài đặt (isSessionReminderEnabled = false) sẽ hủy toàn bộ thông báo")
    func testLocalNotificationService_DisabledRemindersCancelsAll() async {
        let mockNotification = MockNotificationService()
        mockNotification.isSessionReminderEnabled = true

        let futureSession = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi Tương Lai",
            startTime: Date().addingTimeInterval(4 * 3600),
            endTime: Date().addingTimeInterval(5 * 3600),
            status: .scheduled
        )
        await mockNotification.scheduleSessionReminder(for: futureSession)
        #expect(!mockNotification.scheduledSessions.isEmpty)

        // Tắt cài đặt
        mockNotification.isSessionReminderEnabled = false
        await mockNotification.syncSessionReminders(for: [futureSession])

        #expect(mockNotification.scheduledSessions.isEmpty)
    }

    // MARK: - Daily Reminder & Deep Link Tests (Feature 10)

    @Test("Nhắc xem lịch hằng ngày mặc định bật lúc 22:00 và thay thế lịch cũ khi đổi giờ")
    func testLocalNotificationService_DailyReminderScheduleAndReschedule() async {
        let mockNotification = MockNotificationService()
        mockNotification.isDailyReminderEnabled = true
        mockNotification.dailyReminderHour = 22
        mockNotification.dailyReminderMinute = 0

        await mockNotification.syncDailyReminder()

        #expect(mockNotification.scheduledDailyReminderTime?.hour == 22)
        #expect(mockNotification.scheduledDailyReminderTime?.minute == 0)

        // Đổi giờ sang 21:30 -> Thay thế lịch cũ, không tạo thêm bản sao
        mockNotification.dailyReminderHour = 21
        mockNotification.dailyReminderMinute = 30
        await mockNotification.syncDailyReminder()

        #expect(mockNotification.scheduledDailyReminderTime?.hour == 21)
        #expect(mockNotification.scheduledDailyReminderTime?.minute == 30)
    }

    @Test("Tắt lời nhắc hằng ngày không làm ảnh hưởng đến lời nhắc trước buổi dạy")
    func testLocalNotificationService_ToggleDailyReminderDoesNotAffectSessionReminder() async {
        let mockNotification = MockNotificationService()
        mockNotification.isSessionReminderEnabled = true
        mockNotification.isDailyReminderEnabled = true

        let futureSession = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi Dạy Chiều",
            startTime: Date().addingTimeInterval(3 * 3600),
            endTime: Date().addingTimeInterval(4 * 3600),
            status: .scheduled
        )
        await mockNotification.scheduleSessionReminder(for: futureSession)
        await mockNotification.scheduleDailyReminder(hour: 22, minute: 0)

        #expect(!mockNotification.scheduledSessions.isEmpty)
        #expect(mockNotification.scheduledDailyReminderTime != nil)

        // Tắt lời nhắc hằng ngày
        mockNotification.isDailyReminderEnabled = false
        await mockNotification.cancelDailyReminder()

        // Lời nhắc hằng ngày bị hủy nhưng lời nhắc buổi dạy vẫn được giữ nguyên
        #expect(mockNotification.scheduledDailyReminderTime == nil)
        #expect(mockNotification.isDailyReminderCancelled == true)
        #expect(!mockNotification.scheduledSessions.isEmpty)
        #expect(mockNotification.scheduledSessions.contains(where: { $0.id == futureSession.id }))
    }

    @Test("Deep link từ thông báo điều hướng chính xác đến Lịch dạy của ngày mai")
    @MainActor
    func testAppNavigationState_NavigateToScheduleTomorrow() {
        let navState = AppNavigationState.shared
        navState.selectedTabRaw = 0 // Đang ở Home

        navState.navigateToScheduleTomorrow()

        let calendar = Calendar.current
        let expectedTomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!

        #expect(navState.selectedTabRaw == 2) // Tab Lịch dạy
        #expect(navState.targetScheduleDate != nil)
        #expect(calendar.isDate(navState.targetScheduleDate!, inSameDayAs: expectedTomorrow))
    }

    @Test("AppHost Info.plist chứa đầy đủ NSCameraUsageDescription và TeachingProofCameraService vận hành an toàn")
    @MainActor
    func testCameraPrivacyDescriptionAndServiceLifecycle() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = projectRoot.appendingPathComponent("AppHost/Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]

        let cameraDesc = plist?["NSCameraUsageDescription"] as? String
        let photoDesc = plist?["NSPhotoLibraryUsageDescription"] as? String
        let photoAddDesc = plist?["NSPhotoLibraryAddUsageDescription"] as? String

        #expect(cameraDesc != nil)
        #expect(cameraDesc?.isEmpty == false)
        #expect(photoDesc?.isEmpty == false)
        #expect(photoAddDesc?.isEmpty == false)

        let service = TeachingProofCameraService()
        #expect(service.isCapturingPhoto == false)
        service.setZoomFactor(1.0)
        #expect(service.currentZoomFactor == 1.0)
        service.stopSession()
        #expect(service.isSessionRunning == false)
    }

    // MARK: - Feature 3: Thêm Học sinh vào Lớp -> Thiết lập Lịch tháng Tests

    @Test("Trường hợp 1: Lớp đã có lịch học — chỉ thêm học sinh vào các buổi scheduled từ ngày bắt đầu tham gia, không thêm vào buổi đã hoàn thành hoặc trước ngày tham gia, không tạo bản sao và chưa phát sinh học phí")
    @MainActor
    func testEnrollStudentInClassWithExistingSchedule_OnlyAddsFutureScheduledSessionsAndNoDuplicateOrCharge() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Nguyễn Minh Anh")
        try await studentRepo.saveStudent(student)

        let classGroup = ClassGroupEntity(
            name: "Toán 10 Nâng Cao",
            subject: "Toán",
            defaultPricePerSession: 200_000,
            sessionDurationMinutes: 90
        )
        try await classRepo.saveClass(classGroup)

        let cal = Calendar.current
        let baseDate = cal.startOfDay(for: Date())
        let enrolledAt = cal.date(byAdding: .day, value: 5, to: baseDate)!

        // 1. Buổi đã hoàn thành (sau ngày tham gia nhưng trạng thái completed -> phải bỏ qua)
        let completedSession = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Đã Hoàn Thành",
            startTime: cal.date(byAdding: .day, value: 6, to: baseDate)!.addingTimeInterval(18 * 3600),
            endTime: cal.date(byAdding: .day, value: 6, to: baseDate)!.addingTimeInterval(19.5 * 3600),
            status: .completed
        )
        // 2. Buổi chưa diễn ra nhưng TRƯỚC ngày bắt đầu tham gia -> phải bỏ qua
        let earlierScheduledSession = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Trước Ngày Tham Gia",
            startTime: cal.date(byAdding: .day, value: 2, to: baseDate)!.addingTimeInterval(18 * 3600),
            endTime: cal.date(byAdding: .day, value: 2, to: baseDate)!.addingTimeInterval(19.5 * 3600),
            status: .scheduled
        )
        // 3. Hai buổi scheduled TỪ ngày bắt đầu tham gia trở đi -> được tự động thêm điểm danh pending
        let futureSession1 = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Hợp Lệ 1",
            startTime: cal.date(byAdding: .day, value: 5, to: baseDate)!.addingTimeInterval(18 * 3600),
            endTime: cal.date(byAdding: .day, value: 5, to: baseDate)!.addingTimeInterval(19.5 * 3600),
            status: .scheduled
        )
        let futureSession2 = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Hợp Lệ 2",
            startTime: cal.date(byAdding: .day, value: 8, to: baseDate)!.addingTimeInterval(18 * 3600),
            endTime: cal.date(byAdding: .day, value: 8, to: baseDate)!.addingTimeInterval(19.5 * 3600),
            status: .scheduled
        )

        try await scheduleRepo.saveSession(completedSession)
        try await scheduleRepo.saveSession(earlierScheduledSession)
        try await scheduleRepo.saveSession(futureSession1)
        try await scheduleRepo.saveSession(futureSession2)

        let detailVM = StudentDetailViewModel(
            student: student,
            studentRepository: studentRepo,
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadEnrolledClasses()

        // Thực hiện Thêm vào lớp với đơn giá riêng 250.000đ
        try await detailVM.enrollStudentInClass(
            classId: classGroup.id,
            enrolledAt: enrolledAt,
            useCustomPrice: true,
            customPrice: 250_000,
            newMonthlySessionsToCreate: []
        )

        // Không sinh bản sao buổi học
        let allSessions = try await scheduleRepo.fetchSessionsForClass(classId: classGroup.id)
        #expect(allSessions.count == 4)

        // Kiểm tra điểm danh từng buổi
        let attCompleted = try await scheduleRepo.fetchAttendances(forSessionId: completedSession.id)
        let attEarlier = try await scheduleRepo.fetchAttendances(forSessionId: earlierScheduledSession.id)
        let attFuture1 = try await scheduleRepo.fetchAttendances(forSessionId: futureSession1.id)
        let attFuture2 = try await scheduleRepo.fetchAttendances(forSessionId: futureSession2.id)

        #expect(attCompleted.isEmpty)
        #expect(attEarlier.isEmpty)
        #expect(attFuture1.count == 1)
        #expect(attFuture1.first?.studentId == student.id)
        #expect(attFuture1.first?.status == .pending)
        #expect(attFuture2.count == 1)
        #expect(attFuture2.first?.studentId == student.id)

        // Chưa phát sinh bất kỳ khoản học phí nào
        let charges = try await financeRepo.fetchChargesForStudent(studentId: student.id)
        #expect(charges.isEmpty)
        #expect(detailVM.student.defaultPricePerSession == 250_000)
    }

    @Test("Trường hợp 2: Lớp chưa có lịch học — thiết lập lịch học theo tháng / nhiều tháng, khởi tạo điểm danh pending, chống tạo trùng và chưa phát sinh học phí")
    @MainActor
    func testEnrollStudentInClassWithMonthlySchedule_CreatesSessionsAcrossMonthsAndIdempotent() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Trần Quốc Bảo")
        try await studentRepo.saveStudent(student)

        let classGroup = ClassGroupEntity(
            name: "Vật Lý 11",
            subject: "Vật Lý",
            defaultPricePerSession: 180_000,
            sessionDurationMinutes: 90
        )
        try await classRepo.saveClass(classGroup)

        let cal = Calendar.current
        let enrolledAt = cal.startOfDay(for: Date())
        let endDate = cal.date(byAdding: .day, value: 21, to: enrolledAt)!

        var startComp = cal.dateComponents([.year, .month, .day], from: enrolledAt)
        startComp.hour = 18
        startComp.minute = 0
        let tStart = cal.date(from: startComp)!
        let tEnd = tStart.addingTimeInterval(90 * 60)

        let template = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi học: \(classGroup.name)",
            startTime: tStart,
            endTime: tEnd,
            status: .scheduled
        )

        let generator = GenerateRecurringSessionsUseCase()
        let generatedSessions = generator.execute(
            templateSession: template,
            selectedDays: [.monday, .wednesday, .friday],
            startDate: enrolledAt,
            endDate: endDate,
            existingSessions: []
        )
        #expect(!generatedSessions.isEmpty)

        let detailVM = StudentDetailViewModel(
            student: student,
            studentRepository: studentRepo,
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadEnrolledClasses()

        // Lần 1: Thêm vào lớp & lưu lịch tháng
        try await detailVM.enrollStudentInClass(
            classId: classGroup.id,
            enrolledAt: enrolledAt,
            useCustomPrice: false,
            customPrice: nil as Int64?,
            newMonthlySessionsToCreate: generatedSessions
        )

        let savedSessions1 = try await scheduleRepo.fetchSessionsForClass(classId: classGroup.id)
        #expect(savedSessions1.count == generatedSessions.count)

        for s in savedSessions1 {
            let atts = try await scheduleRepo.fetchAttendances(forSessionId: s.id)
            #expect(atts.count == 1)
            #expect(atts.first?.studentId == student.id)
            #expect(atts.first?.status == .pending)
        }

        // Lần 2: Gọi lại với các buổi có ID mới nhưng cùng classId + startTime -> không được tạo trùng
        let duplicateCandidates = generatedSessions.map { s in
            TeachingSessionEntity(
                id: UUID(),
                classId: s.classId,
                title: s.title,
                startTime: s.startTime,
                endTime: s.endTime,
                status: .scheduled
            )
        }
        try await detailVM.enrollStudentInClass(
            classId: classGroup.id,
            enrolledAt: enrolledAt,
            useCustomPrice: false,
            customPrice: nil as Int64?,
            newMonthlySessionsToCreate: duplicateCandidates
        )

        let savedSessions2 = try await scheduleRepo.fetchSessionsForClass(classId: classGroup.id)
        #expect(savedSessions2.count == generatedSessions.count)

        // Chưa phát sinh học phí
        let charges = try await financeRepo.fetchChargesForStudent(studentId: student.id)
        #expect(charges.isEmpty)
    }

    // MARK: - Feature 4: Hoàn thành buổi học, phát sinh học phí idempotent và điều chỉnh sau hoàn thành

    @Test("FinanceRepository.saveCharges đảm bảo idempotent theo cặp (sessionId, studentId) ngay cả khi khác ChargeEntity.id")
    @MainActor
    func testFinanceRepository_SaveCharges_IdempotentBySessionAndStudent() async throws {
        let container = try createTestContainer()
        let financeRepo = FinanceRepository(modelContainer: container)

        let sessionId = UUID()
        let studentId = UUID()

        let charge1 = ChargeEntity(
            id: UUID(),
            sessionId: sessionId,
            studentId: studentId,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid
        )
        let charge2Duplicate = ChargeEntity(
            id: UUID(),
            sessionId: sessionId,
            studentId: studentId,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid
        )

        try await financeRepo.saveCharges([charge1])
        try await financeRepo.saveCharges([charge2Duplicate])

        let savedCharges = try await financeRepo.fetchChargesForSession(sessionId: sessionId)
        #expect(savedCharges.count == 1)
        #expect(savedCharges.first?.studentId == studentId)
        #expect(savedCharges.first?.amount == 200_000)
    }

    @Test("Điều chỉnh trạng thái học sinh từ Đã hoàn thành sang Nghỉ sau khi hoàn thành buổi học: nếu khoản thu chưa thanh toán thì yêu cầu xác nhận và xóa khoản thu đó")
    @MainActor
    func testPostCompletionAdjustment_PresentToAbsent_DeletesUnpaidChargeOnConfirm() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let student = StudentEntity(fullName: "Nguyễn Minh An")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp Toán 10", defaultPricePerSession: 250_000)
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi 1",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo,
            financeRepository: financeRepo,
            notificationService: mockNotification
        )
        await vm.loadData()
        await vm.markAttendance(studentId: student.id, status: .present)
        try await vm.addPhotoAttachment(filePath: "proof.jpg")
        await vm.confirmAndFinalizeCompletion()

        #expect(vm.session.status == .completed)
        let initialCharges = try await financeRepo.fetchChargesForSession(sessionId: session.id)
        #expect(initialCharges.count == 1)
        #expect(initialCharges.first?.amount == 250_000)

        // Gửi yêu cầu đổi từ Đã hoàn thành (.present) sang Nghỉ (.absent)
        await vm.requestPostCompletionStatusAdjustment(studentId: student.id, newStatus: .absent)
        #expect(vm.pendingPostCompletionAdjustment != nil)

        // Xác nhận điều chỉnh
        await vm.confirmPostCompletionAdjustment()
        #expect(vm.pendingPostCompletionAdjustment == nil)
        #expect(vm.attendances.first(where: { $0.studentId == student.id })?.status == .absent)

        let remainingCharges = try await financeRepo.fetchChargesForSession(sessionId: session.id)
        #expect(remainingCharges.isEmpty)
    }

    @Test("Chặn đổi trạng thái từ Đã hoàn thành sang Nghỉ nếu khoản thu của học sinh cho buổi đó đã được thanh toán một phần hoặc toàn bộ")
    @MainActor
    func testPostCompletionAdjustment_PresentToAbsent_BlockedWhenChargeIsPaid() async throws {
        let container = try createTestContainer()
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let studentRepo = StudentRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let student = StudentEntity(fullName: "Trần Bảo Ngọc")
        try await studentRepo.saveStudent(student)
        let classGroup = ClassGroupEntity(name: "Lớp Hóa 11", defaultPricePerSession: 300_000)
        try await classRepo.saveClass(classGroup)
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Hóa",
            startTime: Date(),
            endTime: Date().addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)

        let vm = SessionDetailViewModel(
            session: session,
            scheduleRepository: scheduleRepo,
            classRepository: classRepo,
            studentRepository: studentRepo,
            financeRepository: financeRepo,
            notificationService: mockNotification
        )
        await vm.loadData()
        await vm.markAttendance(studentId: student.id, status: .present)
        try await vm.addPhotoAttachment(filePath: "proof.jpg")
        await vm.confirmAndFinalizeCompletion()

        let charges = try await financeRepo.fetchChargesForSession(sessionId: session.id)
        let charge = try #require(charges.first)

        // Ghi nhận thanh toán cho khoản thu này
        let payment = PaymentEntity(
            studentId: student.id,
            amount: 300_000,
            paidAt: Date(),
            paymentMethod: "Chuyển khoản",
            note: "Đã đóng đủ"
        )
        let allocation = PaymentAllocationEntity(
            paymentId: payment.id,
            chargeId: charge.id,
            allocatedAmount: 300_000
        )
        var paidCharge = charge
        paidCharge.status = .paid
        try await financeRepo.savePayment(payment)
        try await financeRepo.saveCharges([paidCharge])
        try await financeRepo.saveAllocations([allocation])

        // Thử đổi sang Nghỉ (.absent) -> phải bị chặn và báo rõ lý do
        await vm.requestPostCompletionStatusAdjustment(studentId: student.id, newStatus: .absent)
        #expect(vm.pendingPostCompletionAdjustment == nil)
        #expect(vm.validationAlertMessage != nil)
        #expect(vm.attendances.first(where: { $0.studentId == student.id })?.status == .present)

        let preservedCharges = try await financeRepo.fetchChargesForSession(sessionId: session.id)
        #expect(preservedCharges.count == 1)
        #expect(preservedCharges.first?.status == .paid)
    }

    // MARK: - Step 1 Notification Reliability, Deep-Link & Multi-Account Isolation Tests

    @Test("Chạm thông báo nhắc buổi dạy (session_reminder) điều hướng đúng đến tab Lịch dạy, đúng ngày và mở chi tiết buổi học")
    @MainActor
    func testAppNavigationState_HandleNotificationTap_SessionReminderOpensSessionDetail() {
        let navState = AppNavigationState()
        let sessionId = UUID()
        let sessionDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let activeOwner = UserSessionManager.shared.currentOwnerId

        let handled = navState.handleNotificationTap(
            identifier: "session_reminder_\(sessionId.uuidString)",
            userInfo: [
                "type": "session_reminder",
                "sessionId": sessionId.uuidString,
                "sessionStartTime": sessionDate.timeIntervalSince1970,
                "ownerId": activeOwner
            ],
            currentOwnerId: activeOwner
        )

        #expect(handled == true)
        #expect(navState.selectedTabRaw == AppTab.schedule.rawValue)
        #expect(navState.targetSessionId == sessionId)
        #expect(navState.targetScheduleDate != nil)
        #expect(Calendar.current.isDate(navState.targetScheduleDate!, inSameDayAs: sessionDate))
    }

    @Test("Chặn điều hướng khi chạm thông báo thuộc về tài khoản cũ (ownerId khác tài khoản hiện tại)")
    @MainActor
    func testAppNavigationState_HandleNotificationTap_BlocksCrossAccountNotification() {
        let navState = AppNavigationState()
        navState.selectedTabRaw = AppTab.home.rawValue
        navState.targetSessionId = nil
        navState.targetScheduleDate = nil

        let sessionId = UUID()
        let handled = navState.handleNotificationTap(
            identifier: "session_reminder_\(sessionId.uuidString)",
            userInfo: [
                "type": "session_reminder",
                "sessionId": sessionId.uuidString,
                "ownerId": "google_previous_user_123"
            ],
            currentOwnerId: "google_current_user_456"
        )

        #expect(handled == false)
        #expect(navState.selectedTabRaw == AppTab.home.rawValue)
        #expect(navState.targetSessionId == nil)
        #expect(navState.targetScheduleDate == nil)
    }

    @Test("Cập nhật giờ nhắc hằng ngày qua updateDailyReminderTime thực hiện nguyên tử và thay thế thông báo cũ")
    func testLocalNotificationService_AtomicUpdateDailyReminderTime() async {
        let mockNotification = MockNotificationService()
        mockNotification.isDailyReminderEnabled = true

        let scheduled1 = await mockNotification.updateDailyReminderTime(hour: 21, minute: 45)
        #expect(scheduled1 == true)
        #expect(mockNotification.dailyReminderHour == 21)
        #expect(mockNotification.dailyReminderMinute == 45)
        #expect(mockNotification.scheduledDailyReminderTime?.hour == 21)
        #expect(mockNotification.scheduledDailyReminderTime?.minute == 45)

        let scheduled2 = await mockNotification.updateDailyReminderTime(hour: 22, minute: 0)
        #expect(scheduled2 == true)
        #expect(mockNotification.dailyReminderHour == 22)
        #expect(mockNotification.dailyReminderMinute == 0)
        #expect(mockNotification.scheduledDailyReminderTime?.hour == 22)
        #expect(mockNotification.scheduledDailyReminderTime?.minute == 0)
    }

    @Test("HomeViewModel.createSession tự động lên lịch thông báo nhắc trước 60 phút cho buổi dạy mới")
    @MainActor
    func testHomeViewModel_CreateSession_SchedulesNotificationReminder() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let mockNotification = MockNotificationService()

        let classGroup = ClassGroupEntity(name: "Lớp Toán 9")
        try await classRepo.saveClass(classGroup)

        let futureStart = Date().addingTimeInterval(3 * 3600)
        let session = TeachingSessionEntity(
            classId: classGroup.id,
            title: "Buổi Toán 9",
            startTime: futureStart,
            endTime: futureStart.addingTimeInterval(90 * 60),
            status: .scheduled
        )

        let vm = HomeViewModel(
            studentRepository: studentRepo,
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            notificationService: mockNotification
        )

        try await vm.createSession(session)

        #expect(mockNotification.scheduledSessions.contains(where: { $0.id == session.id }))
    }
}

// MARK: - Mock Notification Service Helper for Tests
final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    var isSessionReminderEnabled: Bool = true
    var scheduledSessions: [TeachingSessionEntity] = []
    var cancelledSessionIds: [UUID] = []
    var syncedSessions: [TeachingSessionEntity] = []

    // Daily Reminder (Feature 10)
    var isDailyReminderEnabled: Bool = true
    var dailyReminderHour: Int = 22
    var dailyReminderMinute: Int = 0
    var scheduledDailyReminderTime: (hour: Int, minute: Int)? = nil
    var isDailyReminderCancelled: Bool = false

    func requestAuthorization() async -> Bool { true }
    #if canImport(UserNotifications)
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { .authorized }
    #endif

    @discardableResult
    func scheduleSessionReminder(for session: TeachingSessionEntity) async -> Bool {
        guard isSessionReminderEnabled else { return false }
        let reminderTime = session.startTime.addingTimeInterval(-3600)
        if session.status == .scheduled && reminderTime > Date() {
            scheduledSessions.removeAll { $0.id == session.id }
            scheduledSessions.append(session)
            return true
        }
        return false
    }

    func cancelSessionReminder(sessionId: UUID) async {
        cancelledSessionIds.append(sessionId)
        scheduledSessions.removeAll { $0.id == sessionId }
    }

    func syncSessionReminders(for sessions: [TeachingSessionEntity]) async {
        syncedSessions = sessions
        guard isSessionReminderEnabled else {
            scheduledSessions.removeAll()
            return
        }
        let now = Date()
        let upcoming = sessions
            .filter { $0.status == .scheduled && $0.startTime > now }
            .prefix(40)
        scheduledSessions = Array(upcoming)
    }

    func getPendingReminderSessionIds() async -> [UUID] {
        scheduledSessions.map { $0.id }
    }

    @discardableResult
    func scheduleDailyReminder(hour: Int, minute: Int) async -> Bool {
        guard isDailyReminderEnabled else { return false }
        scheduledDailyReminderTime = (hour, minute)
        isDailyReminderCancelled = false
        return true
    }

    @discardableResult
    func updateDailyReminderTime(hour: Int, minute: Int) async -> Bool {
        dailyReminderHour = hour
        dailyReminderMinute = minute
        if isDailyReminderEnabled {
            return await scheduleDailyReminder(hour: hour, minute: minute)
        }
        return false
    }

    func cancelDailyReminder() async {
        scheduledDailyReminderTime = nil
        isDailyReminderCancelled = true
    }

    func syncDailyReminder() async {
        if isDailyReminderEnabled {
            _ = await scheduleDailyReminder(hour: dailyReminderHour, minute: dailyReminderMinute)
        } else {
            await cancelDailyReminder()
        }
    }
}

