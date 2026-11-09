import Testing
import Foundation
import SwiftData
@testable import EduPetal

@Suite("Student & Class Management Test Suite")
struct StudentClassTests {

    @MainActor
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Student CRUD & Archiving Tests

    @Test("Thêm mới và truy xuất học sinh thành công")
    @MainActor
    func testSaveAndFetchStudent() async throws {
        let container = try createTestContainer()
        let repository = StudentRepository(modelContainer: container)

        let student = StudentEntity(
            fullName: "Nguyễn Văn An",
            phoneNumber: "0901234567",
            parentPhone: "0912345678",
            email: "an.nguyen@example.com",
            defaultPricePerSession: 200_000,
            notes: "Học sinh giỏi Toán"
        )

        try await repository.saveStudent(student)
        let fetched = try await repository.fetchStudent(byId: student.id)

        #expect(fetched != nil)
        #expect(fetched?.fullName == "Nguyễn Văn An")
        #expect(fetched?.phoneNumber == "0901234567")
        #expect(fetched?.defaultPricePerSession == 200_000)
        #expect(fetched?.isArchived == false)
    }

    @Test("Lưu trữ học sinh (Archive) bảo toàn toàn bộ dữ liệu, không xóa mất")
    @MainActor
    func testArchiveStudentPreservesData() async throws {
        let container = try createTestContainer()
        let repository = StudentRepository(modelContainer: container)

        let student = StudentEntity(
            fullName: "Trần Thị Bình",
            phoneNumber: "0987654321",
            defaultPricePerSession: 180_000
        )
        try await repository.saveStudent(student)

        // Thực hiện Archive
        try await repository.archiveStudent(id: student.id)

        // Kiểm tra danh sách active không có Bình
        let activeStudents = try await repository.fetchStudents(includeArchived: false)
        #expect(!activeStudents.contains(where: { $0.id == student.id }))

        // Kiểm tra danh sách bao gồm cả lưu trữ vẫn còn nguyên vẹn
        let allStudents = try await repository.fetchStudents(includeArchived: true)
        let archived = allStudents.first(where: { $0.id == student.id })
        #expect(archived != nil)
        #expect(archived?.isArchived == true)
        #expect(archived?.fullName == "Trần Thị Bình")
        #expect(archived?.defaultPricePerSession == 180_000)
    }

    @Test("Khôi phục học sinh từ mục lưu trữ trở lại danh sách đang học")
    @MainActor
    func testRestoreStudent() async throws {
        let container = try createTestContainer()
        let repository = StudentRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Lê Hoàng Cường", isArchived: true)
        try await repository.saveStudent(student)

        try await repository.restoreStudent(id: student.id)
        let fetched = try await repository.fetchStudent(byId: student.id)

        #expect(fetched?.isArchived == false)
    }

    // MARK: - Filter & Search UseCase Tests

    @Test("Lọc học sinh theo từ khóa tìm kiếm không phân biệt hoa thường")
    func testFilterStudentsByQuery() {
        let useCase = FilterStudentsUseCase()
        let students = [
            StudentEntity(fullName: "Nguyễn Văn An", phoneNumber: "0901234567", email: "an@test.com"),
            StudentEntity(fullName: "Trần Thị Bình", phoneNumber: "0988888888", email: "binh@test.com"),
            StudentEntity(fullName: "Lê Hoàng An", phoneNumber: "0977777777", email: "hoangan@test.com")
        ]

        let results = useCase.execute(students: students, query: "An", showArchivedOnly: false)
        #expect(results.count == 2)
        #expect(results.contains(where: { $0.fullName == "Nguyễn Văn An" }))
        #expect(results.contains(where: { $0.fullName == "Lê Hoàng An" }))

        let phoneResults = useCase.execute(students: students, query: "0988", showArchivedOnly: false)
        #expect(phoneResults.count == 1)
        #expect(phoneResults.first?.fullName == "Trần Thị Bình")
    }

    // MARK: - Class CRUD & Enrollment Tests

    @Test("Thêm mới và truy xuất lớp học thành công")
    @MainActor
    func testSaveAndFetchClass() async throws {
        let container = try createTestContainer()
        let repository = ClassRepository(modelContainer: container)

        let classGroup = ClassGroupEntity(
            name: "Toán 12 Chuyên",
            subject: "Toán",
            defaultPricePerSession: 150_000,
            sessionDurationMinutes: 120,
            colorHex: "#B84D73"
        )

        try await repository.saveClass(classGroup)
        let fetched = try await repository.fetchClass(byId: classGroup.id)

        #expect(fetched != nil)
        #expect(fetched?.name == "Toán 12 Chuyên")
        #expect(fetched?.subject == "Toán")
        #expect(fetched?.defaultPricePerSession == 150_000)
        #expect(fetched?.sessionDurationMinutes == 120)
    }

    @Test("Lưu trữ và khôi phục lớp học")
    @MainActor
    func testArchiveAndRestoreClass() async throws {
        let container = try createTestContainer()
        let repository = ClassRepository(modelContainer: container)

        let classGroup = ClassGroupEntity(name: "Văn 11 Cơ bản")
        try await repository.saveClass(classGroup)

        try await repository.archiveClass(id: classGroup.id)
        var fetched = try await repository.fetchClass(byId: classGroup.id)
        #expect(fetched?.isArchived == true)

        try await repository.restoreClass(id: classGroup.id)
        fetched = try await repository.fetchClass(byId: classGroup.id)
        #expect(fetched?.isArchived == false)
    }

    @Test("Ghi danh học sinh vào lớp và hủy ghi danh chuẩn xác")
    @MainActor
    func testEnrollAndUnenrollStudent() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Đỗ Minh Đức")
        try await studentRepo.saveStudent(student)

        let classGroup = ClassGroupEntity(name: "Lý 10 Nâng cao")
        try await classRepo.saveClass(classGroup)

