import Testing
import Foundation
import SwiftData
@testable import EduPetal

@Suite("Finance Management & Single-Source Tuition Test Suite")
struct FinanceTests {

    @MainActor
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema(EduPetalSchemaV1.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - 1. Charge Generation & Idempotency Tests

    @Test("Idempotent charge generation: calling multiple times never duplicates charges")
    func testIdempotentChargeGeneration() {
        let useCase = GenerateSessionChargesUseCase()
        let sessionId = UUID()
        let student1Id = UUID()
        let student2Id = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Toán 12 - Tích phân",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .completed
        )

        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: student1Id, status: .present),
            AttendanceEntity(sessionId: sessionId, studentId: student2Id, status: .present)
        ]

        let student1 = StudentEntity(id: student1Id, fullName: "Nguyễn Văn A", defaultPricePerSession: 200_000)
        let student2 = StudentEntity(id: student2Id, fullName: "Trần Thị B", defaultPricePerSession: nil)
        let classGroup = ClassGroupEntity(name: "Toán 12 Pro", defaultPricePerSession: 150_000)

        // First run: generates 2 charges
        let firstRunCharges = useCase.execute(
            session: session,
            attendances: attendances,
            students: [student1, student2],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(firstRunCharges.count == 2)
        #expect(firstRunCharges.first(where: { $0.studentId == student1Id })?.amount == 200_000)
        #expect(firstRunCharges.first(where: { $0.studentId == student2Id })?.amount == 150_000)

        // Second run: with existing charges passed, generates 0 new charges (idempotent)
        let secondRunCharges = useCase.execute(
            session: session,
            attendances: attendances,
            students: [student1, student2],
            classGroup: classGroup,
            existingCharges: firstRunCharges
        )
        #expect(secondRunCharges.isEmpty)
    }

    @Test("Present students receive charges snapshotting unit price; Absent/Excused get 0 charges")
    func testChargeGenerationAttendanceStatusFiltering() {
        let useCase = GenerateSessionChargesUseCase()
        let sessionId = UUID()
        let presentStudentId = UUID()
        let absentStudentId = UUID()
        let excusedStudentId = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Vật lý 11 - Sóng cơ",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .completed
        )

        let attendances = [
            AttendanceEntity(sessionId: sessionId, studentId: presentStudentId, status: .present),
            AttendanceEntity(sessionId: sessionId, studentId: absentStudentId, status: .absent),
            AttendanceEntity(sessionId: sessionId, studentId: excusedStudentId, status: .excused)
        ]

        let s1 = StudentEntity(id: presentStudentId, fullName: "Học sinh Có mặt", defaultPricePerSession: 180_000)
        let s2 = StudentEntity(id: absentStudentId, fullName: "Học sinh Vắng", defaultPricePerSession: 180_000)
        let s3 = StudentEntity(id: excusedStudentId, fullName: "Học sinh Nghỉ phép", defaultPricePerSession: 180_000)
        let classGroup = ClassGroupEntity(name: "Vật lý 11", defaultPricePerSession: 150_000)

        let charges = useCase.execute(
            session: session,
            attendances: attendances,
            students: [s1, s2, s3],
            classGroup: classGroup,
            existingCharges: []
        )

        #expect(charges.count == 1)
        #expect(charges[0].studentId == presentStudentId)
        #expect(charges[0].amount == 180_000)
        #expect(charges[0].unitPriceSnapshot == 180_000)
        #expect(charges[0].status == .unpaid)
    }

    @Test("Non-completed session (Scheduled or Cancelled) produces 0 charges")
    func testChargeGenerationNonCompletedSessionProducesZeroCharges() {
        let useCase = GenerateSessionChargesUseCase()
        let sessionId = UUID()
        let studentId = UUID()

        let scheduledSession = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Hóa học 10",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .scheduled
        )

        let cancelledSession = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Hóa học 10",
            startTime: Date(),
            endTime: Date().addingTimeInterval(5400),
            status: .cancelled
        )

        let attendances = [AttendanceEntity(sessionId: sessionId, studentId: studentId, status: .present)]
        let student = StudentEntity(id: studentId, fullName: "Lê C")
        let classGroup = ClassGroupEntity(name: "Hóa 10", defaultPricePerSession: 120_000)

        let scheduledCharges = useCase.execute(
            session: scheduledSession,
            attendances: attendances,
            students: [student],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(scheduledCharges.isEmpty)

        let cancelledCharges = useCase.execute(
            session: cancelledSession,
            attendances: attendances,
            students: [student],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(cancelledCharges.isEmpty)
    }

    @Test("Future price modifications do not affect past charge snapshots")
    func testFuturePriceEditDoesNotAffectPastCharges() {
        let useCase = GenerateSessionChargesUseCase()
        let sessionId = UUID()
        let studentId = UUID()

        let session = TeachingSessionEntity(
            id: sessionId,
            classId: UUID(),
            title: "Tiếng Anh IELTS",
            startTime: Date(),
            endTime: Date().addingTimeInterval(7200),
            status: .completed
        )

        var student = StudentEntity(id: studentId, fullName: "Phạm D", defaultPricePerSession: 250_000)
        var classGroup = ClassGroupEntity(name: "IELTS Speaking", defaultPricePerSession: 200_000)
        let attendances = [AttendanceEntity(sessionId: sessionId, studentId: studentId, status: .present)]

        let generatedCharges = useCase.execute(
            session: session,
            attendances: attendances,
            students: [student],
            classGroup: classGroup,
            existingCharges: []
        )
        #expect(generatedCharges.count == 1)
        let pastCharge = generatedCharges[0]
        #expect(pastCharge.unitPriceSnapshot == 250_000)
        #expect(pastCharge.amount == 250_000)

        // Teacher increases student and class price next month
        student.defaultPricePerSession = 350_000
        classGroup.defaultPricePerSession = 300_000

        // Past charge remains completely unchanged
        #expect(pastCharge.unitPriceSnapshot == 250_000)
        #expect(pastCharge.amount == 250_000)
    }

    // MARK: - 2. Finance Summary & Invariant Balancing Tests

    @Test("Finance summary computes Accrued, Collected, and strictly enforces Invariant Outstanding")
    func testFinanceSummaryInvariantCalculation() {
        let useCase = CalculateFinanceSummaryUseCase()
        let studentId = UUID()

        let charges = [
            ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 200_000, unitPriceSnapshot: 200_000),
            ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 250_000, unitPriceSnapshot: 250_000),
            ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 300_000, unitPriceSnapshot: 300_000)
        ]

        let payments = [
            PaymentEntity(studentId: studentId, amount: 200_000),
            PaymentEntity(studentId: studentId, amount: 150_000)
        ]

        let summary = useCase.execute(charges: charges, payments: payments)

        // Total Accrued = 200k + 250k + 300k = 750k
        #expect(summary.accruedTuition == 750_000)
        // Total Collected = 200k + 150k = 350k
        #expect(summary.collectedTuition == 350_000)
        // Invariant: Outstanding = Accrued - Collected = 400k
        #expect(summary.outstandingBalance == 400_000)
        #expect(summary.outstandingBalance == summary.accruedTuition - summary.collectedTuition)
    }

    @Test("Finance summary per student isolates student calculations")
    func testFinanceSummaryPerStudent() {
        let useCase = CalculateFinanceSummaryUseCase()
        let student1Id = UUID()
        let student2Id = UUID()

        let charges = [
            ChargeEntity(sessionId: UUID(), studentId: student1Id, amount: 300_000, unitPriceSnapshot: 300_000),
            ChargeEntity(sessionId: UUID(), studentId: student2Id, amount: 500_000, unitPriceSnapshot: 500_000)
        ]

        let payments = [
            PaymentEntity(studentId: student1Id, amount: 100_000),
            PaymentEntity(studentId: student2Id, amount: 500_000)
        ]

        let s1Summary = useCase.executeForStudent(studentId: student1Id, charges: charges, payments: payments)
        #expect(s1Summary.accruedTuition == 300_000)
        #expect(s1Summary.collectedTuition == 100_000)
        #expect(s1Summary.outstandingBalance == 200_000)

        let s2Summary = useCase.executeForStudent(studentId: student2Id, charges: charges, payments: payments)
        #expect(s2Summary.accruedTuition == 500_000)
        #expect(s2Summary.collectedTuition == 500_000)
        #expect(s2Summary.outstandingBalance == 0)
    }

    // MARK: - 3. Payment Recording & FIFO Allocation Tests

    @Test("Recording payment with zero or negative amount throws invalidAmount")
    func testRecordPaymentZeroOrNegativeThrows() {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let charge = ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 200_000, unitPriceSnapshot: 200_000)

        #expect(throws: RecordPaymentError.invalidAmount(min: 1)) {
            try useCase.execute(
                studentId: studentId,
                amount: 0,
                studentCharges: [charge],
                existingAllocations: []
            )
        }

        #expect(throws: RecordPaymentError.invalidAmount(min: 1)) {
            try useCase.execute(
                studentId: studentId,
                amount: -50_000,
                studentCharges: [charge],
                existingAllocations: []
            )
        }
    }

    @Test("Recording payment when student has 0 outstanding balance throws studentHasNoOutstandingBalance")
    func testRecordPaymentZeroOutstandingThrows() {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let chargeId = UUID()
        let charge = ChargeEntity(id: chargeId, sessionId: UUID(), studentId: studentId, amount: 200_000, unitPriceSnapshot: 200_000)
        let allocation = PaymentAllocationEntity(paymentId: UUID(), chargeId: chargeId, allocatedAmount: 200_000)

        #expect(throws: RecordPaymentError.studentHasNoOutstandingBalance) {
            try useCase.execute(
                studentId: studentId,
                amount: 100_000,
                studentCharges: [charge],
                existingAllocations: [allocation]
            )
        }
    }

    @Test("Recording payment exceeding outstanding balance is strictly rejected (No overpayment)")
    func testRecordPaymentOverpaymentRejected() {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let charge = ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 200_000, unitPriceSnapshot: 200_000)

        #expect(throws: RecordPaymentError.exceedsOutstandingBalance(outstanding: 200_000, attempted: 250_000)) {
            try useCase.execute(
                studentId: studentId,
                amount: 250_000,
                studentCharges: [charge],
                existingAllocations: []
            )
        }
    }

    @Test("Recording partial payment allocates FIFO and marks charge as partiallyPaid")
    func testRecordPaymentPartialFIFOAllocation() throws {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let chargeId = UUID()
        let charge = ChargeEntity(
            id: chargeId,
            sessionId: UUID(),
            studentId: studentId,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid,
            createdAt: Date()
        )

        let result = try useCase.execute(
            studentId: studentId,
            amount: 100_000,
            paymentMethod: "Chuyển khoản",
            note: "Trả trước đợt 1",
            studentCharges: [charge],
            existingAllocations: []
        )

        #expect(result.payment.amount == 100_000)
        #expect(result.payment.paymentMethod == "Chuyển khoản")
        #expect(result.payment.note == "Trả trước đợt 1")

        #expect(result.allocations.count == 1)
        #expect(result.allocations[0].chargeId == chargeId)
        #expect(result.allocations[0].allocatedAmount == 100_000)

        #expect(result.updatedCharges.count == 1)
        #expect(result.updatedCharges[0].status == .partiallyPaid)
    }

    @Test("Recording payment covering multiple charges allocates in FIFO order")
    func testRecordPaymentMultiChargeFIFO() throws {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let charge1Id = UUID()
        let charge2Id = UUID()
        let date1 = Date().addingTimeInterval(-86400 * 7) // 7 days ago
        let date2 = Date().addingTimeInterval(-86400 * 3) // 3 days ago

        let c1 = ChargeEntity(id: charge1Id, sessionId: UUID(), studentId: studentId, amount: 200_000, unitPriceSnapshot: 200_000, status: .unpaid, createdAt: date1)
        let c2 = ChargeEntity(id: charge2Id, sessionId: UUID(), studentId: studentId, amount: 300_000, unitPriceSnapshot: 300_000, status: .unpaid, createdAt: date2)

        // Total outstanding = 500k. Student pays 350k (covering 200k of c1, and 150k of c2)
        let result = try useCase.execute(
            studentId: studentId,
            amount: 350_000,
            studentCharges: [c1, c2],
            existingAllocations: []
        )

        #expect(result.allocations.count == 2)
        let alloc1 = result.allocations.first(where: { $0.chargeId == charge1Id })
        let alloc2 = result.allocations.first(where: { $0.chargeId == charge2Id })

        #expect(alloc1?.allocatedAmount == 200_000)
        #expect(alloc2?.allocatedAmount == 150_000)

        let updatedC1 = result.updatedCharges.first(where: { $0.id == charge1Id })
        let updatedC2 = result.updatedCharges.first(where: { $0.id == charge2Id })

        #expect(updatedC1?.status == .paid)
        #expect(updatedC2?.status == .partiallyPaid)
    }

    @Test("Recording full payment marks all charges as paid")
    func testRecordPaymentFullPaymentMarksAllPaid() throws {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let c1 = ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 150_000, unitPriceSnapshot: 150_000, status: .unpaid, createdAt: Date().addingTimeInterval(-3600))
        let c2 = ChargeEntity(sessionId: UUID(), studentId: studentId, amount: 250_000, unitPriceSnapshot: 250_000, status: .unpaid, createdAt: Date())

        let result = try useCase.execute(
            studentId: studentId,
            amount: 400_000,
            studentCharges: [c1, c2],
            existingAllocations: []
        )

        #expect(result.allocations.count == 2)
        #expect(result.updatedCharges.allSatisfy { $0.status == .paid })
    }

    // MARK: - 4. Model Mapper & Repository Integration Tests

    @Test("Finance Mapper accurately converts between Models and Entities")
    func testFinanceMapperConversion() {
        let chargeId = UUID()
        let sessionId = UUID()
        let studentId = UUID()

        let chargeEntity = ChargeEntity(
            id: chargeId,
            sessionId: sessionId,
            studentId: studentId,
            amount: 220_000,
            unitPriceSnapshot: 220_000,
            status: .partiallyPaid
        )

        let model = FinanceMapper.toChargeModel(chargeEntity)
        #expect(model.id == chargeId)
        #expect(model.amount == 220_000)
        #expect(model.statusRaw == "partially_paid")

        let convertedBack = FinanceMapper.toChargeEntity(model)
        #expect(convertedBack.id == chargeId)
        #expect(convertedBack.status == .partiallyPaid)
        #expect(convertedBack.amount == 220_000)
    }

    @MainActor
    @Test("FinanceRepository integrates with SwiftData container")
    func testFinanceRepositoryIntegration() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let repository = FinanceRepository(modelContext: context)

        let studentId = UUID()
        let sessionId = UUID()

        let charge = ChargeEntity(
            sessionId: sessionId,
            studentId: studentId,
            amount: 180_000,
            unitPriceSnapshot: 180_000,
            status: .unpaid
        )
        try await repository.saveCharge(charge)

        let fetchedCharges = try await repository.fetchChargesForStudent(studentId: studentId)
        #expect(fetchedCharges.count == 1)
        #expect(fetchedCharges[0].amount == 180_000)

        let payment = PaymentEntity(
            studentId: studentId,
            amount: 180_000,
            paymentMethod: "Chuyển khoản Vietcombank"
        )
        try await repository.savePayment(payment)

        let fetchedPayments = try await repository.fetchPaymentsForStudent(studentId: studentId)
        #expect(fetchedPayments.count == 1)
        #expect(fetchedPayments[0].amount == 180_000)
        #expect(fetchedPayments[0].paymentMethod == "Chuyển khoản Vietcombank")
    }

    @MainActor
    @Test("FinanceViewModel filters transaction history accurately by type and returns created payment")
    func testFinanceViewModelFilteredTransactions() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let fRepo = FinanceRepository(modelContext: context)
        let sRepo = StudentRepository(modelContext: context)

        let student = StudentEntity(fullName: "Lê Hoàng Long", defaultPricePerSession: 200_000)
        try await sRepo.saveStudent(student)

        let viewModel = FinanceViewModel(
            financeRepository: fRepo,
            studentRepository: sRepo
        )

        let charge1 = ChargeEntity(
            sessionId: UUID(),
            studentId: student.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid,
            createdAt: Date().addingTimeInterval(-3600)
        )
        try await fRepo.saveCharge(charge1)

        await viewModel.loadData()
        #expect(viewModel.charges.count == 1)
        #expect(viewModel.summary.accruedTuition == 200_000)
        #expect(viewModel.summary.outstandingBalance == 200_000)

        // Record payment
        let savedPayment = try await viewModel.recordPayment(
            studentId: student.id,
            amount: 200_000,
            paymentMethod: "Chuyển khoản",
            note: "Thanh toán học phí tháng 11"
        )

        #expect(savedPayment.amount == 200_000)
        #expect(viewModel.summary.collectedTuition == 200_000)
        #expect(viewModel.summary.outstandingBalance == 0)

        // Test Transaction filtering
        viewModel.transactionTypeFilter = .all
        #expect(viewModel.filteredTransactions.count == 2) // 1 charge + 1 payment

        viewModel.transactionTypeFilter = .payments
        #expect(viewModel.filteredTransactions.count == 1)
        if case .payment(let p) = viewModel.filteredTransactions[0] {
            #expect(p.amount == 200_000)
        } else {
            Issue.record("Expected payment transaction item")
        }

        viewModel.transactionTypeFilter = .charges
        #expect(viewModel.filteredTransactions.count == 1)
        if case .charge(let c) = viewModel.filteredTransactions[0] {
            #expect(c.amount == 200_000)
            #expect(c.status == .paid)
        } else {
            Issue.record("Expected charge transaction item")
        }

        // Test FIFO allocation retrieval
        let allocations = await viewModel.fetchAllocations(for: savedPayment.id)
        #expect(allocations.count == 1)
        #expect(allocations[0].allocatedAmount == 200_000)
    }

    // MARK: - VietQR & Bank Configuration Tests

    @Test("BankConfigService accurately persists account details and builds valid VietQR URL")
    func testBankConfigServiceVietQRGeneration() {
        let service = BankConfigService()

        let unconfigured = BankAccountConfig(accountNumber: "", accountHolderName: "")
        #expect(!unconfigured.isConfigured)
        #expect(service.generateVietQRURL(config: unconfigured, amount: 200_000, note: "Hoc phi") == nil)

        let config = BankAccountConfig(
            bankCode: "VCB",
            bankName: "Vietcombank (VCB)",
            accountNumber: "1234567890",
            accountHolderName: "NGUYEN VAN A"
        )
        #expect(config.isConfigured)

        service.saveConfig(config)
        let loaded = service.loadConfig()
        #expect(loaded.bankCode == "VCB")
        #expect(loaded.accountNumber == "1234567890")
        #expect(loaded.accountHolderName == "NGUYEN VAN A")

        // Test VietQR URL Generation
        let url = service.generateVietQRURL(config: config, amount: 500_000, note: "Hoc phi Nam")
        #expect(url != nil)
        let urlString = url?.absoluteString ?? ""
        #expect(urlString.contains("img.vietqr.io/image/vcb-1234567890-compact2.png"))
        #expect(urlString.contains("amount=500000"))
        #expect(urlString.contains("addInfo=Hoc%20phi%20Nam"))

        // Test Transfer message template
        let message = service.generateTransferMessage(config: config, amount: 500_000, studentName: "Trần Nam", note: "Hoc phi thang 11")
        #expect(message.contains("1234567890"))
        #expect(message.contains("NGUYEN VAN A"))
        #expect(message.contains("500.000 ₫"))
        #expect(message.contains("Hoc phi thang 11"))
    }

    // MARK: - Receipt PDF & Cancellation Tests

    @Test("ReceiptPDFRenderer generates valid standard A4 tuition statement PDF")
    func testReceiptPDFRenderer_GeneratesValidA4PDF() throws {
        let renderer = ReceiptPDFRenderer()
        let data = ReceiptPDFData(
            receiptCode: "#REC-12345678",
            teacherName: "Thầy Minh Huy",
            studentName: "Nguyễn Văn An",
            amount: 600_000,
            paidAt: Date(),
            paymentMethod: "Chuyển khoản Vietcombank",
            note: "Học phí 3 buổi ôn thi",
            remainingBalance: 0,
            items: [
                (title: "Buổi 1: Đạo hàm", date: Date().addingTimeInterval(-86400 * 5), amount: 200_000),
                (title: "Buổi 2: Tích phân", date: Date().addingTimeInterval(-86400 * 3), amount: 200_000),
                (title: "Buổi 3: Hình không gian", date: Date().addingTimeInterval(-86400 * 1), amount: 200_000)
            ]
        )

        let pdfData = try renderer.renderReceiptPDF(data: data)
        #expect(!pdfData.isEmpty)
        #expect(pdfData.count > 1000)
    }

    @MainActor
    @Test("Cancel payment rolls back charge status to unpaid and restores outstanding balance")
    func testCancelPaymentRollsBackChargeAndRecalculatesDebt() async throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let fRepo = FinanceRepository(modelContext: context)
        let sRepo = StudentRepository(modelContext: context)

        let student = StudentEntity(fullName: "Phạm Minh Trang", defaultPricePerSession: 300_000)
        try await sRepo.saveStudent(student)

        let viewModel = FinanceViewModel(
            financeRepository: fRepo,
            studentRepository: sRepo
        )

        let charge = ChargeEntity(
            sessionId: UUID(),
            studentId: student.id,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid
        )
        try await fRepo.saveCharge(charge)
        await viewModel.loadData()

        #expect(viewModel.summary.accruedTuition == 300_000)
        #expect(viewModel.summary.outstandingBalance == 300_000)

        // 1. Thu tiền
        let payment = try await viewModel.recordPayment(
            studentId: student.id,
            amount: 300_000,
            paymentMethod: "Tiền mặt"
        )
        #expect(viewModel.summary.collectedTuition == 300_000)
        #expect(viewModel.summary.outstandingBalance == 0)
        #expect(viewModel.charges.first(where: { $0.id == charge.id })?.status == .paid)

        // 2. Hủy phiếu thu
        try await viewModel.cancelPayment(paymentId: payment.id)

        // 3. Kiểm tra công nợ được khôi phục nguyên vẹn
        #expect(viewModel.summary.collectedTuition == 0)
        #expect(viewModel.summary.outstandingBalance == 300_000)
        #expect(viewModel.charges.first(where: { $0.id == charge.id })?.status == .unpaid)
        #expect(viewModel.payments.isEmpty)
    }

    // MARK: - 5. Feature 5: Danh sách học phí, số buổi trong kỳ, tách bạch nợ cũ và ảnh minh chứng

    @MainActor
    @Test("FinanceViewModel tính đúng số buổi trong kỳ, học phí phát sinh trong kỳ, đã thu trong kỳ, nợ cũ kỳ trước, lọc lớp/trạng thái và gắn ảnh minh chứng")
    func testFinanceViewModel_PeriodMetrics_PriorDebt_FiltersAndProofAttachments() async throws {
        let container = try createTestContainer()
        let fRepo = FinanceRepository(modelContainer: container)
        let sRepo = StudentRepository(modelContainer: container)
        let schRepo = ScheduleRepository(modelContainer: container)
        let cRepo = ClassRepository(modelContainer: container)

        let classMath = ClassGroupEntity(name: "Lớp Toán 12", subject: "Toán", defaultPricePerSession: 200_000)
        let classEng = ClassGroupEntity(name: "Lớp IELTS", subject: "Tiếng Anh", defaultPricePerSession: 300_000)
        try await cRepo.saveClass(classMath)
        try await cRepo.saveClass(classEng)

        let studentA = StudentEntity(fullName: "Nguyễn Hải Đăng", phoneNumber: "0901112222")
        let studentB = StudentEntity(fullName: "Lê Thu Hà", phoneNumber: "0903334444")
        try await sRepo.saveStudent(studentA)
        try await sRepo.saveStudent(studentB)

        try await cRepo.enrollStudent(studentId: studentA.id, classId: classMath.id)
        try await cRepo.enrollStudent(studentId: studentB.id, classId: classEng.id)

        let cal = Calendar.current
        let now = Date()
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-35 * 86400)

        // Buổi tháng trước của Học sinh A (200k - chưa đóng -> thành nợ cũ kỳ trước)
        let sessionLastMonth = TeachingSessionEntity(
            classId: classMath.id,
            title: "Toán 12 - Tháng trước",
            startTime: lastMonthDate,
            endTime: lastMonthDate.addingTimeInterval(5400),
            status: .completed
        )
        try await schRepo.saveSession(sessionLastMonth)
        try await schRepo.addAttachment(
            SessionAttachmentEntity(sessionId: sessionLastMonth.id, filePath: "proof_old.jpg", caption: "Ảnh tháng trước")
        )
        let chargeOld = ChargeEntity(
            sessionId: sessionLastMonth.id,
            studentId: studentA.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid,
            createdAt: lastMonthDate
        )
        try await fRepo.saveCharge(chargeOld)

        // 2 buổi tháng này của Học sinh A (mỗi buổi 200k -> tổng phát sinh trong kỳ = 400k)
        let sessionThisMonth1 = TeachingSessionEntity(
            classId: classMath.id,
            title: "Toán 12 - Buổi 1 tháng này",
            startTime: now.addingTimeInterval(-3600 * 24),
            endTime: now.addingTimeInterval(-3600 * 22.5),
            status: .completed
        )
        let sessionThisMonth2 = TeachingSessionEntity(
            classId: classMath.id,
            title: "Toán 12 - Buổi 2 tháng này",
            startTime: now,
            endTime: now.addingTimeInterval(5400),
            status: .completed
        )
        try await schRepo.saveSession(sessionThisMonth1)
        try await schRepo.saveSession(sessionThisMonth2)
        try await schRepo.addAttachment(
            SessionAttachmentEntity(sessionId: sessionThisMonth1.id, filePath: "proof_m1.jpg", caption: "Minh chứng buổi 1")
        )
        try await schRepo.addAttachment(
            SessionAttachmentEntity(sessionId: sessionThisMonth2.id, filePath: "proof_m2.jpg", caption: "Minh chứng buổi 2")
        )

        let chargeNew1 = ChargeEntity(
            sessionId: sessionThisMonth1.id,
            studentId: studentA.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid,
            createdAt: now.addingTimeInterval(-3600 * 24)
        )
        let chargeNew2 = ChargeEntity(
            sessionId: sessionThisMonth2.id,
            studentId: studentA.id,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid,
            createdAt: now
        )
        try await fRepo.saveCharges([chargeNew1, chargeNew2])

        // 1 buổi tháng này của Học sinh B (300k - đã thu đủ 300k)
        let sessionEng = TeachingSessionEntity(
            classId: classEng.id,
            title: "IELTS Speaking",
            startTime: now,
            endTime: now.addingTimeInterval(5400),
            status: .completed
        )
        try await schRepo.saveSession(sessionEng)
        let chargeEng = ChargeEntity(
            sessionId: sessionEng.id,
            studentId: studentB.id,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid,
            createdAt: now
        )
        try await fRepo.saveCharge(chargeEng)

        let vm = FinanceViewModel(
            financeRepository: fRepo,
            studentRepository: sRepo,
            scheduleRepository: schRepo,
            classRepository: cRepo
        )
        vm.selectedTimeFilter = .thisMonth
        await vm.loadData()

        // Học sinh B đóng đủ 300k trong tháng này
        _ = try await vm.recordPayment(studentId: studentB.id, amount: 300_000, paidAt: now, paymentMethod: "Chuyển khoản")
        // Học sinh A đóng 150k trong tháng này (FIFO cấn trừ vào khoản nợ tháng trước chargeOld 200k -> nợ cũ còn 50k, nợ kỳ này còn 400k, tổng nợ hiện tại = 450k)
        _ = try await vm.recordPayment(studentId: studentA.id, amount: 150_000, paidAt: now, paymentMethod: "Tiền mặt")

        let allItems = vm.buildStudentFinanceItems(searchQuery: "")
        let itemA = try #require(allItems.first(where: { $0.student.id == studentA.id }))
        let itemB = try #require(allItems.first(where: { $0.student.id == studentB.id }))

        // Kiểm tra Học sinh A:
        // - Số buổi trong kỳ (tháng này): 2 buổi (tổng lũy kế: 3 buổi)
        #expect(itemA.completedSessionsInPeriodCount == 2)
        #expect(itemA.totalCompletedSessionsCount == 3)
        // - Học phí phát sinh trong kỳ: 400.000 ₫ (tổng lũy kế: 600.000 ₫)
        #expect(itemA.accruedInPeriod == 400_000)
        #expect(itemA.accrued == 600_000)
        // - Đã thu trong kỳ: 150.000 ₫
        #expect(itemA.collectedInPeriod == 150_000)
        // - Tổng còn nợ đến hiện tại: 450.000 ₫ (gồm 50.000 ₫ nợ cũ tháng trước + 400.000 ₫ nợ kỳ này)
        #expect(itemA.outstanding == 450_000)
        #expect(itemA.priorPeriodDebt == 50_000)
        #expect(itemA.outstandingInPeriod == 400_000)
        #expect(itemA.paymentStatus == .partiallyPaid)
        #expect(itemA.totalProofAttachmentsCount == 3)
        #expect(itemA.proofAttachmentsInPeriodCount == 2)

        // Kiểm tra Học sinh B:
        #expect(itemB.completedSessionsInPeriodCount == 1)
        #expect(itemB.accruedInPeriod == 300_000)
        #expect(itemB.collectedInPeriod == 300_000)
        #expect(itemB.outstanding == 0)
        #expect(itemB.paymentStatus == .paid)

        // Kiểm tra lọc theo Lớp học
        vm.selectedClassFilterId = classMath.id
        let mathOnly = vm.buildStudentFinanceItems(searchQuery: "")
        #expect(mathOnly.count == 1)
        #expect(mathOnly.first?.student.id == studentA.id)

        vm.selectedClassFilterId = nil
        // Kiểm tra lọc theo Trạng thái thanh toán (.paid)
        vm.selectedStatusFilter = .paid
        let paidOnly = vm.buildStudentFinanceItems(searchQuery: "")
        #expect(paidOnly.count == 1)
        #expect(paidOnly.first?.student.id == studentB.id)

        vm.selectedStatusFilter = .all
        // Kiểm tra chi tiết buổi học & ảnh minh chứng của Học sinh A
        let sessionDetailsA = vm.chargeSessionDetails(for: studentA.id, onlySelectedPeriod: false)
        #expect(sessionDetailsA.count == 3)
        let oldSessionDetail = try #require(sessionDetailsA.first(where: { $0.charge.id == chargeOld.id }))
        #expect(oldSessionDetail.allocatedPaidAmount == 150_000)
        #expect(oldSessionDetail.remainingAmount == 50_000)
        #expect(oldSessionDetail.attachments.count == 1)
        #expect(oldSessionDetail.attachments.first?.caption == "Ảnh tháng trước")
    }

    // MARK: - 6. Feature 6: Ghi nhận thu tiền theo buổi đã chọn, chống nhân đôi phân bổ và bản kê / biên nhận học phí

    @Test("RecordPaymentUseCase allocates strictly to selectedChargeIds and rejects empty selection or over-selected-amount")
    func testRecordPaymentWithSelectedChargeIds() throws {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let c1 = ChargeEntity(
            sessionId: UUID(),
            studentId: studentId,
            amount: 200_000,
            unitPriceSnapshot: 200_000,
            status: .unpaid,
            createdAt: t0
        )
        let c2 = ChargeEntity(
            sessionId: UUID(),
            studentId: studentId,
            amount: 250_000,
            unitPriceSnapshot: 250_000,
            status: .unpaid,
            createdAt: t0.addingTimeInterval(3600)
        )
        let c3 = ChargeEntity(
            sessionId: UUID(),
            studentId: studentId,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid,
            createdAt: t0.addingTimeInterval(7200)
        )

        // 1. Truyền tập rỗng -> báo lỗi noChargesSelected
        #expect(throws: RecordPaymentError.noChargesSelected) {
            try useCase.execute(
                studentId: studentId,
                amount: 100_000,
                studentCharges: [c1, c2, c3],
                existingAllocations: [],
                selectedChargeIds: []
            )
        }

        // 2. Chọn riêng c2 (250k) và c3 (300k), bỏ qua c1 (200k).
        // Nếu nhập vượt tổng nợ đã chọn (550k) -> báo lỗi exceedsOutstandingBalance(outstanding: 550_000, attempted: 600_000)
        #expect(throws: RecordPaymentError.exceedsOutstandingBalance(outstanding: 550_000, attempted: 600_000)) {
            try useCase.execute(
                studentId: studentId,
                amount: 600_000,
                studentCharges: [c1, c2, c3],
                existingAllocations: [],
                selectedChargeIds: [c2.id, c3.id]
            )
        }

        // 3. Thu một phần 400k cho [c2, c3]: c2 được trả đủ 250k (.paid), c3 được trả một phần 150k (.partiallyPaid), c1 giữ nguyên .unpaid
        let result = try useCase.execute(
            studentId: studentId,
            amount: 400_000,
            studentCharges: [c1, c2, c3],
            existingAllocations: [],
            selectedChargeIds: [c2.id, c3.id]
        )

        #expect(result.allocations.count == 2)
        #expect(result.allocations.first(where: { $0.chargeId == c1.id }) == nil)
        #expect(result.allocations.first(where: { $0.chargeId == c2.id })?.allocatedAmount == 250_000)
        #expect(result.allocations.first(where: { $0.chargeId == c3.id })?.allocatedAmount == 150_000)

        let updatedC2 = try #require(result.updatedCharges.first(where: { $0.id == c2.id }))
        let updatedC3 = try #require(result.updatedCharges.first(where: { $0.id == c3.id }))
        #expect(updatedC2.status == .paid)
        #expect(updatedC3.status == .partiallyPaid)
        #expect(result.updatedCharges.first(where: { $0.id == c1.id }) == nil)
    }

    @MainActor
    @Test("Chống phân bổ trùng khi gọi lại cùng paymentId hoặc lưu lại cùng PaymentAllocation trong FinanceRepository")
    func testNoDuplicateAllocationOnRetry() async throws {
        let useCase = RecordPaymentUseCase()
        let studentId = UUID()
        let fixedPaymentId = UUID()
        let charge = ChargeEntity(
            sessionId: UUID(),
            studentId: studentId,
            amount: 300_000,
            unitPriceSnapshot: 300_000,
            status: .unpaid
        )

        let firstResult = try useCase.execute(
            paymentId: fixedPaymentId,
            studentId: studentId,
            amount: 200_000,
            studentCharges: [charge],
            existingAllocations: []
        )
        #expect(firstResult.allocations.count == 1)

        // Gọi lại với cùng paymentId khi allocation đã tồn tại -> không sinh thêm allocation trùng
        let duplicateResult = try useCase.execute(
            paymentId: fixedPaymentId,
            studentId: studentId,
            amount: 200_000,
            studentCharges: firstResult.updatedCharges,
            existingAllocations: firstResult.allocations
        )
        #expect(duplicateResult.allocations.isEmpty)
        #expect(duplicateResult.updatedCharges.isEmpty)

        // Kiểm tra idempotency ở tầng lưu trữ FinanceRepository.saveAllocations
        let container = try createTestContainer()
        let fRepo = FinanceRepository(modelContainer: container)
        try await fRepo.saveCharge(charge)
        try await fRepo.savePayment(firstResult.payment)
        try await fRepo.saveAllocations(firstResult.allocations)
        // Gọi saveAllocations lần 2 với cùng allocation hoặc cùng cặp (paymentId, chargeId)
        let dupAllocWithNewId = PaymentAllocationEntity(
            paymentId: fixedPaymentId,
            chargeId: charge.id,
            allocatedAmount: 200_000
        )
        try await fRepo.saveAllocations([firstResult.allocations[0], dupAllocWithNewId])

        let storedAllocations = try await fRepo.fetchAllocationsForCharge(chargeId: charge.id)
        #expect(storedAllocations.count == 1)
        #expect(storedAllocations.first?.allocatedAmount == 200_000)
    }

    @MainActor
    @Test("Tạo Bản kê nháp PDF không tự động tính là đã thu tiền và Biên nhận đã phát hành bảo toàn snapshot dư nợ lịch sử")
    func testDraftStatementDoesNotMarkPaid_AndIssuedReceiptPreservesSnapshotBalance() async throws {
        let container = try createTestContainer()
        let fRepo = FinanceRepository(modelContainer: container)
        let sRepo = StudentRepository(modelContainer: container)
        let schRepo = ScheduleRepository(modelContainer: container)

        let student = StudentEntity(fullName: "Hoàng Gia Bảo", defaultPricePerSession: 200_000)
        try await sRepo.saveStudent(student)

        let t1 = Date().addingTimeInterval(-7200)
        let t2 = Date().addingTimeInterval(-3600)
        let s1 = TeachingSessionEntity(classId: UUID(), title: "Buổi 1", startTime: t1, endTime: t1.addingTimeInterval(3600), status: .completed)
        let s2 = TeachingSessionEntity(classId: UUID(), title: "Buổi 2", startTime: t2, endTime: t2.addingTimeInterval(3600), status: .completed)
        try await schRepo.saveSession(s1)
        try await schRepo.saveSession(s2)

        let c1 = ChargeEntity(sessionId: s1.id, studentId: student.id, amount: 200_000, unitPriceSnapshot: 200_000, status: .unpaid, createdAt: t1)
        let c2 = ChargeEntity(sessionId: s2.id, studentId: student.id, amount: 200_000, unitPriceSnapshot: 200_000, status: .unpaid, createdAt: t2)
        try await fRepo.saveCharges([c1, c2])

        let vm = FinanceViewModel(financeRepository: fRepo, studentRepository: sRepo, scheduleRepository: schRepo)
        await vm.loadData()

        // 1. Tạo Bản kê nháp PDF cho Buổi 1 (200k) -> sinh dữ liệu PDF hợp lệ nhưng KHÔNG ghi nhận thanh toán
        let unpaidBefore = vm.unpaidChargeSessionDetails(for: student.id)
        let selectedItemC1 = unpaidBefore.filter { $0.charge.id == c1.id }
        let draftData = vm.generateDraftStatementPDF(
            draftCode: "#DRAFT-TEST01",
            studentId: student.id,
            selectedItems: selectedItemC1,
            requestedAmount: 200_000,
            paymentMethod: "Chuyển khoản",
            note: "Bản nháp gửi phụ huynh"
        )
        #expect(draftData != nil)
        #expect((draftData?.count ?? 0) > 100)
        #expect(vm.payments.isEmpty)
        #expect(vm.outstandingBalance(for: student.id) == 400_000)

        // 2. Giáo viên xác nhận đã nhận tiền cho riêng Buổi 2 (c2) với số tiền 150k (thu một phần)
        let payment = try await vm.recordPayment(
            studentId: student.id,
            amount: 150_000,
            paidAt: Date(),
            paymentMethod: "Chuyển khoản",
            note: "Thu một phần buổi 2",
            selectedChargeIds: [c2.id]
        )

        // Sau giao dịch này: c1 vẫn còn nợ 200k (.unpaid), c2 còn nợ 50k (.partiallyPaid), tổng dư nợ = 250k
        #expect(vm.outstandingBalance(for: student.id) == 250_000)
        #expect(vm.snapshotRemainingBalanceAfterPayment(payment) == 250_000)
        let unpaidAfter = vm.unpaidChargeSessionDetails(for: student.id)
        #expect(unpaidAfter.count == 2)
        #expect(unpaidAfter.first(where: { $0.charge.id == c1.id })?.remainingAmount == 200_000)
        #expect(unpaidAfter.first(where: { $0.charge.id == c2.id })?.remainingAmount == 50_000)

        // 3. Phát sinh thêm Buổi 3 mới sau thời điểm thanh toán (200k)
        let t3 = Date().addingTimeInterval(3600)
        let s3 = TeachingSessionEntity(classId: UUID(), title: "Buổi 3 mới", startTime: t3, endTime: t3.addingTimeInterval(3600), status: .completed)
        try await schRepo.saveSession(s3)
        let c3 = ChargeEntity(sessionId: s3.id, studentId: student.id, amount: 200_000, unitPriceSnapshot: 200_000, status: .unpaid, createdAt: t3)
        try await fRepo.saveCharge(c3)
        await vm.loadData()

        // Tổng nợ hiện tại tăng lên 450k, NHƯNG snapshot dư nợ trên biên nhận cũ vẫn giữ nguyên 250k!
        #expect(vm.outstandingBalance(for: student.id) == 450_000)
        #expect(vm.snapshotRemainingBalanceAfterPayment(payment) == 250_000)
    }
}
