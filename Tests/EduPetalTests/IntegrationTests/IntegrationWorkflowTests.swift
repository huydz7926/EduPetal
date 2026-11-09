import Testing
import Foundation
import SwiftData
import PDFKit
@testable import EduPetal

@Suite("End-to-End Integration & Full Lifecycle Workflow Test Suite")
struct IntegrationWorkflowTests {

    @MainActor
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema(EduPetalSchemaV1.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Workflow 1: Complete Teaching & Single-Source Tuition Lifecycle

    @Test("Workflow 1: Full Student -> Session -> Attendance -> Snapshot Charge -> FIFO Payment -> Zero Overpayment Lifecycle")
    func testTeachingAndFinanceFullLifecycle() throws {
        let studentId = UUID()
        let classId = UUID()
        let sessionId = UUID()

        // 1. Setup Student & Class with pricing rules
        let student = StudentEntity(
            id: studentId,
            fullName: "Hoàng Minh Tâm",
            phoneNumber: "0912345678",
            defaultPricePerSession: 250_000 // Custom student price
        )

        let classGroup = ClassGroupEntity(
            id: classId,
            name: "Luyện thi Đại học Toán Chuyên",
            subject: "Toán",
            defaultPricePerSession: 200_000 // Class fallback price
        )

        // 2. Schedule Session & Overlap Check
        let now = Date()
        let sessionStartTime = now.addingTimeInterval(3600)
        let sessionEndTime = now.addingTimeInterval(3600 + 5400) // 1.5 hours

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: classId,
            title: "Chuyên đề Hình học Không gian Oxyz",
            startTime: sessionStartTime,
            endTime: sessionEndTime,
            status: .scheduled
        )

        let overlapUseCase = CheckScheduleOverlapUseCase()
        let hasConflict = overlapUseCase.execute(
            newStartTime: sessionStartTime,
            newEndTime: sessionEndTime,
            existingSessions: [],
            excludeSessionId: nil
        )
        #expect(hasConflict == nil)

        // 3. Mark 100% Attendance & Complete Session
        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: studentId, status: .present)
        ]

        let completeSessionUseCase = CompleteTeachingSessionUseCase()
        let completedSession = try completeSessionUseCase.execute(
            session: session,
            attendances: attendances,
            expectedStudentIds: [studentId]
        )
        #expect(completedSession.status == .completed)

        // 4. Generate Idempotent Charges with Unit Price Snapshot
        let generateChargesUseCase = GenerateSessionChargesUseCase()
        let chargesRun1 = generateChargesUseCase.execute(
            session: completedSession,
            attendances: attendances,
            students: [student],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(chargesRun1.count == 1)
        let charge = chargesRun1[0]
        #expect(charge.amount == 250_000)
        #expect(charge.unitPriceSnapshot == 250_000)
        #expect(charge.status == .unpaid)

        // Idempotency check: running again generates 0 new charges
        let chargesRun2 = generateChargesUseCase.execute(
            session: completedSession,
            attendances: attendances,
            students: [student],
            classGroup: classGroup,
            existingCharges: chargesRun1
        )
        #expect(chargesRun2.isEmpty)

        // 5. Initial Balance Check
        let financeSummaryUseCase = CalculateFinanceSummaryUseCase()
        var summary = financeSummaryUseCase.execute(charges: [charge], payments: [])
        #expect(summary.accruedTuition == 250_000)
        #expect(summary.collectedTuition == 0)
        #expect(summary.outstandingBalance == 250_000)
        #expect(summary.outstandingBalance == summary.accruedTuition - summary.collectedTuition)

        // 6. Partial Payment Recording (150,000 VND)
        let recordPaymentUseCase = RecordPaymentUseCase()
        let payment1Result = try recordPaymentUseCase.execute(
            studentId: studentId,
            amount: 150_000,
            paymentMethod: "Chuyển khoản",
            note: "Thanh toán đợt 1",
            studentCharges: [charge],
            existingAllocations: []
        )

        #expect(payment1Result.updatedCharges[0].status == .partiallyPaid)
        #expect(payment1Result.allocations[0].allocatedAmount == 150_000)

        // Check updated summary after partial payment
        summary = financeSummaryUseCase.execute(
            charges: payment1Result.updatedCharges,
            payments: [payment1Result.payment]
        )
        #expect(summary.accruedTuition == 250_000)
        #expect(summary.collectedTuition == 150_000)
        #expect(summary.outstandingBalance == 100_000)
        #expect(summary.outstandingBalance == summary.accruedTuition - summary.collectedTuition)

        // 7. Full Remaining Payment Recording (100,000 VND)
        let payment2Result = try recordPaymentUseCase.execute(
            studentId: studentId,
            amount: 100_000,
            paymentMethod: "Tiền mặt",
            note: "Thanh toán dứt điểm",
            studentCharges: payment1Result.updatedCharges,
            existingAllocations: payment1Result.allocations
        )

        #expect(payment2Result.updatedCharges[0].status == .paid)
        #expect(payment2Result.allocations[0].allocatedAmount == 100_000)

        // Check summary after full payment
        let allPayments = [payment1Result.payment, payment2Result.payment]
        summary = financeSummaryUseCase.execute(
            charges: payment2Result.updatedCharges,
            payments: allPayments
        )
        #expect(summary.accruedTuition == 250_000)
        #expect(summary.collectedTuition == 250_000)
        #expect(summary.outstandingBalance == 0)

        // 8. Overpayment Rejection (Strict Rule)
        #expect(throws: RecordPaymentError.studentHasNoOutstandingBalance) {
            try recordPaymentUseCase.execute(
                studentId: studentId,
                amount: 50_000,
                studentCharges: payment2Result.updatedCharges,
                existingAllocations: payment1Result.allocations + payment2Result.allocations
            )
        }
    }

    // MARK: - Workflow 2: Assignment Submission, Grading & Progressive Analytics

    @Test("Workflow 2: Assignment Submission -> Pending Counter -> Grading -> Progression Weighted Average")
    func testAssignmentAndGradingLifecycle() throws {
        let studentId = UUID()
        let classId = UUID()
        let assignmentId = UUID()
        let recordId = UUID()

        let assignment = AssignmentEntity(
            id: assignmentId,
            classId: classId,
            title: "Bài tập Phương trình Mũ & Logarit",
            maxScore: 10.0
        )

        // 1. Student submits assignment -> status .submitted
        let submittedRecord = AssignmentRecordEntity(
            id: recordId,
            assignmentId: assignmentId,
            studentId: studentId,
            status: .submitted
        )

        // 2. Dashboard detects pending grading
        let dashboardUseCase = CalculateDashboardMetricsUseCase()
        let metricsBeforeGrading = dashboardUseCase.execute(
            students: [StudentEntity(id: studentId, fullName: "Lê Văn H")],
            classes: [ClassGroupEntity(id: classId, name: "Toán 12")],
            sessions: [],
            records: [submittedRecord],
            charges: [],
            payments: []
        )
        #expect(metricsBeforeGrading.pendingGradingAssignmentsCount == 1)

        // 3. Teacher grades the assignment
        let gradeValidation = ValidateGradeInputUseCase()
        let validatedScore: Double = 8.75
        try gradeValidation.execute(score: validatedScore, maxScore: assignment.maxScore)
        #expect(validatedScore == 8.75)

        var gradedRecord = submittedRecord
        gradedRecord.score = validatedScore
        gradedRecord.status = .graded
        gradedRecord.feedback = "Trình bày rõ ràng, bước 3 có sáng tạo."

        // 4. Create Grade & Assessment
        let assessment = AssessmentEntity(classId: classId, title: assignment.title, maxScore: 10.0, weight: 1.0)
        let grade = GradeEntity(assessmentId: assessment.id, studentId: studentId, score: validatedScore)

        let weightedAverageUseCase = CalculateWeightedAverageUseCase()
        let avg = weightedAverageUseCase.execute(items: [StudentGradeItem(grade: grade, assessment: assessment)])
        #expect(avg == 8.8) // Rounded to 1 decimal place (standard VN grading)

        // 5. Dashboard pending grading clears to 0
        let metricsAfterGrading = dashboardUseCase.execute(
            students: [StudentEntity(id: studentId, fullName: "Lê Văn H")],
            classes: [ClassGroupEntity(id: classId, name: "Toán 12")],
            sessions: [],
            records: [gradedRecord],
            charges: [],
            payments: []
        )
        #expect(metricsAfterGrading.pendingGradingAssignmentsCount == 0)
    }

    // MARK: - Workflow 3: Class Management -> Monthly Schedule -> Attendance -> Class Finance & Safe Archive Lifecycle

    @Test("Workflow 3: Class Creation -> Student Enrollment (0 Charges) -> Monthly Schedule -> Attendance Completion -> Class Finance & Archive Protection")
    @MainActor
    func testClassManagementMonthlyScheduleAndFinanceLifecycle() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let ownerId = "teacher_class_workflow"

        let classRepo = ClassRepository(modelContext: context, ownerId: ownerId)
        let studentRepo = StudentRepository(modelContext: context, ownerId: ownerId)
        let scheduleRepo = ScheduleRepository(modelContext: context, ownerId: ownerId)
        let financeRepo = FinanceRepository(modelContext: context, ownerId: ownerId)

        let listVM = ClassListViewModel(
            classRepository: classRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )

        // 1. Tạo lớp mới với tên lớp và đơn giá hợp lệ (> 0)
        let newClass = ClassGroupEntity(
            name: "Lớp Toán 9 Luyện Thi Vào 10",
            subject: "Toán",
            defaultPricePerSession: 200_000,
            sessionDurationMinutes: 90,
            colorHex: "#C94A6A"
        )
        let savedClassOk = await listVM.saveClass(newClass)
        #expect(savedClassOk == true)
        #expect(listVM.classes.count == 1)

        let detailVM = ClassDetailViewModel(
            classGroup: newClass,
            classRepository: classRepo,
            studentRepository: studentRepo,
            scheduleRepository: scheduleRepo,
            financeRepository: financeRepo
        )
        await detailVM.loadMembers()

        // 2. Tạo và ghi danh học sinh vào lớp -> CHƯA phát sinh bất kỳ khoản học phí nào
        let didCreateStudent = await detailVM.createAndEnrollStudent(
            StudentEntity(
                fullName: "Nguyễn Minh Khôi",
                phoneNumber: "0912345678",
                defaultPricePerSession: nil // Dùng đơn giá mặc định của lớp (200.000đ)
            )
        )
        #expect(didCreateStudent == true)
        #expect(detailVM.enrolledStudents.count == 1)
        #expect(detailVM.totalAccruedAmount == 0)
        #expect(detailVM.totalOutstandingAmount == 0)
        let enrolledStudent = try #require(detailVM.enrolledStudents.first)

        // 3. Thiết lập lịch học theo tháng -> vẫn CHƯA phát sinh học phí trước khi hoàn thành buổi dạy
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startDate = cal.startOfDay(for: Date().addingTimeInterval(86400))
        let endDate = cal.date(byAdding: .day, value: 14, to: startDate)!
        var startComp = cal.dateComponents([.year, .month, .day], from: startDate)
        startComp.hour = 18
        startComp.minute = 30
        let sessionStartTime = cal.date(from: startComp) ?? startDate
        let sessionEndTime = sessionStartTime.addingTimeInterval(90 * 60)

        let createdSessionsCount = await detailVM.createMonthlySchedule(
            selectedDays: [.monday, .wednesday, .friday],
            startDate: startDate,
            endDate: endDate,
            sessionStartTime: sessionStartTime,
            sessionEndTime: sessionEndTime
        )
        #expect(createdSessionsCount >= 2)
        #expect(detailVM.classSessions.count == createdSessionsCount)
        #expect(detailVM.totalAccruedAmount == 0)

        // 4. Điểm danh có mặt và hoàn thành buổi đầu tiên -> phát sinh đúng 1 khoản phải thu 200.000đ
        let firstSession = try #require(detailVM.classSessions.first)
        let presentAttendance = AttendanceEntity(
            sessionId: firstSession.id,
            studentId: enrolledStudent.id,
            status: .present
        )
        try await scheduleRepo.saveAttendance(presentAttendance)

        let completedSession = try CompleteTeachingSessionUseCase().execute(
            session: firstSession,
            attendances: [presentAttendance],
            expectedStudentIds: [enrolledStudent.id]
        )
        try await scheduleRepo.saveSession(completedSession)

        let generatedCharges = GenerateSessionChargesUseCase().execute(
            session: completedSession,
            attendances: [presentAttendance],
            students: [enrolledStudent],
            classGroup: newClass,
            existingCharges: []
        )
        try await financeRepo.saveCharges(generatedCharges)

        await detailVM.loadMembers()
        #expect(detailVM.classSessions.filter { $0.status == .completed }.count == 1)
        #expect(detailVM.totalAccruedAmount == 200_000)
        #expect(detailVM.totalCollectedAmount == 0)
        #expect(detailVM.totalOutstandingAmount == 200_000)

        // 5. Ghi nhận thu học phí một phần (120.000đ) ngay trong Chi tiết lớp
        try await detailVM.recordPaymentForStudent(
            studentId: enrolledStudent.id,
            amount: 120_000,
            paidAt: Date(),
            paymentMethod: "Chuyển khoản",
            note: "Thu học phí đợt 1"
        )
        #expect(detailVM.totalAccruedAmount == 200_000)
        #expect(detailVM.totalCollectedAmount == 120_000)
        #expect(detailVM.totalOutstandingAmount == 80_000)

        // 6. Đổi đơn giá lớp từ 200.000đ lên 300.000đ -> khoản đã phát sinh (snapshot) và đã thu KHÔNG bị thay đổi
        var updatedClass = detailVM.classGroup
        updatedClass.defaultPricePerSession = 300_000
        try await classRepo.saveClass(updatedClass)
        await detailVM.loadMembers()
        #expect(detailVM.totalAccruedAmount == 200_000)
        #expect(detailVM.totalCollectedAmount == 120_000)
        #expect(detailVM.totalOutstandingAmount == 80_000)

        // 7. Lưu trữ và khôi phục lớp: giữ nguyên toàn bộ lịch sử học sinh, buổi dạy và tài chính
        await listVM.archiveClass(id: updatedClass.id)
        let archivedClasses = try await classRepo.fetchClasses(includeArchived: true)
        #expect(archivedClasses.first?.isArchived == true)
        #expect(try await financeRepo.fetchCharges().count == 1)
        #expect(try await financeRepo.fetchPayments().count == 1)
    }

    // MARK: - Workflow 4: Backup Export, JSON Serializability & Integrity Verification

    @Test("Workflow 4: Complete Data Backup Export -> JSON Verification -> Integrity Summary")
    func testBackupExportAndIntegrityWorkflow() throws {
        let student = StudentEntity(fullName: "Nguyễn Thu Hà")
        let classGroup = ClassGroupEntity(name: "Hóa học 11")
        let session = TeachingSessionEntity(classId: classGroup.id, title: "Liên kết cộng hóa trị", startTime: Date(), endTime: Date().addingTimeInterval(5400))
        let charge = ChargeEntity(sessionId: session.id, studentId: student.id, amount: 180_000, unitPriceSnapshot: 180_000)
        let payment = PaymentEntity(studentId: student.id, amount: 180_000)

        let backupService = BackupExportService()
        let jsonData = try backupService.exportToJSONData(
            teacherName: "Thầy Minh Huy",
            students: [student],
            classes: [classGroup],
            sessions: [session],
            charges: [charge],
            payments: [payment]
        )

        #expect(jsonData.count > 0)

        // Integrity verification
        let summary = try backupService.verifyBackupIntegrity(data: jsonData)
        #expect(summary.schemaVersion == "1.0.0")
        #expect(summary.studentsCount == 1)
        #expect(summary.classesCount == 1)
        #expect(summary.sessionsCount == 1)
        #expect(summary.chargesCount == 1)
        #expect(summary.paymentsCount == 1)
    }

    // MARK: - Workflow 5: End-to-End Recurring Schedule -> Attendance -> VietQR -> PDF Receipt -> Profile

    @Test("Workflow 5: Comprehensive Full-App Flow (Student -> Session -> Attendance -> VietQR -> Payment -> PDF Receipt)")
    func testComprehensiveAppWorkflow() throws {
        let studentId = UUID()
        let classId = UUID()
        let sessionId = UUID()

        // 1. Tạo học sinh và lớp
        let student = StudentEntity(
            id: studentId,
            fullName: "Trần Bảo Ngọc",
            phoneNumber: "0988776655",
            defaultPricePerSession: 220_000
        )
        let classGroup = ClassGroupEntity(
            id: classId,
            name: "Văn học 10 Ôn thi",
            subject: "Ngữ văn",
            defaultPricePerSession: 200_000
        )

        // 2. Tạo buổi học và điểm danh có mặt
        let session = TeachingSessionEntity(
            id: sessionId,
            classId: classId,
            title: "Phân tích bài thơ Tây Tiến",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .scheduled
        )
        let attendance = AttendanceEntity(
            sessionId: sessionId,
            studentId: studentId,
            status: .present,
            note: "Phát biểu tích cực"
        )

        // 3. Hoàn thành buổi học
        let completeUseCase = CompleteTeachingSessionUseCase()
        let completedSession = try completeUseCase.execute(
            session: session,
            attendances: [attendance],
            expectedStudentIds: [studentId]
        )
        #expect(completedSession.status == .completed)

        // 4. Phát sinh học phí snapshot
        let generateChargesUseCase = GenerateSessionChargesUseCase()
        let charges = generateChargesUseCase.execute(
            session: completedSession,
            attendances: [attendance],
            students: [student],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(charges.count == 1)
        #expect(charges.first?.amount == 220_000)

        // 5. Kiểm tra thống kê chuyên cần trong Student Profile
        let profileRecord = StudentAttendanceRecord(
            sessionDate: session.startTime,
            sessionTitle: session.title,
            status: attendance.status,
            notes: attendance.note
        )
        let attendancesList = [profileRecord]
        let presentCount = attendancesList.filter { $0.status == AttendanceStatus.present }.count
        let totalCount = attendancesList.count
        let rate = (Double(presentCount) / Double(totalCount)) * 100.0
        #expect(rate == 100.0)

        // 6. Sinh VietQR chuyển khoản
        let bankService = BankConfigService()
        let bankConfig = BankAccountConfig(
            bankCode: "VCB",
            accountNumber: "1234567890",
            accountHolderName: "NGUYEN VAN A"
        )
        let qrURL = bankService.generateVietQRURL(config: bankConfig, amount: 220_000, note: "Hoc phi Tran Bao Ngoc")
        #expect(qrURL != nil)
        #expect(qrURL?.absoluteString.contains("1234567890") == true)

        // 7. Ghi nhận thanh toán
        let recordPaymentUseCase = RecordPaymentUseCase()
        let paymentResult = try recordPaymentUseCase.execute(
            studentId: studentId,
            amount: 220_000,
            paymentMethod: "Chuyển khoản VietQR",
            note: "Phụ huynh chuyển qua VietQR",
            studentCharges: charges,
            existingAllocations: []
        )
        #expect(paymentResult.payment.amount == 220_000)
        #expect(paymentResult.updatedCharges.first?.status == .paid)

        // 8. Xuất hóa đơn / Biên nhận PDF
        let receiptRenderer = ReceiptPDFRenderer()
        let receiptData = try receiptRenderer.renderReceiptPDF(
            data: ReceiptPDFData(
                receiptCode: "EP-REC-001",
                teacherName: "Cô Thu Hà",
                studentName: student.fullName,
                amount: paymentResult.payment.amount,
                paidAt: paymentResult.payment.paidAt,
                paymentMethod: paymentResult.payment.paymentMethod,
                note: paymentResult.payment.note,
                remainingBalance: 0,
                items: [
                    (title: session.title, date: session.startTime, amount: 220_000)
                ]
            )
        )
        #expect(receiptData.count > 500)
    }

    // MARK: - Workflow 6: Google Login, Firebase Config & Strict Multi-User Session Isolation (Mục 8 & 9 /duan)

    /// Tạo một tệp PDF hợp lệ 1 trang để dùng cho kiểm thử cô lập tài liệu
    private func createSamplePDFFile(named fileName: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
        let renderer = ReceiptPDFRenderer()
        let pdfData = try renderer.renderReceiptPDF(
            data: ReceiptPDFData(
                receiptCode: "TEST-PDF",
                teacherName: "Giáo viên Kiểm thử",
                studentName: "Học sinh Mẫu",
                amount: 200_000,
                paidAt: Date(),
                paymentMethod: "Chuyển khoản",
                note: "Tài liệu PDF mẫu kiểm thử cô lập user",
                remainingBalance: 0,
                items: [(title: "Đề thi mẫu", date: Date(), amount: 200_000)]
            )
        )
        try pdfData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    @Test("Mục 8: Kiểm tra cấu hình GoogleService-Info.plist khớp BUNDLE_ID com.edupetal.app, không lộ API_KEY và xử lý Đăng nhập / Hủy / Khôi phục / Đăng xuất Google")
    func testFirebaseConfigAndGoogleAuthLifecycle() async throws {
        // 1. Kiểm tra FirebaseAuthConfigService
        let configResult = FirebaseAuthConfigService.shared.inspectConfiguration()
        #expect(configResult.isPlistFound == true)
        #expect(configResult.plistBundleId == "com.edupetal.app")
        #expect(configResult.expectedBundleId == "com.edupetal.app")
        #expect(configResult.isBundleIdMatched == true)
        #expect(configResult.projectId == "edupetal-b6641")
        #expect(configResult.isSignInEnabled == true)
        #expect(configResult.hasCallbackURLSchemeConfigured == true)
        // Đảm bảo thông điệp chẩn đoán không bao giờ chứa khóa bí mật AIza...
        #expect(!configResult.diagnosticMessage.contains("AIza"))

        // 2. Tạo UserSessionManager cô lập trên UserDefaults riêng để kiểm thử vòng đời phiên
        let suiteName = "com.edupetal.tests.auth.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let sessionManager = UserSessionManager(userDefaults: testDefaults)
        #expect(sessionManager.isAuthenticated == false)
        #expect(sessionManager.currentUser == nil)

        // 3. Người dùng bấm Hủy khi đang đăng nhập -> không báo lỗi giả, không tự chuyển sang khách
        sessionManager.handleSignInCancelled()
        #expect(sessionManager.isAuthenticated == false)
        #expect(sessionManager.authErrorMessage == nil)
        #expect(sessionManager.isAuthenticating == false)

        // 4. Đăng nhập Google thành công
        let userA = try await sessionManager.signInWithGoogle(
            email: "gv.toan.a@gmail.com",
            displayName: "Thầy Nguyễn Văn A",
            googleSubjectId: "109876543210"
        )
        #expect(sessionManager.isAuthenticated == true)
        #expect(userA.provider == .google)
        #expect(userA.userId == "google_109876543210")
        #expect(sessionManager.currentOwnerId == "google_109876543210")
        #expect(sessionManager.savedGoogleAccounts.count == 1)

        // 5. Mô phỏng tắt và mở lại ứng dụng: Khôi phục phiên đăng nhập từ bộ nhớ
        let restartedSessionManager = UserSessionManager(userDefaults: testDefaults)
        #expect(restartedSessionManager.isAuthenticated == true)
        #expect(restartedSessionManager.currentUser?.userId == "google_109876543210")
        #expect(restartedSessionManager.currentUser?.email == "gv.toan.a@gmail.com")

        // 6. Đăng xuất: xóa phiên hiện tại, đổi sessionToken mới, không tự đăng nhập khách
        let tokenBeforeSignOut = restartedSessionManager.currentSessionToken
        await restartedSessionManager.signOut()
        #expect(restartedSessionManager.isAuthenticated == false)
        #expect(restartedSessionManager.currentUser == nil)
        #expect(restartedSessionManager.currentSessionToken != tokenBeforeSignOut)
    }

    @Test("Mục 9 (Kịch bản 1, 2, 3, 4): Cô lập dữ liệu tuyệt đối giữa User A và User B khi chuyển tài khoản, khởi động lại app và đăng nhập lại")
    @MainActor
    func testMultiUserDatabaseAndFileIsolationAcrossSessions() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let suiteName = "com.edupetal.tests.isolation.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let sessionManager = UserSessionManager(userDefaults: testDefaults)
        let photoStorage = PhotoStorageService(sessionManager: sessionManager)
        let avatarStorage = AvatarStorageService(sessionManager: sessionManager)

        // --- BƯỚC 1: Đăng nhập User A (Google) và tạo dữ liệu trên toàn bộ các phân hệ ---
        let userA = try await sessionManager.signInWithGoogle(
            email: "teacher.a@gmail.com",
            displayName: "Cô Giáo A",
            googleSubjectId: "sub_user_a_001"
        )
        let ownerA = userA.userId

        let studentRepoA = StudentRepository(modelContext: context, ownerId: ownerA)
        let classRepoA = ClassRepository(modelContext: context, ownerId: ownerA)
        let scheduleRepoA = ScheduleRepository(modelContext: context, ownerId: ownerA)
        let financeRepoA = FinanceRepository(modelContext: context, ownerId: ownerA)
        let assignmentRepoA = AssignmentRepository(modelContext: context, ownerId: ownerA)
        let gradeRepoA = GradeRepository(modelContext: context, ownerId: ownerA)

        // Lưu avatar cho học sinh của User A
        let avatarPathA = try avatarStorage.saveAvatarData(Data([0xFF, 0xD8, 0xFF, 0xD9]), prefix: "studentA")
        #expect(avatarPathA.hasPrefix("\(ownerA)/"))

        let studentA = StudentEntity(
            fullName: "Học Sinh Của Cô A",
            phoneNumber: "0901112222",
            defaultPricePerSession: 250_000,
            avatarPath: avatarPathA
        )
        try await studentRepoA.saveStudent(studentA)

        let classA = ClassGroupEntity(
            name: "Toán 12 Cô A",
            subject: "Toán",
            defaultPricePerSession: 250_000
        )
        try await classRepoA.saveClass(classA)

        // Lưu ảnh minh chứng buổi học của User A
        let sessionAId = UUID()
        let photoPathA = try await photoStorage.savePhotoData(
            Data("photo-proof-user-a".utf8),
            forSessionId: sessionAId
        )
        #expect(photoPathA.hasPrefix("\(ownerA)/"))

        let sessionA = TeachingSessionEntity(
            id: sessionAId,
            classId: classA.id,
            title: "Buổi 1 Hàm Số Cô A",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .completed
        )
        try await scheduleRepoA.saveSession(sessionA)
        try await scheduleRepoA.addAttachment(
            SessionAttachmentEntity(
                sessionId: sessionAId,
                filePath: photoPathA,
                fileType: "image",
                caption: "Ảnh minh chứng lớp Cô A"
            )
        )

        // Lưu học phí & thanh toán của User A
        let chargeA = ChargeEntity(
            sessionId: sessionA.id,
            studentId: studentA.id,
            amount: 250_000,
            unitPriceSnapshot: 250_000,
            status: .paid
        )
        try await financeRepoA.saveCharges([chargeA])

        let paymentA = PaymentEntity(
            studentId: studentA.id,
            amount: 250_000,
            paymentMethod: "Chuyển khoản VietQR",
            note: "Học phí tháng 11 Cô A"
        )
        try await financeRepoA.savePayment(paymentA)

        // Lưu bài tập & điểm số của User A
        let assignmentA = AssignmentEntity(
            classId: classA.id,
            title: "Bài tập Đạo hàm Cô A",
            dueDate: Date().addingTimeInterval(86400)
        )
        try await assignmentRepoA.saveAssignment(assignmentA)

        let assessmentA = AssessmentEntity(
            classId: classA.id,
            title: "Kiểm tra 15p Cô A",
            maxScore: 10.0,
            weight: 1.0
        )
        try await gradeRepoA.saveAssessment(assessmentA)

        // Xác nhận User A đọc được đầy đủ dữ liệu của mình
        #expect(try await studentRepoA.fetchStudents(includeArchived: true).count == 1)
        #expect(try await classRepoA.fetchClasses(includeArchived: true).count == 1)
        #expect(try await scheduleRepoA.fetchSessionsForClass(classId: classA.id).count == 1)
        #expect(try await financeRepoA.fetchCharges().count == 1)
        #expect(try await financeRepoA.fetchPayments().count == 1)

        // --- BƯỚC 2: Đăng xuất User A và đăng nhập User B (Google) ---
        await sessionManager.signOut()
        let userB = try await sessionManager.signInWithGoogle(
            email: "teacher.b@gmail.com",
            displayName: "Thầy Giáo B",
            googleSubjectId: "sub_user_b_002"
        )
        let ownerB = userB.userId
        #expect(ownerB != ownerA)

        let studentRepoB = StudentRepository(modelContext: context, ownerId: ownerB)
        let classRepoB = ClassRepository(modelContext: context, ownerId: ownerB)
        let scheduleRepoB = ScheduleRepository(modelContext: context, ownerId: ownerB)
        let financeRepoB = FinanceRepository(modelContext: context, ownerId: ownerB)
        let assignmentRepoB = AssignmentRepository(modelContext: context, ownerId: ownerB)
        let gradeRepoB = GradeRepository(modelContext: context, ownerId: ownerB)

        // User B tuyệt đối không nhìn thấy bất kỳ dữ liệu nào của User A
        #expect(try await studentRepoB.fetchStudents(includeArchived: true).isEmpty)
        #expect(try await classRepoB.fetchClasses(includeArchived: true).isEmpty)
        #expect(try await scheduleRepoB.fetchSessionsForClass(classId: classA.id).isEmpty)
        #expect(try await financeRepoB.fetchCharges().isEmpty)
        #expect(try await financeRepoB.fetchPayments().isEmpty)
        #expect(try await assignmentRepoB.fetchAssignments(forClassId: classA.id).isEmpty)
        #expect(try await gradeRepoB.fetchAssessments(forClassId: classA.id).isEmpty)

        // --- BƯỚC 3: Khởi động lại ứng dụng ở phiên của User B -> vẫn không thấy dữ liệu của User A ---
        sessionManager.restoreSession()
        #expect(sessionManager.currentOwnerId == ownerB)
        #expect(try await studentRepoB.fetchStudents(includeArchived: true).isEmpty)

        // User B tạo 1 học sinh riêng của User B
        let studentB = StudentEntity(
            fullName: "Học Sinh Của Thầy B",
            phoneNumber: "0909998888",
            defaultPricePerSession: 300_000
        )
        try await studentRepoB.saveStudent(studentB)
        #expect(try await studentRepoB.fetchStudents(includeArchived: true).count == 1)

        // --- BƯỚC 4: Đăng xuất User B, đăng nhập lại User A -> toàn bộ dữ liệu và file của User A còn nguyên vẹn 100%, không lẫn dữ liệu của User B ---
        await sessionManager.signOut()
        let reloginA = try await sessionManager.signInWithGoogle(
            email: "teacher.a@gmail.com",
            displayName: "Cô Giáo A",
            googleSubjectId: "sub_user_a_001"
        )
        #expect(reloginA.userId == ownerA)

        let studentsOfA = try await studentRepoA.fetchStudents(includeArchived: true)
        #expect(studentsOfA.count == 1)
        #expect(studentsOfA.first?.fullName == "Học Sinh Của Cô A")
        #expect(try await classRepoA.fetchClasses(includeArchived: true).count == 1)
        #expect(try await scheduleRepoA.fetchSessionsForClass(classId: classA.id).count == 1)
        #expect(try await financeRepoA.fetchCharges().count == 1)
        #expect(try await financeRepoA.fetchPayments().count == 1)

        // Ảnh minh chứng buổi học và avatar của User A đều đọc lại được bình thường
        #expect(try photoStorage.verifyAndLoadPhotoData(named: photoPathA).count > 0)
        #expect(avatarStorage.avatarFileExists(named: avatarPathA) == true)

        // Dọn dẹp file test trong thư mục của User A
        photoStorage.deleteImage(named: photoPathA)
        avatarStorage.deleteAvatar(named: avatarPathA)
    }

    @Test("Mục 9 (Kịch bản 5 & 6): Chặn tác vụ bất đồng bộ khi đổi tài khoản giữa chừng và chặn truy cập/sửa/xóa trái phép tài liệu hoặc bản ghi của User A từ phiên User B")
    @MainActor
    func testAsyncTaskGuardAndCrossUserAccessDenial() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let suiteName = "com.edupetal.tests.guard.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let sessionManager = UserSessionManager(userDefaults: testDefaults)
        let photoStorage = PhotoStorageService(sessionManager: sessionManager)

        // 1. Đăng nhập User A và tạo dữ liệu + ảnh minh chứng
        let userA = try await sessionManager.signInWithGoogle(
            email: "user.a@gmail.com",
            displayName: "User A",
            googleSubjectId: "guard_user_a"
        )
        let studentRepoA = StudentRepository(modelContext: context, ownerId: userA.userId)
        let classRepoA = ClassRepository(modelContext: context, ownerId: userA.userId)

        let studentA = StudentEntity(fullName: "Học sinh A", defaultPricePerSession: 200_000, ownerId: userA.userId)
        try await studentRepoA.saveStudent(studentA)

        let classA = ClassGroupEntity(name: "Lớp của User A", subject: "Vật lý", defaultPricePerSession: 200_000, ownerId: userA.userId)
        try await classRepoA.saveClass(classA)

        let photoPathA = try await photoStorage.savePhotoData(Data("photo-a".utf8), forSessionId: UUID())

        // Chụp lại ngữ cảnh phiên làm việc của User A trước khi bắt đầu một tác vụ bất đồng bộ mới
        let capturedContextA = sessionManager.captureSessionContext()

        // 2. Chuyển sang phiên của User B trong khi tác vụ bất đồng bộ của User A chưa kịp hoàn tất
        let userB = try await sessionManager.signInWithGoogle(
            email: "user.b@gmail.com",
            displayName: "User B",
            googleSubjectId: "guard_user_b"
        )
        #expect(sessionManager.currentOwnerId == userB.userId)

        // Kịch bản 5: Tác vụ lưu ảnh minh chứng với ngữ cảnh cũ của User A phải bị từ chối và dọn file tạm
        var didThrowAsyncSessionChangedForPhoto = false
        do {
            _ = try await photoStorage.savePhotoData(
                Data("orphan-photo".utf8),
                forSessionId: UUID(),
                expectedSessionContext: capturedContextA
            )
        } catch let error as SessionIsolationError {
            if case .sessionChangedDuringAsyncTask(let expected, let current) = error {
                #expect(expected == userA.userId)
                #expect(current == userB.userId)
                didThrowAsyncSessionChangedForPhoto = true
            }
        }
        #expect(didThrowAsyncSessionChangedForPhoto == true)

        // Kịch bản 6a: Đang ở phiên User B, cố tình đọc/xóa ảnh của User A qua đường dẫn cũ đều bị chặn
        var didBlockDirectPhotoRead = false
        do {
            _ = try photoStorage.verifyAndLoadPhotoData(named: photoPathA)
        } catch is SessionIsolationError {
            didBlockDirectPhotoRead = true
        }
        #expect(didBlockDirectPhotoRead == true)

        // Cố tình gọi xóa file của User A khi đang ở phiên User B -> bị chặn, file của User A vẫn an toàn
        photoStorage.deleteImage(named: photoPathA)

        // Kịch bản 6b: Đang ở phiên User B, cố tình ghi đè hoặc xóa bản ghi SwiftData của User A phải bị từ chối
        let studentRepoB = StudentRepository(modelContext: context, ownerId: userB.userId)
        let classRepoB = ClassRepository(modelContext: context, ownerId: userB.userId)

        var didBlockCrossUserStudentUpdate = false
        do {
            try await studentRepoB.saveStudent(studentA)
        } catch is SessionIsolationError {
            didBlockCrossUserStudentUpdate = true
        }
        #expect(didBlockCrossUserStudentUpdate == true)

        var didBlockCrossUserClassDelete = false
        do {
            try await classRepoB.deleteClass(id: classA.id)
        } catch is SessionIsolationError {
            didBlockCrossUserClassDelete = true
        }
        #expect(didBlockCrossUserClassDelete == true)

        // Đăng nhập lại User A để kiểm chứng file và bản ghi của User A vẫn nguyên vẹn 100%
        _ = try await sessionManager.signInWithGoogle(
            email: "user.a@gmail.com",
            displayName: "User A",
            googleSubjectId: "guard_user_a"
        )
        #expect(try photoStorage.verifyAndLoadPhotoData(named: photoPathA).count > 0)
        #expect(try await studentRepoA.fetchStudent(byId: studentA.id)?.fullName == "Học sinh A")
        #expect(try await classRepoA.fetchClass(byId: classA.id)?.name == "Lớp của User A")

        photoStorage.deleteImage(named: photoPathA)
    }

    @Test("Mục 9 (Kịch bản 7): Dữ liệu cũ chưa có ownerId không tự động gán bừa cho user mới và không gộp tài khoản khác phương thức dù trùng email")
    @MainActor
    func testLegacyUnownedDataMigrationAndProviderSeparation() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // 1. Tạo dữ liệu cũ thời chưa có đăng nhập (`ownerId == ""`) trực tiếp trong SwiftData
        let legacyStudent = StudentModel(
            fullName: "Học Sinh Dữ Liệu Cũ",
            phoneNumber: "0911000111",
            defaultPricePerSession: 180_000,
            ownerId: ""
        )
        let legacyClass = ClassGroupModel(
            name: "Lớp Dữ Liệu Cũ",
            subject: "Hóa học",
            defaultPricePerSession: 180_000,
            ownerId: ""
        )
        context.insert(legacyStudent)
        context.insert(legacyClass)
        try context.save()

        // Kiểm tra LegacyDataMigrationService phát hiện đúng 2 bản ghi chưa có chủ sở hữu
        let migrationService = LegacyDataMigrationService.shared
        #expect(migrationService.countUnownedRecords(in: context) == 2)

        // 2. User A đăng nhập bằng Google với email `same.teacher@gmail.com`
        let suiteName = "com.edupetal.tests.legacy.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        let sessionManager = UserSessionManager(userDefaults: testDefaults)

        let googleUser = try await sessionManager.signInWithGoogle(
            email: "same.teacher@gmail.com",
            displayName: "Cô Giáo Google",
            googleSubjectId: "google_sub_999"
        )

        // Trước khi xác nhận chuyển dữ liệu cũ, User A tuyệt đối không tự động thấy dữ liệu `ownerId == ""`
        let studentRepoGoogle = StudentRepository(modelContext: context, ownerId: googleUser.userId)
        let classRepoGoogle = ClassRepository(modelContext: context, ownerId: googleUser.userId)
        #expect(try await studentRepoGoogle.fetchStudents(includeArchived: true).isEmpty)
        #expect(try await classRepoGoogle.fetchClasses(includeArchived: true).isEmpty)

        // 3. Khi người dùng chủ động xác nhận chuyển dữ liệu cũ vào tài khoản Google hiện tại
        let migratedCount = try migrationService.claimUnownedData(forOwnerId: googleUser.userId, in: context)
        #expect(migratedCount == 2)
        #expect(migrationService.countUnownedRecords(in: context) == 0)

        // Giờ đây User A (Google) nhìn thấy đúng dữ liệu đã nhận quyền sở hữu
        #expect(try await studentRepoGoogle.fetchStudents(includeArchived: true).count == 1)
        #expect(try await classRepoGoogle.fetchClasses(includeArchived: true).count == 1)

        // 4. Không tự gộp tài khoản chỉ vì trùng email giữa Google và Apple (`google_...` khác hoàn toàn `apple_...`)
        let appleOwnerId = "apple_sub_999"
        #expect(googleUser.userId != appleOwnerId)

        let studentRepoApple = StudentRepository(modelContext: context, ownerId: appleOwnerId)
        let classRepoApple = ClassRepository(modelContext: context, ownerId: appleOwnerId)
        #expect(try await studentRepoApple.fetchStudents(includeArchived: true).isEmpty)
        #expect(try await classRepoApple.fetchClasses(includeArchived: true).isEmpty)
    }

    @Test("Mục 8 & 9: Google OAuth (ASWebAuthenticationSession select_account) và Apple / iOS Sign-In lưu bền vững họ tên/email lần đầu + cô lập dữ liệu tuyệt đối")
    @MainActor
    func testGoogleOAuthWebFlowAndAppleSignInIsolation() async throws {
        // 1. Kiểm tra tạo URL Google OAuth có prompt=select_account và scheme app-1-...
        if let runtimeConfig = FirebaseAuthConfigService.shared.loadRuntimeOAuthConfig() {
            #expect(runtimeConfig.encodedAppScheme == "app-1-491580800757-ios-fe0f62fbc34298d9ba4fbc")
            let handlerURL = GoogleOAuthService.buildFirebaseOAuthHandlerURL(
                config: runtimeConfig,
                sessionId: "test_session_123",
                eventId: "test_event_456"
            )
            #expect(handlerURL != nil)
            let urlStr = handlerURL?.absoluteString ?? ""
            #expect(urlStr.contains("edupetal-b6641.firebaseapp.com/__/auth/handler"))
            #expect(urlStr.contains("providerId=google.com"))
            #expect(urlStr.contains("select_account"))
        }

        // 2. Kiểm tra giải mã callback trực tiếp (bắt trước khi firebaseapp.com/__/auth/handler chạy sessionStorage), kiểm tra CSRF state và callback deep_link_id
        let directCallbackURL = URL(string: "https://edupetal-b6641.firebaseapp.com/__/auth/handler?state=abc&code=xyz&scope=email+profile+openid")!
        try GoogleOAuthService.verifyOAuthState(expectedState: "abc", callbackURL: directCallbackURL)
        var didDetectTamperedState = false
        do {
            try GoogleOAuthService.verifyOAuthState(expectedState: "abc", callbackURL: URL(string: "https://edupetal-b6641.firebaseapp.com/__/auth/handler?state=wrong_state&code=xyz")!)
        } catch let error as GoogleOAuthError {
            if case .stateMismatch = error {
                didDetectTamperedState = true
            }
        }
        #expect(didDetectTamperedState == true)

        let directExtractedURI = try GoogleOAuthService.extractOAuthRequestURI(from: directCallbackURL)
        #expect(directExtractedURI == "https://edupetal-b6641.firebaseapp.com/__/auth/handler?state=abc&code=xyz&scope=email+profile+openid")

        let innerCallback = "https://edupetal-b6641.firebaseapp.com/__/auth/callback?authType=signInWithRedirect&link=https%3A%2F%2Fedupetal-b6641.firebaseapp.com%2F__%2Fauth%2Fhandler%3Fstate%3Dabc%26code%3Dxyz"
        var comps = URLComponents(string: "app-1-491580800757-ios-fe0f62fbc34298d9ba4fbc://firebaseauth/link")!
        comps.queryItems = [URLQueryItem(name: "deep_link_id", value: innerCallback)]
        let extractedURI = try GoogleOAuthService.extractOAuthRequestURI(from: comps.url!)
        #expect(extractedURI == "https://edupetal-b6641.firebaseapp.com/__/auth/handler?state=abc&code=xyz")

        // 3. Kiểm tra Sign in with Apple: Lần đầu trả (userIdentifier, email, displayName), lần sau chỉ trả userIdentifier vẫn giữ nguyên họ tên & email
        let suiteName = "com.edupetal.tests.apple.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        let sessionManager = UserSessionManager(userDefaults: testDefaults)

        let appleFirstLogin = try await sessionManager.signInWithApple(
            appleUserIdentifier: "001988.abcdef123456.0912",
            email: "minhhuy.ios@icloud.com",
            displayName: "Thầy Minh Huy (iOS)"
        )
        #expect(appleFirstLogin.provider == .apple)
        #expect(appleFirstLogin.userId == "apple_001988_abcdef123456_0912")
        #expect(appleFirstLogin.email == "minhhuy.ios@icloud.com")
        #expect(appleFirstLogin.displayName == "Thầy Minh Huy (iOS)")
        #expect(sessionManager.savedAppleAccounts.count == 1)

        // Đăng xuất và đăng nhập lại bằng Apple lần 2 (Apple chỉ trả userIdentifier, email = nil, displayName = nil)
        await sessionManager.signOut()
        let appleSecondLogin = try await sessionManager.signInWithApple(
            appleUserIdentifier: "001988.abcdef123456.0912",
            email: nil,
            displayName: nil
        )
        #expect(appleSecondLogin.userId == "apple_001988_abcdef123456_0912")
        #expect(appleSecondLogin.email == "minhhuy.ios@icloud.com")
        #expect(appleSecondLogin.displayName == "Thầy Minh Huy (iOS)")
    }

    // MARK: - 14. Regression Test chống Deadlock 0x8BADF00D (ObservationRegistrar vs NSLock)
    @Test("Không xảy ra AB-BA Deadlock 0x8BADF00D khi SwiftUI ObservationTracking đọc isAuthenticated/currentOwnerId đồng thời với đăng nhập Apple/Google và chuyển ngôn ngữ")
    func testNoDeadlockBetweenObservationTrackingAndSessionTransitions() async throws {
        let suiteName = "com.edupetal.tests.deadlock.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        let sessionManager = UserSessionManager(userDefaults: testDefaults)

        await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: Mô phỏng SwiftUI ViewBodyAccessor liên tục đăng ký ObservationTracking trên MainActor
            group.addTask { @MainActor in
                for _ in 0..<150 {
                    _ = withObservationTracking {
                        let auth = sessionManager.isAuthenticated
                        let owner = sessionManager.currentOwnerId
                        let gen = sessionManager.sessionGeneration
                        let appleCount = sessionManager.savedAppleAccounts.count
                        let googleCount = sessionManager.savedGoogleAccounts.count
                        let text = L("Tổng quan", "Overview")
                        return (auth, owner, gen, appleCount, googleCount, text)
                    } onChange: {
                        // Mô phỏng ObservationCenter.invalidate đọc lại currentOwnerId
                        _ = sessionManager.currentOwnerId
                    }
                    await Task.yield()
                }
            }

            // Task 2: Liên tục đăng nhập Apple / Google / Guest và đăng xuất
            group.addTask {
                for i in 0..<50 {
                    _ = try await sessionManager.signInWithApple(
                        appleUserIdentifier: "apple.stress.\(i % 5)",
                        email: "teacher\(i % 5)@icloud.com",
                        displayName: "Teacher \(i)"
                    )
                    _ = sessionManager.captureSessionContext()
                    _ = try await sessionManager.signInWithGoogle(
                        email: "teacher\(i % 5)@gmail.com",
                        displayName: "Google Teacher \(i)",
                        googleSubjectId: "g_sub_\(i % 5)"
                    )
                    await sessionManager.signOut()
                }
            }

            // Task 3: Các tác vụ nền liên tục đọc currentOwnerId, captureSessionContext và dịch chuỗi L(...)
            group.addTask {
                for _ in 0..<150 {
                    let ctx = sessionManager.captureSessionContext()
                    _ = sessionManager.currentOwnerId
                    _ = try? sessionManager.validateSessionContext(ctx)
                    _ = L("Học phí", "Tuition")
                    await Task.yield()
                }
            }

            while let _ = try? await group.next() {}
        }

        // Sau khi kết thúc vòng lặp đồng thời, xác nhận phiên có thể đăng nhập lại bình thường
        let finalUser = try await sessionManager.signInWithApple(
            appleUserIdentifier: "apple.final.check",
            email: "final@icloud.com",
            displayName: "Final Check"
        )
        #expect(sessionManager.isAuthenticated == true)
        #expect(sessionManager.currentOwnerId == finalUser.userId)

        // Xác nhận tài khoản demo cũ (apple_ios_... / appleid@icloud.com) bị tự động loại bỏ khi restoreSession
        let fakeDemoUser = AuthenticatedUser(
            userId: "apple_ios_fake123456",
            provider: .apple,
            email: "appleid@icloud.com",
            displayName: "Demo Apple",
            signedInAt: Date()
        )
        if let encodedFake = try? JSONEncoder().encode(fakeDemoUser) {
            testDefaults.set(encodedFake, forKey: "EduPetal_ActiveAuthenticatedUser_V1")
        }
        let restoredAfterPurge = sessionManager.restoreSession()
        #expect(restoredAfterPurge == nil)
        #expect(sessionManager.isAuthenticated == false)
    }
}
