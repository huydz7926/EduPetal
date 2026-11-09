import Foundation
import SwiftUI
import Observation

/// ViewModel quản lý Danh sách Học sinh (Presentation Layer)
@Observable
@MainActor
public final class StudentListViewModel {
    public var students: [StudentEntity] = []
    public var classes: [ClassGroupEntity] = []
    public var enrolledClassesByStudentId: [UUID: [ClassGroupEntity]] = [:]
    public var searchQuery: String = ""
    public var selectedClassId: UUID? = nil
    public var showArchived: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    // Quản lý Trạng thái Xác nhận Lưu trữ & Cảnh báo Buổi học tương lai
    public var studentToArchiveWithUpcomingSessions: (student: StudentEntity, upcomingCount: Int)? = nil

    // Quản lý Trạng thái Xác nhận Xóa & Chặn xóa do công nợ
    public var studentToDelete: StudentEntity? = nil
    public var studentBlockedFromDelete: (student: StudentEntity, debtAmount: Int64)? = nil

    public let studentRepository: StudentRepositoryProtocol
    public let classRepository: ClassRepositoryProtocol
    public let scheduleRepository: ScheduleRepositoryProtocol?
    public let financeRepository: FinanceRepositoryProtocol?
    private let filterUseCase = FilterStudentsUseCase()

    public init(
        studentRepository: StudentRepositoryProtocol,
        classRepository: ClassRepositoryProtocol,
        scheduleRepository: ScheduleRepositoryProtocol? = nil,
        financeRepository: FinanceRepositoryProtocol? = nil
    ) {
        self.studentRepository = studentRepository
        self.classRepository = classRepository
        self.scheduleRepository = scheduleRepository
        self.financeRepository = financeRepository
    }

    /// Lọc danh sách học sinh theo từ khóa, trạng thái lưu trữ và lớp học
    public var filteredStudents: [StudentEntity] {
        let base = filterUseCase.execute(
            students: students,
            query: searchQuery,
            showArchivedOnly: showArchived
        )
        guard let selectedClassId else { return base }
        return base.filter { student in
            (enrolledClassesByStudentId[student.id] ?? []).contains(where: { $0.id == selectedClassId })
        }
    }

    /// Lấy danh sách lớp đang tham gia của một học sinh
    public func enrolledClasses(for studentId: UUID) -> [ClassGroupEntity] {
        enrolledClassesByStudentId[studentId] ?? []
    }

    public func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedStudents = try await studentRepository.fetchStudents(includeArchived: true)
            let loadedAllClasses = try await classRepository.fetchClasses(includeArchived: true)

            let classesById = Dictionary(uniqueKeysWithValues: loadedAllClasses.map { ($0.id, $0) })
            var enrollmentMap: [UUID: [ClassGroupEntity]] = [:]

            for student in loadedStudents {
                let activeEnrollments = (try? await classRepository.fetchEnrollments(forStudentId: student.id, activeOnly: true)) ?? []
                let studentClasses = activeEnrollments.compactMap { classesById[$0.classId] }
                enrollmentMap[student.id] = studentClasses
            }

            self.students = loadedStudents
            self.classes = loadedAllClasses.filter { !$0.isArchived }
            self.enrolledClassesByStudentId = enrollmentMap
        } catch {
            self.errorMessage = "Không thể tải danh sách học sinh: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Yêu cầu lưu trữ học sinh: Kiểm tra xem học sinh có buổi dạy trong tương lai đã xếp lịch không
    public func requestArchive(student: StudentEntity) async {
        guard let schRepo = scheduleRepository else {
            await executeArchive(id: student.id)
            return
        }

        do {
            let now = Date()
            let futureEnd = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
            let futureSessions = try await schRepo.fetchSessions(from: now, to: futureEnd)
            let upcomingScheduled = futureSessions.filter { $0.status == .scheduled && $0.startTime >= now }

            var upcomingCount = 0
            for session in upcomingScheduled {
                let attendances = try await schRepo.fetchAttendances(forSessionId: session.id)
                if attendances.contains(where: { $0.studentId == student.id }) {
                    upcomingCount += 1
                }
            }

            if upcomingCount > 0 {
                // Hiển thị cảnh báo để giáo viên biết và xử lý rõ ràng
                self.studentToArchiveWithUpcomingSessions = (student, upcomingCount)
            } else {
                await executeArchive(id: student.id)
            }
        } catch {
            await executeArchive(id: student.id)
        }
    }

    /// Thực hiện lưu trữ học sinh và bảo toàn 100% dữ liệu lịch sử
    public func executeArchive(id: UUID) async {
        do {
            try await studentRepository.archiveStudent(id: id)
            withAnimation(.easeInOut(duration: 0.25)) {
                if let idx = students.firstIndex(where: { $0.id == id }) {
                    students[idx].isArchived = true
                }
            }
            await loadData()
        } catch {
            self.errorMessage = "Không thể lưu trữ học sinh: \(error.localizedDescription)"
        }
    }

    /// Khôi phục học sinh từ danh sách lưu trữ về danh sách đang học
    public func restoreStudent(id: UUID) async {
        do {
            try await studentRepository.restoreStudent(id: id)
            withAnimation(.easeInOut(duration: 0.25)) {
                if let idx = students.firstIndex(where: { $0.id == id }) {
                    students[idx].isArchived = false
                }
            }
            await loadData()
        } catch {
            self.errorMessage = "Không thể khôi phục học sinh: \(error.localizedDescription)"
        }
    }

    /// Yêu cầu xóa học sinh: Kiểm tra công nợ học phí, chặn xóa nếu còn nợ để bảo toàn tài chính
    public func requestDelete(student: StudentEntity) async {
        guard let finRepo = financeRepository else {
            self.studentToDelete = student
            return
        }

        do {
            let charges = try await finRepo.fetchChargesForStudent(studentId: student.id)
            let payments = try await finRepo.fetchPaymentsForStudent(studentId: student.id)

            let totalAccrued = charges.reduce(0 as Int64) { $0 + $1.amount }
            let totalCollected = payments.reduce(0 as Int64) { $0 + $1.amount }
            let outstandingBalance = max(0, totalAccrued - totalCollected)
            let hasUnpaidCharges = charges.contains { $0.status != .paid }
            let hasFinancialHistory = !charges.isEmpty || !payments.isEmpty

            if outstandingBalance > 0 || hasUnpaidCharges || hasFinancialHistory {
                // Chặn xóa và gợi ý giáo viên chọn Lưu trữ
                self.studentBlockedFromDelete = (student, outstandingBalance)
            } else {
                // Không có công nợ hoặc lịch sử tài chính -> hiển thị hộp thoại xác nhận xóa vĩnh viễn
                self.studentToDelete = student
            }
        } catch {
            self.errorMessage = "Không thể kiểm tra công nợ học sinh: \(error.localizedDescription)"
        }
    }

    /// Thực hiện xóa học sinh vĩnh viễn sau khi người dùng đã xác nhận
    public func executeDelete(id: UUID) async {
        do {
            try await studentRepository.deleteStudent(id: id)
            withAnimation(.easeInOut(duration: 0.25)) {
                students.removeAll(where: { $0.id == id })
            }
            await loadData()
        } catch {
            self.errorMessage = "Không thể xóa học sinh: \(error.localizedDescription)"
        }
    }
}

