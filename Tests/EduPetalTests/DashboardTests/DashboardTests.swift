import Testing
import Foundation
import SwiftData
@testable import EduPetal

@Suite("Dashboard & Analytics Metrics Test Suite")
struct DashboardTests {

    private let useCase = CalculateDashboardMetricsUseCase()

    // MARK: - 1. Greeting Tests

    @Test("Greeting adapts properly to morning, afternoon, and evening hours")
    func testGreetingTimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)! // Vietnam GMT+7

        // 8:00 AM -> Morning
        var morningComponents = DateComponents()
        morningComponents.year = 2026
        morningComponents.month = 11
        morningComponents.day = 4
        morningComponents.hour = 8
        let morningDate = calendar.date(from: morningComponents)!
        #expect(useCase.greeting(for: morningDate, calendar: calendar).contains("Chào buổi sáng"))

        // 2:00 PM (14:00) -> Afternoon
        var afternoonComponents = morningComponents
        afternoonComponents.hour = 14
        let afternoonDate = calendar.date(from: afternoonComponents)!
        #expect(useCase.greeting(for: afternoonDate, calendar: calendar).contains("Chào buổi chiều"))

        // 8:00 PM (20:00) -> Evening
        var eveningComponents = morningComponents
        eveningComponents.hour = 20
        let eveningDate = calendar.date(from: eveningComponents)!
        #expect(useCase.greeting(for: eveningDate, calendar: calendar).contains("Chào buổi tối"))

        // 2:00 AM -> Evening / Night
        var lateNightComponents = morningComponents
        lateNightComponents.hour = 2
        let lateNightDate = calendar.date(from: lateNightComponents)!
        #expect(useCase.greeting(for: lateNightDate, calendar: calendar).contains("Chào buổi tối"))
    }

    // MARK: - 2. Active Student & Class Counts

    @Test("Archived students and classes are excluded from active dashboard counters")
    func testActiveStudentsAndClassesFiltering() {
        let students = [
            StudentEntity(fullName: "Học sinh 1", isArchived: false),
            StudentEntity(fullName: "Học sinh 2", isArchived: false),
            StudentEntity(fullName: "Học sinh 3 đã lưu trữ", isArchived: true)
        ]

        let classes = [
            ClassGroupEntity(name: "Lớp Toán 12", isArchived: false),
            ClassGroupEntity(name: "Lớp Lý 10 đã lưu trữ", isArchived: true)
        ]

        let metrics = useCase.execute(
            students: students,
            classes: classes,
            sessions: [],
            records: [],
            charges: [],
            payments: []
        )

        #expect(metrics.activeStudentsCount == 2)
        #expect(metrics.activeClassesCount == 1)
    }

    // MARK: - 3. Today's Agenda & Completion Counters

    @Test("Today's sessions accurately isolate sessions happening today and compute completion progress")
    func testTodaySessionsFilteringAndCompletion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let session1Start = todayStart.addingTimeInterval(3600 * 9) // 9:00 AM today
        let session2Start = todayStart.addingTimeInterval(3600 * 14) // 2:00 PM today
        let yesterdayStart = todayStart.addingTimeInterval(-86400) // yesterday
        let tomorrowStart = todayStart.addingTimeInterval(86400) // tomorrow

        let s1 = TeachingSessionEntity(classId: UUID(), title: "Toán 12", startTime: session1Start, endTime: session1Start.addingTimeInterval(5400), status: .completed)
        let s2 = TeachingSessionEntity(classId: UUID(), title: "Lý 11", startTime: session2Start, endTime: session2Start.addingTimeInterval(5400), status: .scheduled)
        let sYesterday = TeachingSessionEntity(classId: UUID(), title: "Hóa 10", startTime: yesterdayStart, endTime: yesterdayStart.addingTimeInterval(5400), status: .completed)
        let sTomorrow = TeachingSessionEntity(classId: UUID(), title: "Văn 12", startTime: tomorrowStart, endTime: tomorrowStart.addingTimeInterval(5400), status: .scheduled)

        let metrics = useCase.execute(
            students: [],
            classes: [],
            sessions: [s1, s2, sYesterday, sTomorrow],
            records: [],
            charges: [],
            payments: [],
            now: now,
            calendar: calendar
        )

        #expect(metrics.todaySessions.count == 2)
        #expect(metrics.todayTotalSessionsCount == 2)
        #expect(metrics.todayCompletedSessionsCount == 1)
        #expect(metrics.todaySessions.map(\.title).contains("Toán 12"))
        #expect(metrics.todaySessions.map(\.title).contains("Lý 11"))
    }

    // MARK: - 4. Pending Action Items

    @Test("Pending grading assignments counter only includes submitted records")
    func testPendingGradingCounter() {
        let r1 = AssignmentRecordEntity(assignmentId: UUID(), studentId: UUID(), status: .submitted)
        let r2 = AssignmentRecordEntity(assignmentId: UUID(), studentId: UUID(), status: .submitted)
        let r3 = AssignmentRecordEntity(assignmentId: UUID(), studentId: UUID(), status: .graded)
        let r4 = AssignmentRecordEntity(assignmentId: UUID(), studentId: UUID(), status: .inProgress)
        let r5 = AssignmentRecordEntity(assignmentId: UUID(), studentId: UUID(), status: .notStarted)

        let metrics = useCase.execute(
            students: [],
            classes: [],
            sessions: [],
            records: [r1, r2, r3, r4, r5],
            charges: [],
            payments: []
        )

        #expect(metrics.pendingGradingAssignmentsCount == 2)
    }

    @Test("Overdue sessions counter detects scheduled sessions whose endTime is in the past")
    func testPendingCompletionSessionsOverdue() {
        let now = Date()
        let pastSessionOverdue = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi học sáng nay đã hết giờ nhưng chưa hoàn thành",
            startTime: now.addingTimeInterval(-7200),
            endTime: now.addingTimeInterval(-1800),
            status: .scheduled
        )

        let pastSessionCompleted = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi học sáng nay đã hoàn thành",
            startTime: now.addingTimeInterval(-7200),
            endTime: now.addingTimeInterval(-1800),
            status: .completed
        )

        let futureSession = TeachingSessionEntity(
            classId: UUID(),
            title: "Buổi học chiều nay",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200),
            status: .scheduled
        )

        let metrics = useCase.execute(
            students: [],
            classes: [],
            sessions: [pastSessionOverdue, pastSessionCompleted, futureSession],
            records: [],
            charges: [],
            payments: [],
            now: now
        )

        #expect(metrics.pendingCompletionSessionsCount == 1)
    }

    @Test("Students with outstanding tuition counter calculates active students with remaining balance")
    func testStudentsWithOutstandingTuition() {
        let s1Id = UUID()
        let s2Id = UUID()
        let s3Id = UUID()

        let s1 = StudentEntity(id: s1Id, fullName: "Học sinh nợ tiền")
        let s2 = StudentEntity(id: s2Id, fullName: "Học sinh đã trả hết")
        let s3 = StudentEntity(id: s3Id, fullName: "Học sinh chưa có buổi học nào")

        let charges = [
            ChargeEntity(sessionId: UUID(), studentId: s1Id, amount: 400_000, unitPriceSnapshot: 400_000),
            ChargeEntity(sessionId: UUID(), studentId: s2Id, amount: 300_000, unitPriceSnapshot: 300_000)
        ]

        let payments = [
            PaymentEntity(studentId: s1Id, amount: 200_000), // nợ 200k
            PaymentEntity(studentId: s2Id, amount: 300_000)  // nợ 0
        ]

        let metrics = useCase.execute(
            students: [s1, s2, s3],
            classes: [],
            sessions: [],
            records: [],
            charges: charges,
            payments: payments
        )

        #expect(metrics.studentsWithOutstandingTuitionCount == 1)
        #expect(metrics.financeSummary.accruedTuition == 700_000)
        #expect(metrics.financeSummary.collectedTuition == 500_000)
        #expect(metrics.financeSummary.outstandingBalance == 200_000)
    }

    @Test("Trải nghiệm người dùng lần đầu (3 bước: Tạo lớp -> Thêm học sinh -> Lên lịch buổi đầu): dẫn bước tiếp theo, cho phép bỏ qua theo tài khoản và không tự chèn dữ liệu demo")
    @MainActor
    func testFirstTimeSetupFlow_ThreeSteps_GuidesNextStep_SkippablePerOwner_AndNeverInjectsDemoData() async throws {
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
        let ownerA = "step5_first_time_ownerA_\(UUID().uuidString)"
        let ownerB = "step5_first_time_ownerB_\(UUID().uuidString)"

        let sRepoA = StudentRepository(modelContext: container.mainContext, ownerId: ownerA)
        let cRepoA = ClassRepository(modelContext: container.mainContext, ownerId: ownerA)
        let schRepoA = ScheduleRepository(modelContext: container.mainContext, ownerId: ownerA)
        let fRepoA = FinanceRepository(modelContext: container.mainContext, ownerId: ownerA)

        let vmA = HomeViewModel(
            studentRepository: sRepoA,
            classRepository: cRepoA,
            scheduleRepository: schRepoA,
            financeRepository: fRepoA,
            explicitOwnerId: ownerA
        )
        await vmA.loadDashboard()

        // 0. Tài khoản mới hoàn toàn trống (không tự thêm dữ liệu demo) và ở Bước 1: Tạo lớp
        #expect(vmA.classes.isEmpty)
        #expect(vmA.students.isEmpty)
        #expect(vmA.sessions.isEmpty)
        #expect(vmA.currentFirstTimeStep == .createClass)
        #expect(vmA.completedFirstTimeStepsCount == 0)
        #expect(vmA.shouldShowFirstTimeGuide == true)

        // Cho phép bỏ qua hướng dẫn theo đúng tài khoản ownerA, không ảnh hưởng ownerB
        vmA.dismissFirstTimeGuide()
        #expect(vmA.isFirstTimeGuideDismissed == true)
        #expect(vmA.shouldShowFirstTimeGuide == false)

        let sRepoB = StudentRepository(modelContext: container.mainContext, ownerId: ownerB)
        let cRepoB = ClassRepository(modelContext: container.mainContext, ownerId: ownerB)
        let schRepoB = ScheduleRepository(modelContext: container.mainContext, ownerId: ownerB)
        let vmB = HomeViewModel(
            studentRepository: sRepoB,
            classRepository: cRepoB,
            scheduleRepository: schRepoB,
            explicitOwnerId: ownerB
        )
        await vmB.loadDashboard()
        #expect(vmB.isFirstTimeGuideDismissed == false)
        #expect(vmB.shouldShowFirstTimeGuide == true)

        // Khôi phục lại hướng dẫn cho ownerA và đi qua 3 bước liên hoàn
        vmA.restoreFirstTimeGuide()
        #expect(vmA.shouldShowFirstTimeGuide == true)

        // Bước 1: Tạo lớp -> tự động chuyển sang Bước 2 (Thêm học sinh)
        let firstClass = ClassGroupEntity(name: "Toán 9 Cơ Bản", defaultPricePerSession: 150_000)
        let savedClass = await vmA.createClassFromGuide(firstClass)
        #expect(savedClass == true)
        #expect(vmA.currentFirstTimeStep == .addStudent)
        #expect(vmA.completedFirstTimeStepsCount == 1)

        // Bước 2: Thêm học sinh -> tự động ghi danh vào lớp vừa tạo và chuyển sang Bước 3 (Lên lịch buổi đầu)
        let firstStudent = StudentEntity(fullName: "Nguyễn Minh Khôi")
        let savedStudent = await vmA.createAndEnrollStudentFromGuide(firstStudent, classId: firstClass.id)
        #expect(savedStudent == true)
        #expect(vmA.currentFirstTimeStep == .scheduleFirstSession)
        #expect(vmA.completedFirstTimeStepsCount == 2)

        // Bước 3: Lên lịch buổi đầu -> hoàn tất cả 3 bước
        let firstSession = TeachingSessionEntity(
            classId: firstClass.id,
            title: "Buổi 1: Toán 9 Cơ Bản",
            startTime: Date().addingTimeInterval(3600),
            endTime: Date().addingTimeInterval(3600 + 5400),
            status: .scheduled
        )
        try await vmA.createSession(firstSession, participantStudentIds: [firstStudent.id])
        #expect(vmA.currentFirstTimeStep == .completed)
        #expect(vmA.completedFirstTimeStepsCount == 3)
        #expect(vmA.shouldShowFirstTimeGuide == false)
    }

    @Test("Trang chủ 4 nhóm tổng quan: đếm học sinh/lớp đang hoạt động không trùng lặp và lấy danh sách buổi dạy hôm nay hoặc sắp tới")
    func testHomeOverviewFourGroups_UniqueActiveCounts_AndUpcomingSessionsFallback() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!

        let now = Date()
        let studentId1 = UUID()
        let studentId2 = UUID()
        let archivedStudentId = UUID()

        // Giả lập học sinh 1 xuất hiện 2 lần trong mảng đầu vào (ví dụ từ nhiều nguồn/lớp) và 1 học sinh đã lưu trữ
        let students = [
            StudentEntity(id: studentId1, fullName: "Nguyễn Minh Anh", isArchived: false),
            StudentEntity(id: studentId1, fullName: "Nguyễn Minh Anh", isArchived: false),
            StudentEntity(id: studentId2, fullName: "Trần Gia Bảo", isArchived: false),
            StudentEntity(id: archivedStudentId, fullName: "Lê Hoàng Cũ", isArchived: true)
        ]

        let classId1 = UUID()
        let archivedClassId = UUID()
        let classes = [
            ClassGroupEntity(id: classId1, name: "Toán 9", isArchived: false),
            ClassGroupEntity(id: classId1, name: "Toán 9", isArchived: false),
            ClassGroupEntity(id: archivedClassId, name: "Lý 9 Cũ", isArchived: true)
        ]

        // Không có buổi hôm nay, nhưng có 2 buổi sắp tới (ngày mai và ngày kia) + 1 buổi đã hủy
        let tomorrow = now.addingTimeInterval(86_400)
        let dayAfter = now.addingTimeInterval(172_800)
        let upcoming1 = TeachingSessionEntity(
            classId: classId1,
            title: "Đại số 9",
            startTime: tomorrow,
            endTime: tomorrow.addingTimeInterval(5400),
            status: .scheduled
        )
        let upcoming2 = TeachingSessionEntity(
            classId: classId1,
            title: "Hình học 9",
            startTime: dayAfter,
            endTime: dayAfter.addingTimeInterval(5400),
            status: .scheduled
        )
        let cancelledUpcoming = TeachingSessionEntity(
            classId: classId1,
            title: "Buổi nghỉ",
            startTime: tomorrow.addingTimeInterval(7200),
            endTime: tomorrow.addingTimeInterval(10800),
            status: .cancelled
        )

        let charges = [
            ChargeEntity(sessionId: UUID(), studentId: studentId1, amount: 300_000, unitPriceSnapshot: 150_000),
            ChargeEntity(sessionId: UUID(), studentId: studentId2, amount: 150_000, unitPriceSnapshot: 150_000)
        ]
        let payments = [
            PaymentEntity(studentId: studentId1, amount: 200_000)
        ]

        let metrics = useCase.execute(
            students: students,
            classes: classes,
            sessions: [upcoming2, upcoming1, cancelledUpcoming],
            records: [],
            charges: charges,
            payments: payments,
            now: now,
            calendar: calendar
        )

        // B & C: Không cộng nhầm đã lưu trữ và không đếm trùng học sinh/lớp
        #expect(metrics.activeStudentsCount == 2)
        #expect(metrics.activeClassesCount == 1)

        // A: Tài chính dùng chung nguồn CalculateFinanceSummaryUseCase (Phát sinh - Đã thu = Còn nợ)
        #expect(metrics.financeSummary.accruedTuition == 450_000)
        #expect(metrics.financeSummary.collectedTuition == 200_000)
        #expect(metrics.financeSummary.outstandingBalance == 250_000)

        // D: Khi hôm nay không có ca dạy, upcomingSessions chứa các buổi sắp tới đã sắp xếp tăng dần theo giờ (bỏ qua buổi đã hủy)
        #expect(metrics.todaySessions.isEmpty)
        #expect(metrics.upcomingSessions.count == 2)
        #expect(metrics.upcomingSessions.first?.id == upcoming1.id)
        #expect(metrics.displaySessions.count == 2)
        #expect(metrics.isShowingUpcomingSessions == true)
    }

    @Test("Kiểm thử hiệu năng và hồi quy Trang chủ 4 nhóm với tập dữ liệu lớn (500 học sinh, 50 lớp, 1.000 buổi dạy, 2.000 khoản thu)")
    func testDashboardHighVolumePerformanceAndSingleSourceInvariants() {
        let now = Date()
        var students: [StudentEntity] = []
        students.reserveCapacity(500)
        for idx in 0..<500 {
            students.append(
                StudentEntity(
                    fullName: "Học sinh \(idx)",
                    isArchived: idx >= 450 // 450 active, 50 archived
                )
            )
        }

        var classes: [ClassGroupEntity] = []
        classes.reserveCapacity(50)
        for idx in 0..<50 {
            classes.append(
                ClassGroupEntity(
                    name: "Lớp \(idx)",
                    defaultPricePerSession: 200_000,
                    isArchived: idx >= 40 // 40 active, 10 archived
                )
            )
        }

        var sessions: [TeachingSessionEntity] = []
        sessions.reserveCapacity(1_000)
        for idx in 0..<1_000 {
            let offsetHours = Double(idx - 500)
            let start = now.addingTimeInterval(offsetHours * 3600)
            sessions.append(
                TeachingSessionEntity(
                    classId: classes[idx % classes.count].id,
                    title: "Buổi học \(idx)",
                    startTime: start,
                    endTime: start.addingTimeInterval(5400),
                    status: idx < 500 ? .completed : .scheduled
                )
            )
        }

        var charges: [ChargeEntity] = []
        charges.reserveCapacity(2_000)
        for idx in 0..<2_000 {
            charges.append(
                ChargeEntity(
                    sessionId: sessions[idx % 500].id,
                    studentId: students[idx % 450].id,
                    amount: 200_000,
                    unitPriceSnapshot: 200_000
                )
            )
        }

        var payments: [PaymentEntity] = []
        payments.reserveCapacity(1_500)
        for idx in 0..<1_500 {
            payments.append(
                PaymentEntity(
                    studentId: students[idx % 450].id,
                    amount: 200_000
                )
            )
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let metrics = useCase.execute(
            students: students,
            classes: classes,
            sessions: sessions,
            records: [],
            charges: charges,
            payments: payments,
            now: now
        )
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        #expect(metrics.activeStudentsCount == 450)
        #expect(metrics.activeClassesCount == 40)
        #expect(metrics.financeSummary.accruedTuition == 400_000_000)
        #expect(metrics.financeSummary.collectedTuition == 300_000_000)
        #expect(metrics.financeSummary.outstandingBalance == 100_000_000)
        #expect(
            metrics.financeSummary.accruedTuition - metrics.financeSummary.collectedTuition
            == metrics.financeSummary.outstandingBalance
        )
        #expect(elapsedMs < 250.0)
    }
}