        // Ghi danh vào lớp
        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)
        var isEnrolled = try await classRepo.isStudentEnrolled(studentId: student.id, classId: classGroup.id)
        #expect(isEnrolled == true)

        let enrollments = try await classRepo.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
        #expect(enrollments.count == 1)
        #expect(enrollments.first?.studentId == student.id)

        // Hủy ghi danh khỏi lớp
        try await classRepo.unenrollStudent(studentId: student.id, classId: classGroup.id)
        isEnrolled = try await classRepo.isStudentEnrolled(studentId: student.id, classId: classGroup.id)
        #expect(isEnrolled == false)

        let activeAfter = try await classRepo.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
        #expect(activeAfter.isEmpty)
    }

    // MARK: - Effective Price Calculation Tests

    @Test("Đơn giá riêng của học sinh luôn ghi đè đơn giá mặc định của lớp học")
    func testEffectivePriceWithStudentCustomPrice() {
        let useCase = GetEffectiveStudentPriceUseCase()
        let student = StudentEntity(fullName: "Học sinh A", defaultPricePerSession: 250_000)
        let classGroup = ClassGroupEntity(name: "Lớp A", defaultPricePerSession: 150_000)

        let effectivePrice = useCase.execute(student: student, classGroup: classGroup)
        #expect(effectivePrice == 250_000)
    }

    @Test("Khi học sinh không có đơn giá riêng, áp dụng đơn giá mặc định của lớp học")
    func testEffectivePriceWithClassDefaultPrice() {
        let useCase = GetEffectiveStudentPriceUseCase()
        let student = StudentEntity(fullName: "Học sinh B", defaultPricePerSession: nil)
        let classGroup = ClassGroupEntity(name: "Lớp B", defaultPricePerSession: 150_000)

        let effectivePrice = useCase.execute(student: student, classGroup: classGroup)
        #expect(effectivePrice == 150_000)
    }

    @Test("Khi học sinh có đơn giá riêng bằng 0, fallback về đơn giá mặc định của lớp")
    func testEffectivePriceWithZeroCustomPrice() {
        let useCase = GetEffectiveStudentPriceUseCase()
        let student = StudentEntity(fullName: "Học sinh C", defaultPricePerSession: 0)
        let classGroup = ClassGroupEntity(name: "Lớp C", defaultPricePerSession: 180_000)

        let effectivePrice = useCase.execute(student: student, classGroup: classGroup)
        #expect(effectivePrice == 180_000)
    }

    // MARK: - Safe Archive, Debt-blocking & Delete Tests

    @Test("Chặn xóa học sinh khi còn công nợ học phí chưa thanh toán")
    @MainActor
    func testDeleteStudent_BlockedWhenOutstandingTuitionDebtExists() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            ChargeModel.self,
            PaymentModel.self,
            PaymentAllocationModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Nguyễn Văn Nợ", isArchived: true)
        try await studentRepo.saveStudent(student)

        // Tạo 1 khoản nợ chưa thanh toán 300,000 VND
        let unpaidCharge = ChargeEntity(
            sessionId: UUID(),
            studentId: student.id,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid
        )
        try await financeRepo.saveCharge(unpaidCharge)

        let vm = StudentListViewModel(
            studentRepository: studentRepo,
            classRepository: classRepo,
            financeRepository: financeRepo
        )

        await vm.requestDelete(student: student)

        // Không được phép mở hộp thoại xóa trực tiếp
        #expect(vm.studentToDelete == nil)
        // Phải xuất hiện cảnh báo chặn xóa kèm số tiền nợ
        #expect(vm.studentBlockedFromDelete != nil)
        #expect(vm.studentBlockedFromDelete?.student.id == student.id)
        #expect(vm.studentBlockedFromDelete?.debtAmount == 300_000)
    }

    @Test("Cho phép mở hộp thoại xác nhận xóa khi học sinh không còn nợ học phí")
    @MainActor
    func testDeleteStudent_AllowedWhenNoDebt() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            ChargeModel.self,
            PaymentModel.self,
            PaymentAllocationModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Lê Sạch Nợ", isArchived: true)
        try await studentRepo.saveStudent(student)

        let vm = StudentListViewModel(
            studentRepository: studentRepo,
            classRepository: classRepo,
            financeRepository: financeRepo
        )

        await vm.requestDelete(student: student)

        // Không bị chặn bởi nợ
        #expect(vm.studentBlockedFromDelete == nil)
        // Mở hộp thoại xác nhận xóa
        #expect(vm.studentToDelete != nil)
        #expect(vm.studentToDelete?.id == student.id)

        // Thực thi xóa sau khi đã xác nhận
        await vm.executeDelete(id: student.id)
        let fetched = try await studentRepo.fetchStudent(byId: student.id)
        #expect(fetched == nil)
    }

    @Test("Cảnh báo khi lưu trữ học sinh đang có buổi dạy trong tương lai")
    @MainActor
    func testArchiveStudent_WarnsWhenUpcomingScheduledSessionsExist() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Trần Có Lịch")
        try await studentRepo.saveStudent(student)

        // Tạo 1 buổi dạy trong tương lai và thêm student vào điểm danh
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let sessionId = UUID()
        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Toán Nâng Cao Tương Lai",
            startTime: futureDate,
            endTime: futureDate.addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(session)
        let attendance = AttendanceEntity(sessionId: sessionId, studentId: student.id, status: .pending)
        try await scheduleRepo.saveAttendance(attendance)

        let vm = StudentListViewModel(
            studentRepository: studentRepo,
            classRepository: classRepo,
            scheduleRepository: scheduleRepo
        )

        await vm.requestArchive(student: student)

        // Phải phát hiện và hiển thị cảnh báo có 1 buổi học tương lai
        #expect(vm.studentToArchiveWithUpcomingSessions != nil)
        #expect(vm.studentToArchiveWithUpcomingSessions?.student.id == student.id)
        #expect(vm.studentToArchiveWithUpcomingSessions?.upcomingCount == 1)

        // Khi người dùng bấm tiếp tục lưu trữ
        await vm.executeArchive(id: student.id)
        let fetched = try await studentRepo.fetchStudent(byId: student.id)
        #expect(fetched?.isArchived == true)
        // Buổi học tương lai vẫn tồn tại nguyên vẹn, không bị âm thầm xóa
        let existingSession = try await scheduleRepo.fetchSession(byId: sessionId)
        #expect(existingSession != nil)
    }

    @Test("Học sinh đã lưu trữ bị loại khỏi danh sách enrollments active của lớp")
    @MainActor
    func testArchivedStudent_ExcludedFromActiveEnrollments() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Hoàng Lưu Trữ")
        try await studentRepo.saveStudent(student)

        let classGroup = ClassGroupEntity(name: "Lớp Hóa Học")
        try await classRepo.saveClass(classGroup)

        try await classRepo.enrollStudent(studentId: student.id, classId: classGroup.id)

        // Trước khi lưu trữ: có trong danh sách active enrollments
        let activeBefore = try await classRepo.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
        #expect(activeBefore.contains(where: { $0.studentId == student.id }))

        // Lưu trữ học sinh
        try await studentRepo.archiveStudent(id: student.id)

        // Sau khi lưu trữ: tự động bị loại khỏi danh sách active enrollments
        let activeAfter = try await classRepo.fetchEnrollments(forClassId: classGroup.id, activeOnly: true)
        #expect(!activeAfter.contains(where: { $0.studentId == student.id }))

        // Nhưng trong toàn bộ enrollments lịch sử vẫn còn nguyên
        let allEnrollments = try await classRepo.fetchEnrollments(forClassId: classGroup.id, activeOnly: false)
        #expect(allEnrollments.contains(where: { $0.studentId == student.id }))
    }

    // MARK: - Avatar Storage & Persistence Tests (Feature 12)

    @Test("AvatarStorageService: Lưu trữ, thay thế dọn dẹp ảnh cũ và xóa avatar")
    func testAvatarStorageLifecycle() throws {
        let service = AvatarStorageService.shared
        let dummyData1 = "ImageData_V1_\(UUID().uuidString)".data(using: .utf8)!
        let dummyData2 = "ImageData_V2_\(UUID().uuidString)".data(using: .utf8)!

        // 1. Lưu avatar đầu tiên
        let file1 = try service.saveAvatarData(dummyData1, prefix: "test_stu")
        #expect(!file1.isEmpty)
        #expect(service.avatarFileExists(named: file1))

        // 2. Thay thế bằng ảnh mới, kiểm tra ảnh cũ tự động bị dọn dẹp (cleanup)
        let file2 = try service.saveAvatarData(dummyData2, prefix: "test_stu", oldAvatarPath: file1)
        #expect(!file2.isEmpty)
        #expect(file2 != file1)
        #expect(service.avatarFileExists(named: file2))
        #expect(!service.avatarFileExists(named: file1), "Ảnh cũ phải được tự động dọn dẹp sau khi thay thế thành công")

        // 3. Xóa avatar
        service.deleteAvatar(named: file2)
        #expect(!service.avatarFileExists(named: file2), "Ảnh phải bị xóa hoàn toàn khỏi đĩa khi bấm xóa avatar")
    }

    @Test("Hồ sơ học sinh lưu trữ và khôi phục avatarPath bền vững trong SwiftData")
    @MainActor
    func testStudentAvatarPersistenceInSwiftData() async throws {
        let container = try createTestContainer()
        let repository = StudentRepository(modelContainer: container)

        let avatarFileName = "avatar_stu_123456_abc.jpg"
        let student = StudentEntity(
            fullName: "Phạm Minh Tâm",
            phoneNumber: "0911223344",
            avatarPath: avatarFileName
        )

        try await repository.saveStudent(student)
        let fetched = try await repository.fetchStudent(byId: student.id)

        #expect(fetched != nil)
        #expect(fetched?.fullName == "Phạm Minh Tâm")
        #expect(fetched?.avatarPath == avatarFileName)

        // Cập nhật gỡ bỏ avatar
        var updated = fetched!
        updated.avatarPath = nil
        try await repository.saveStudent(updated)

        let reloaded = try await repository.fetchStudent(byId: student.id)
        #expect(reloaded?.avatarPath == nil)
    }

    @Test("AvatarStorageService: Lưu trữ và đồng bộ avatarPath của giáo viên")
    func testTeacherAvatarPersistence() {
        let service = AvatarStorageService.shared
        let testPath = "avatar_teacher_preview_99.jpg"

        service.teacherAvatarPath = testPath
        #expect(service.teacherAvatarPath == testPath)

        service.teacherAvatarPath = nil
        #expect(service.teacherAvatarPath == nil)
    }

    // MARK: - Feature 2: StudentDetailViewModel & Enrollment Overlap / History Tests

    @Test("StudentDetailViewModel: Chỉnh sửa học sinh lưu bền vững vào SwiftData")
    @MainActor
    func testStudentDetail_SaveUpdatedStudentPersistsToDB() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let student = StudentEntity(
            fullName: "Nguyễn Minh Khôi",
            phoneNumber: "0901112222",
            defaultPricePerSession: 150_000
        )
        try await studentRepo.saveStudent(student)

        let vm = StudentDetailViewModel(
            student: student,
            studentRepository: studentRepo,
            classRepository: classRepo
        )

        var edited = student
        edited.fullName = "Nguyễn Minh Khôi (Đã sửa)"
        edited.phoneNumber = "0909998888"
        edited.defaultPricePerSession = 220_000

        await vm.saveUpdatedStudent(edited)

        let reloaded = try await studentRepo.fetchStudent(byId: student.id)
        #expect(reloaded?.fullName == "Nguyễn Minh Khôi (Đã sửa)")
        #expect(reloaded?.phoneNumber == "0909998888")
        #expect(reloaded?.defaultPricePerSession == 220_000)
    }

    @Test("StudentDetailViewModel: Chưa có điểm trả về weightedAverage == nil (không coi bằng 0), thêm/sửa điểm kiểm tra hợp lệ")
    @MainActor
    func testStudentDetail_GradesEmptyAndAddUpdateValidation() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            AssessmentModel.self,
            GradeModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let gradeRepo = GradeRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Phạm Thảo Vy")
        try await studentRepo.saveStudent(student)

        let mathClass = ClassGroupEntity(name: "Toán 10A", subject: "Toán")
        try await classRepo.saveClass(mathClass)
        try await classRepo.enrollStudent(studentId: student.id, classId: mathClass.id)

        let vm = StudentDetailViewModel(
            student: student,
            studentRepository: studentRepo,
            classRepository: classRepo,
            gradeRepository: gradeRepo
        )
        await vm.loadEnrolledClasses()

        // 1. Khi chưa có điểm: phải là nil (trạng thái trống), tuyệt đối không phải 0.0
        #expect(vm.studentGradeItems.isEmpty)
        #expect(vm.weightedAverage == nil)

        // 2. Nhập điểm vượt quá điểm tối đa -> phải bị chặn
        await #expect(throws: GradeValidationError.self) {
            try await vm.saveOrUpdateGrade(
                classId: mathClass.id,
                title: "Kiểm tra 15p",
                score: 11.0,
                maxScore: 10.0,
                weight: 1.0,
                date: Date(),
                notes: "Sai thang điểm"
            )
        }

        // 3. Nhập điểm hợp lệ (8.0 / 10.0, hệ số 1)
        try await vm.saveOrUpdateGrade(
            classId: mathClass.id,
            title: "Kiểm tra 15p",
            score: 8.0,
            maxScore: 10.0,
            weight: 1.0,
            date: Date(),
            notes: "Làm bài tốt"
        )
        #expect(vm.studentGradeItems.count == 1)
        #expect(vm.weightedAverage == 8.0)

        // 4. Sửa điểm hiện có lên 9.5 / 10.0
        let existingItem = vm.studentGradeItems.first!
        try await vm.saveOrUpdateGrade(
            existingItem: existingItem,
            classId: mathClass.id,
            title: "Kiểm tra 15p (Đã phúc khảo)",
            score: 9.5,
            maxScore: 10.0,
            weight: 1.0,
            date: existingItem.assessment.date,
            notes: "Cộng thêm điểm câu 4"
        )
        #expect(vm.studentGradeItems.count == 1)
        #expect(vm.studentGradeItems.first?.grade.score == 9.5)
        #expect(vm.studentGradeItems.first?.assessment.title == "Kiểm tra 15p (Đã phúc khảo)")
        #expect(vm.weightedAverage == 9.5)
    }

    @Test("Chặn đăng ký trùng lớp đang học hoặc chồng lấn khoảng thời gian tham gia lịch sử; giữ nguyên lịch sử khi kết thúc")
    @MainActor
    func testEnrollment_DuplicateAndOverlapBlocked_HistoryPreserved() async throws {
        let container = try createTestContainer()
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Lê Quốc Bảo")
        try await studentRepo.saveStudent(student)

        let englishClass = ClassGroupEntity(name: "IELTS 6.5", subject: "Tiếng Anh", defaultPricePerSession: 250_000)
        try await classRepo.saveClass(englishClass)

        let cal = Calendar.current
        let jan10 = cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let jan20 = cal.date(from: DateComponents(year: 2026, month: 1, day: 20))!
        let jan15 = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let feb01 = cal.date(from: DateComponents(year: 2026, month: 2, day: 1))!

        // 1. Tham gia lớp từ 10/01/2026
        try await classRepo.enrollStudent(studentId: student.id, classId: englishClass.id, enrolledAt: jan10)

        // 2. Đăng ký trùng khi đang học lớp này -> phải chặn
        await #expect(throws: EnrollmentValidationError.alreadyActiveInClass) {
            try await classRepo.enrollStudent(studentId: student.id, classId: englishClass.id, enrolledAt: jan15)
        }

        // 3. Kết thúc tham gia vào 20/01/2026 -> giữ lịch sử
        try await classRepo.unenrollStudent(studentId: student.id, classId: englishClass.id, leftAt: jan20)
        let historyAfterLeave = try await classRepo.fetchEnrollments(forStudentId: student.id, activeOnly: false)
        #expect(historyAfterLeave.count == 1)
        #expect(historyAfterLeave.first?.isActive == false)
        #expect(historyAfterLeave.first?.leftAt != nil)

        // 4. Đăng ký lại nhưng chọn ngày bắt đầu 15/01/2026 (chồng lấn giai đoạn 10/01 - 20/01) -> phải chặn
        await #expect(throws: EnrollmentValidationError.self) {
            try await classRepo.enrollStudent(studentId: student.id, classId: englishClass.id, enrolledAt: jan15)
        }

        // 5. Đăng ký lại từ 01/02/2026 (sau khi đã kết thúc kỳ trước) -> cho phép và giữ cả 2 bản ghi (1 lịch sử + 1 đang học)
        try await classRepo.enrollStudent(studentId: student.id, classId: englishClass.id, enrolledAt: feb01)
        let allEnrollments = try await classRepo.fetchEnrollments(forStudentId: student.id, activeOnly: false)
        let activeEnrollments = try await classRepo.fetchEnrollments(forStudentId: student.id, activeOnly: true)
        #expect(allEnrollments.count == 2)
        #expect(activeEnrollments.count == 1)
    }

    @Test("Chặn xóa học sinh khi đã có lịch sử tài chính dù công nợ bằng 0")
    @MainActor
    func testDeleteStudent_BlockedWhenPaidFinancialHistoryExists() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            ChargeModel.self,
            PaymentModel.self,
            PaymentAllocationModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Vũ Đã Đóng Đủ", isArchived: true)
        try await studentRepo.saveStudent(student)

        let paidCharge = ChargeEntity(
            sessionId: UUID(),
            studentId: student.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .paid
        )
        try await financeRepo.saveCharge(paidCharge)
        let payment = PaymentEntity(studentId: student.id, amount: 200_000, paidAt: Date())
        try await financeRepo.savePayment(payment)

        let detailVM = StudentDetailViewModel(
            student: student,
            studentRepository: studentRepo,
            classRepository: classRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadEnrolledClasses()
        await detailVM.requestDelete()

        #expect(detailVM.isDeleteBlockedShowing == true)
        #expect(detailVM.isDeleteConfirmationShowing == false)
        #expect(detailVM.hasFinancialHistoryBlock == true)
    }

    @Test("ClassListViewModel & ClassDetailViewModel: Xem lại các lớp đã tạo, lọc Đang mở/Đã lưu trữ và đồng bộ buổi học khi thêm học sinh vào lớp")
    @MainActor
    func testClassListAndClassDetail_ViewCreatedClassesAndSyncSessions() async throws {
        let schema = Schema([
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)

        let activeClass = ClassGroupEntity(name: "Toán 9 Luyện Thi", subject: "Toán", defaultPricePerSession: 180_000)
        let archivedClass = ClassGroupEntity(name: "Lý 8 Hè", subject: "Vật lý", defaultPricePerSession: 150_000, isArchived: true)
        try await classRepo.saveClass(activeClass)
        try await classRepo.saveClass(archivedClass)

        let student = StudentEntity(fullName: "Hoàng Gia Bảo")
        try await studentRepo.saveStudent(student)

        // Tạo 1 buổi học sắp tới của lớp Toán 9
        let futureStart = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let futureSession = TeachingSessionEntity(
            classId: activeClass.id,
            title: "Chuyên đề Hàm số",
            startTime: futureStart,
            endTime: futureStart.addingTimeInterval(90 * 60),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(futureSession)

        // 1. Kiểm tra ClassListViewModel hiển thị đúng các lớp đã tạo (Đang mở / Đã lưu trữ)
        let listVM = ClassListViewModel(classRepository: classRepo)
        await listVM.loadData()
        #expect(listVM.filteredClasses.count == 1)
        #expect(listVM.filteredClasses.first?.name == "Toán 9 Luyện Thi")

        listVM.showArchived = true
        #expect(listVM.filteredClasses.count == 1)
        #expect(listVM.filteredClasses.first?.name == "Lý 8 Hè")

        // 2. Kiểm tra ClassDetailViewModel xem chi tiết lớp, thêm học sinh và tự động đồng bộ vào buổi học sắp tới
        let detailVM = ClassDetailViewModel(
            classGroup: activeClass,
            classRepository: classRepo,
            studentRepository: studentRepo,
            scheduleRepository: scheduleRepo
        )
        await detailVM.loadMembers()
        #expect(detailVM.enrolledStudents.isEmpty)
        #expect(detailVM.classSessions.count == 1)

        await detailVM.enrollStudent(id: student.id)
        #expect(detailVM.enrolledStudents.count == 1)
        #expect(detailVM.enrolledStudents.first?.fullName == "Hoàng Gia Bảo")

        let sessionAttendances = try await scheduleRepo.fetchAttendances(forSessionId: futureSession.id)
        #expect(sessionAttendances.contains(where: { $0.studentId == student.id }))
    }

    @Test("Xóa lớp ở phần lưu trữ: hiện xác nhận xóa khi không nợ học phí; nếu còn học phí chưa thanh toán thì nhắc và yêu cầu xác nhận đã thanh toán mới cho xóa")
    @MainActor
    func testDeleteArchivedClass_ConfirmationAndUnpaidTuitionCheck() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let studentRepo = StudentRepository(modelContainer: container)
        let classRepo = ClassRepository(modelContainer: container)
        let scheduleRepo = ScheduleRepository(modelContainer: container)
        let financeRepo = FinanceRepository(modelContainer: container)

        // Lớp lưu trữ 1: Không nợ học phí
        let cleanArchivedClass = ClassGroupEntity(
            name: "Hoá 10 Học Kỳ 1",
            subject: "Hoá học",
            defaultPricePerSession: 150_000,
            isArchived: true
        )
        // Lớp lưu trữ 2: Đang còn học phí chưa thanh toán
        let unpaidArchivedClass = ClassGroupEntity(
            name: "Anh Văn Giao Tiếp",
            subject: "Tiếng Anh",
            defaultPricePerSession: 200_000,
            isArchived: true
        )
        try await classRepo.saveClass(cleanArchivedClass)
        try await classRepo.saveClass(unpaidArchivedClass)

        let student = StudentEntity(fullName: "Phạm Minh Châu")
        try await studentRepo.saveStudent(student)
        try await classRepo.enrollStudent(studentId: student.id, classId: unpaidArchivedClass.id)

        let session = TeachingSessionEntity(
            classId: unpaidArchivedClass.id,
            title: "Buổi 1",
            startTime: Date().addingTimeInterval(-7200),
            endTime: Date().addingTimeInterval(-3600),
            status: .completed
        )
        try await scheduleRepo.saveSession(session)

        let unpaidCharge = ChargeEntity(
            sessionId: session.id,
            studentId: student.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid
        )
        try await financeRepo.saveCharge(unpaidCharge)

        let listVM = ClassListViewModel(
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        listVM.showArchived = true
        await listVM.loadData()
        #expect(listVM.filteredClasses.count == 2)

        // 1. Yêu cầu xóa lớp không nợ học phí -> hiện hộp thoại "Chắc chắn xóa"
        await listVM.requestDeleteArchivedClass(cleanArchivedClass)
        #expect(listVM.classPendingSimpleDelete?.id == cleanArchivedClass.id)
        #expect(listVM.classPendingUnpaidDelete == nil)

        await listVM.confirmDeleteClass(id: cleanArchivedClass.id, confirmPaidIfUnpaid: false)
        #expect(listVM.filteredClasses.count == 1)

        // 2. Yêu cầu xóa lớp còn nợ học phí -> hiện cảnh báo "Còn học phí chưa thanh toán"
        await listVM.requestDeleteArchivedClass(unpaidArchivedClass)
        #expect(listVM.classPendingSimpleDelete == nil)
        #expect(listVM.classPendingUnpaidDelete?.classGroup.id == unpaidArchivedClass.id)
        #expect(listVM.classPendingUnpaidDelete?.unpaidAmount == 200_000)

        // Nếu chưa xác nhận đã thanh toán -> chặn xóa
        await listVM.confirmDeleteClass(id: unpaidArchivedClass.id, confirmPaidIfUnpaid: false)
        #expect(listVM.errorMessage != nil)
        #expect(listVM.filteredClasses.count == 1)

        // Khi xác nhận đã thanh toán -> ghi nhận thu đủ học phí và cho phép xóa lớp
        await listVM.confirmDeleteClass(id: unpaidArchivedClass.id, confirmPaidIfUnpaid: true)
        #expect(listVM.filteredClasses.isEmpty)

        let updatedCharges = try await financeRepo.fetchChargesForStudent(studentId: student.id)
        #expect(updatedCharges.first?.status == .paid)
        let payments = try await financeRepo.fetchPaymentsForStudent(studentId: student.id)
        #expect(payments.first?.amount == 200_000)
    }

    // MARK: - Step 2: Thay tab Đề thi bằng Lớp học & Bảo toàn lịch sử tài chính/buổi học

    @Test("Thanh điều hướng chính (AppTab) gồm đúng 5 tab: Tổng quan, Học sinh, Lịch dạy, Lớp học, Học phí (không còn Đề thi)")
    func testMainTabView_AppTabs_ReplacesExamsWithClasses() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs[0] == .home)
        #expect(tabs[1] == .students)
        #expect(tabs[2] == .schedule)
        #expect(tabs[3] == .classes)
        #expect(tabs[4] == .finance)
        #expect(AppTab.classes.rawValue == 3)
        #expect(!tabs.map { $0.title }.contains("Đề thi"))
    }

    @Test("ClassListViewModel tải đúng buổi dạy tiếp theo (nextUpcomingSessions) và không cascade xóa buổi đã hoàn thành/học phí khi xóa lớp")
    @MainActor
    func testClassListViewModel_LoadsNextUpcomingSessionAndPreservesCompletedHistory() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let isolatedOwner = "step2_test_owner_\(UUID().uuidString)"
        let classRepo = ClassRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let scheduleRepo = ScheduleRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let financeRepo = FinanceRepository(modelContext: container.mainContext, ownerId: isolatedOwner)

        let activeClass = ClassGroupEntity(
            name: "Toán 12 Luyện Thi",
            subject: "Toán",
            defaultPricePerSession: 250_000
        )
        try await classRepo.saveClass(activeClass)

        let now = Date()
        // 1. Buổi quá khứ đã hoàn thành
        let completedSession = TeachingSessionEntity(
            classId: activeClass.id,
            title: "Buổi Đã Dạy",
            startTime: now.addingTimeInterval(-86400),
            endTime: now.addingTimeInterval(-86400 + 5400),
            status: .completed
        )
        // 2. Buổi tương lai gần nhất (sau 2 ngày)
        let nextSession = TeachingSessionEntity(
            classId: activeClass.id,
            title: "Buổi Sắp Tới 1",
            startTime: now.addingTimeInterval(2 * 86400),
            endTime: now.addingTimeInterval(2 * 86400 + 5400),
            status: .scheduled
        )
        // 3. Buổi tương lai xa hơn (sau 5 ngày)
        let laterSession = TeachingSessionEntity(
            classId: activeClass.id,
            title: "Buổi Sắp Tới 2",
            startTime: now.addingTimeInterval(5 * 86400),
            endTime: now.addingTimeInterval(5 * 86400 + 5400),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(completedSession)
        try await scheduleRepo.saveSession(laterSession)
        try await scheduleRepo.saveSession(nextSession)

        let listVM = ClassListViewModel(
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await listVM.loadData()

        // Buổi dạy tiếp theo của lớp phải là nextSession (sớm nhất trong tương lai)
        #expect(listVM.nextUpcomingSessions[activeClass.id]?.id == nextSession.id)

        // Khi lưu trữ rồi xóa lớp: các buổi chưa diễn ra bị xóa nhưng buổi đã hoàn thành (.completed) được giữ lại để bảo toàn đối soát
        await listVM.archiveClass(id: activeClass.id)
        await listVM.confirmDeleteClass(id: activeClass.id, confirmPaidIfUnpaid: true)

        let remainingCompleted = try await scheduleRepo.fetchSession(byId: completedSession.id)
        let deletedFuture = try await scheduleRepo.fetchSession(byId: nextSession.id)
        #expect(remainingCompleted != nil)
        #expect(remainingCompleted?.status == .completed)
        #expect(deletedFuture == nil)
    }

    @Test("ClassListViewModel kiểm tra bắt buộc Tên lớp + Đơn giá > 0 và chống lưu trùng")
    @MainActor
    func testClassListViewModel_SaveClass_ValidatesNameAndPrice_AndPreventsDuplicateTap() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let isolatedOwner = "step3_class_save_\(UUID().uuidString)"
        let classRepo = ClassRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let listVM = ClassListViewModel(classRepository: classRepo)

        // 1. Tên lớp rỗng -> từ chối lưu
        let emptyNameClass = ClassGroupEntity(name: "   ", defaultPricePerSession: 150_000)
        let savedEmptyName = await listVM.saveClass(emptyNameClass)
        #expect(savedEmptyName == false)
        #expect(listVM.errorMessage != nil)
        #expect(listVM.classes.isEmpty)

        // 2. Đơn giá <= 0 -> từ chối lưu
        let zeroPriceClass = ClassGroupEntity(name: "Lớp Toán 10", defaultPricePerSession: 0)
        let savedZeroPrice = await listVM.saveClass(zeroPriceClass)
        #expect(savedZeroPrice == false)
        #expect(listVM.errorMessage != nil)
        #expect(listVM.classes.isEmpty)

        // 3. Chỉ cần Tên lớp và Đơn giá hợp lệ (các trường khác tùy chọn để trống) -> lưu thành công
        let validMinimalClass = ClassGroupEntity(
            name: "Lớp Toán 10 Cơ Bản",
            subject: "",
            defaultPricePerSession: 180_000,
            notes: ""
        )
        let savedValid = await listVM.saveClass(validMinimalClass)
        #expect(savedValid == true)
        #expect(listVM.errorMessage == nil)
        #expect(listVM.classes.count == 1)
        #expect(listVM.classes.first?.name == "Lớp Toán 10 Cơ Bản")
        #expect(listVM.classes.first?.defaultPricePerSession == 180_000)
    }

    @Test("ClassDetailViewModel hỗ trợ thêm học sinh có sẵn & tạo học sinh mới ngay trong lớp, không phát sinh học phí khi mới ghi danh")
    @MainActor
    func testClassDetailViewModel_CreateAndEnrollStudent_AndEnrollExistingStudents_WithoutGeneratingCharges() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let isolatedOwner = "step3_enroll_\(UUID().uuidString)"
        let studentRepo = StudentRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let classRepo = ClassRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let scheduleRepo = ScheduleRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let financeRepo = FinanceRepository(modelContext: container.mainContext, ownerId: isolatedOwner)

        let targetClass = ClassGroupEntity(name: "Tiếng Anh Giao Tiếp", defaultPricePerSession: 200_000)
        try await classRepo.saveClass(targetClass)

        // Tạo sẵn 1 buổi học tương lai của lớp
        let futureSession = TeachingSessionEntity(
            classId: targetClass.id,
            title: "Buổi 1",
            startTime: Date().addingTimeInterval(86400),
            endTime: Date().addingTimeInterval(86400 + 5400),
            status: .scheduled
        )
        try await scheduleRepo.saveSession(futureSession)

        // Tạo sẵn 1 học sinh ngoài lớp
        let existingStudent = StudentEntity(fullName: "Phạm Học Sinh Có Sẵn")
        try await studentRepo.saveStudent(existingStudent)

        let detailVM = ClassDetailViewModel(
            classGroup: targetClass,
            classRepository: classRepo,
            studentRepository: studentRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadMembers()
        #expect(detailVM.enrolledStudents.isEmpty)
        #expect(detailVM.availableStudentsToEnroll.count == 1)

        // 1. Thêm học sinh có sẵn vào lớp
        let enrolledExisting = await detailVM.enrollStudents(ids: [existingStudent.id])
        #expect(enrolledExisting == true)
        #expect(detailVM.enrolledStudents.count == 1)
        #expect(detailVM.availableStudentsToEnroll.isEmpty)

        // 2. Tạo học sinh mới và thêm thẳng vào lớp
        let brandNewStudent = StudentEntity(fullName: "Nguyễn Học Sinh Mới", phoneNumber: "0912345678")
        let createdAndEnrolled = await detailVM.createAndEnrollStudent(brandNewStudent)
        #expect(createdAndEnrolled == true)
        #expect(detailVM.enrolledStudents.count == 2)

        // Kiểm tra cả 2 học sinh đã được tự động thêm vào danh sách điểm danh chờ (.pending) của buổi học tương lai
        let attendances = try await scheduleRepo.fetchAttendances(forSessionId: futureSession.id)
        #expect(attendances.count == 2)
        #expect(attendances.allSatisfy { $0.status == .pending })

        // Quy tắc bất biến Học phí: Ghi danh học sinh vào lớp chưa phát sinh bất kỳ khoản thu (ChargeEntity) nào
        let charges = try await financeRepo.fetchCharges()
        #expect(charges.isEmpty)
    }

    @Test("ClassDetailViewModel thiết lập lịch theo tháng tạo đúng chuỗi buổi học, khởi tạo điểm danh pending và chưa phát sinh học phí")
    @MainActor
    func testClassDetailViewModel_CreateMonthlySchedule_GeneratesSessionsAndPendingAttendance_WithoutCharges() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let isolatedOwner = "step4_monthly_schedule_\(UUID().uuidString)"
        let studentRepo = StudentRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let classRepo = ClassRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let scheduleRepo = ScheduleRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let financeRepo = FinanceRepository(modelContext: container.mainContext, ownerId: isolatedOwner)

        let targetClass = ClassGroupEntity(
            name: "Vật Lý 11 Nâng Cao",
            subject: "Vật Lý",
            defaultPricePerSession: 220_000,
            sessionDurationMinutes: 90
        )
        try await classRepo.saveClass(targetClass)

        let studentA = StudentEntity(fullName: "Trần Minh A")
        let studentB = StudentEntity(fullName: "Lê Minh B")
        try await studentRepo.saveStudent(studentA)
        try await studentRepo.saveStudent(studentB)
        try await classRepo.enrollStudent(studentId: studentA.id, classId: targetClass.id)
        try await classRepo.enrollStudent(studentId: studentB.id, classId: targetClass.id)

        let detailVM = ClassDetailViewModel(
            classGroup: targetClass,
            classRepository: classRepo,
            studentRepository: studentRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadMembers()
        #expect(detailVM.enrolledStudents.count == 2)

        // Thiết lập lịch học trong 14 ngày tới cho Thứ 2, Thứ 4, Thứ 6 lúc 18:00 - 19:30
        let cal = Calendar.current
        let startDate = cal.startOfDay(for: Date().addingTimeInterval(86400))
        let endDate = cal.date(byAdding: .day, value: 14, to: startDate) ?? startDate
        var startComp = cal.dateComponents([.year, .month, .day], from: startDate)
        startComp.hour = 18
        startComp.minute = 0
        let startTime = cal.date(from: startComp) ?? startDate
        let endTime = startTime.addingTimeInterval(90 * 60)

        let preview = detailVM.previewMonthlySessions(
            selectedDays: [.monday, .wednesday, .friday],
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: startTime,
            sessionEndTime: endTime
        )
        #expect(!preview.isEmpty)

        let savedCount = await detailVM.createMonthlySchedule(
            selectedDays: [.monday, .wednesday, .friday],
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: startTime,
            sessionEndTime: endTime
        )
        #expect(savedCount == preview.count)
        #expect(detailVM.upcomingSessions.count == preview.count)

        // Gọi lại lần nữa cùng khung giờ không tạo trùng
        let duplicateCount = await detailVM.createMonthlySchedule(
            selectedDays: [.monday, .wednesday, .friday],
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: startTime,
            sessionEndTime: endTime
        )
        #expect(duplicateCount == 0)

        // Kiểm tra từng buổi học đều có sẵn điểm danh .pending cho cả 2 học sinh trong lớp
        if let firstSession = detailVM.upcomingSessions.first {
            let atts = try await scheduleRepo.fetchAttendances(forSessionId: firstSession.id)
            #expect(atts.count == 2)
            #expect(atts.allSatisfy { $0.status == .pending })
        }

        // Quy tắc học phí: Tạo lịch theo tháng chưa phát sinh khoản thu nào
        let allCharges = try await financeRepo.fetchCharges()
        #expect(allCharges.isEmpty)
    }

    @Test("ClassDetailViewModel tổng hợp đúng Học phí liên quan của lớp: Đã phát sinh - Đã thu = Còn nợ và giữ nguyên lịch sử khi sửa lớp")
    @MainActor
    func testClassDetailViewModel_LoadsClassFinanceSummaryAndHistory_AccruedMinusCollectedEqualsOutstanding() async throws {
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
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let isolatedOwner = "step4_class_finance_\(UUID().uuidString)"
        let studentRepo = StudentRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let classRepo = ClassRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let scheduleRepo = ScheduleRepository(modelContext: container.mainContext, ownerId: isolatedOwner)
        let financeRepo = FinanceRepository(modelContext: container.mainContext, ownerId: isolatedOwner)

        let targetClass = ClassGroupEntity(
            name: "Hóa Học 12",
            subject: "Hóa",
            defaultPricePerSession: 200_000
        )
        try await classRepo.saveClass(targetClass)

        let student = StudentEntity(fullName: "Phạm Thu Ngân")
        try await studentRepo.saveStudent(student)
        try await classRepo.enrollStudent(studentId: student.id, classId: targetClass.id)

        // Tạo 2 buổi đã hoàn thành của lớp
        let session1 = TeachingSessionEntity(
            classId: targetClass.id,
            title: "Buổi 1",
            startTime: Date().addingTimeInterval(-3 * 86400),
            endTime: Date().addingTimeInterval(-3 * 86400 + 5400),
            status: .completed
        )
        let session2 = TeachingSessionEntity(
            classId: targetClass.id,
            title: "Buổi 2",
            startTime: Date().addingTimeInterval(-1 * 86400),
            endTime: Date().addingTimeInterval(-1 * 86400 + 5400),
            status: .completed
        )
        try await scheduleRepo.saveSession(session1)
        try await scheduleRepo.saveSession(session2)

        let charge1 = ChargeEntity(
            sessionId: session1.id,
            studentId: student.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .paid
        )
        let charge2 = ChargeEntity(
            sessionId: session2.id,
            studentId: student.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid
        )
        try await financeRepo.saveCharges([charge1, charge2])

        let payment1 = PaymentEntity(
            studentId: student.id,
            amount: 200_000,
            paidAt: Date().addingTimeInterval(-2 * 86400),
            paymentMethod: "Chuyển khoản",
            note: "Thu học phí buổi 1"
        )
        try await financeRepo.savePayment(payment1)
        try await financeRepo.saveAllocations([
            PaymentAllocationEntity(paymentId: payment1.id, chargeId: charge1.id, allocatedAmount: 200_000)
        ])

        let detailVM = ClassDetailViewModel(
            classGroup: targetClass,
            classRepository: classRepo,
            studentRepository: studentRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadMembers()

        #expect(detailVM.totalAccruedAmount == 400_000)
        #expect(detailVM.totalCollectedAmount == 200_000)
        #expect(detailVM.totalOutstandingAmount == 200_000)
        #expect(detailVM.totalAccruedAmount - detailVM.totalCollectedAmount == detailVM.totalOutstandingAmount)
        #expect(detailVM.studentTuitionSummaries.count == 1)
        #expect(detailVM.classPaymentHistory.count == 1)

        // Khi sửa đơn giá mặc định của lớp lên 300.000đ, các khoản đã phát sinh/đã thu trước đó (snapshot 200.000đ) không bị thay đổi
        var editedClass = targetClass
        editedClass.defaultPricePerSession = 300_000
        try await classRepo.saveClass(editedClass)
        await detailVM.loadMembers()

        #expect(detailVM.totalAccruedAmount == 400_000)
        #expect(detailVM.totalCollectedAmount == 200_000)
        #expect(detailVM.totalOutstandingAmount == 200_000)
    }
}

