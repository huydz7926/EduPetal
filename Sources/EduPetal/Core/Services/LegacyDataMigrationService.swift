import Foundation
import SwiftData

/// Dịch vụ kiểm tra và chuyển đổi dữ liệu cũ chưa có `ownerId` (Legacy Data Migration)
/// Nguyên tắc bất biến (Mục 9 của `/duan`):
/// - Tuyệt đối KHÔNG tự động gán dữ liệu chưa có `ownerId` cho tài khoản vừa đăng nhập.
/// - Chỉ gán quyền sở hữu khi người dùng chủ động bấm xác nhận chuyển đổi.
@MainActor
public final class LegacyDataMigrationService {
    public static let shared = LegacyDataMigrationService()

    private static let dismissedMigrationPrefix = "EduPetal_DismissedLegacyMigration_"

    public init() {}

    /// Đếm số lượng bản ghi dữ liệu cũ chưa có `ownerId` (`ownerId == ""`) trong `ModelContext`
    public func countUnownedRecords(in modelContext: ModelContext) -> Int {
        var total = 0
        if let students = try? modelContext.fetch(FetchDescriptor<StudentModel>()) {
            total += students.filter { $0.ownerId.isEmpty }.count
        }
        if let classes = try? modelContext.fetch(FetchDescriptor<ClassGroupModel>()) {
            total += classes.filter { $0.ownerId.isEmpty }.count
        }
        if let sessions = try? modelContext.fetch(FetchDescriptor<TeachingSessionModel>()) {
            total += sessions.filter { $0.ownerId.isEmpty }.count
        }
        if let exams = try? modelContext.fetch(FetchDescriptor<ExamModel>()) {
            total += exams.filter { $0.ownerId.isEmpty }.count
        }
        if let questions = try? modelContext.fetch(FetchDescriptor<QuestionModel>()) {
            total += questions.filter { $0.ownerId.isEmpty }.count
        }
        if let charges = try? modelContext.fetch(FetchDescriptor<ChargeModel>()) {
            total += charges.filter { $0.ownerId.isEmpty }.count
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<PaymentModel>()) {
            total += payments.filter { $0.ownerId.isEmpty }.count
        }
        return total
    }

    /// Kiểm tra xem tài khoản hiện tại đã từ chối thông báo chuyển dữ liệu cũ hay chưa
    public func hasDismissedMigrationPrompt(forOwnerId ownerId: String) -> Bool {
        let key = "\(Self.dismissedMigrationPrefix)\(UserSessionManager.sanitizeIdentifier(ownerId))"
        return UserDefaults.standard.bool(forKey: key)
    }

    public func setDismissedMigrationPrompt(_ dismissed: Bool, forOwnerId ownerId: String) {
        let key = "\(Self.dismissedMigrationPrefix)\(UserSessionManager.sanitizeIdentifier(ownerId))"
        UserDefaults.standard.set(dismissed, forKey: key)
    }

    /// Chỉ thực thi khi người dùng XÁC NHẬN chuyển dữ liệu cũ chưa có `ownerId` vào tài khoản `targetOwnerId`
    @discardableResult
    public func claimUnownedData(
        forOwnerId targetOwnerId: String,
        in modelContext: ModelContext
    ) throws -> Int {
        let cleanOwner = targetOwnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOwner.isEmpty else {
            throw SessionIsolationError.invalidCredentials(reason: "Không xác định được tài khoản đích để nhận dữ liệu.")
        }

        var migratedCount = 0

        if let students = try? modelContext.fetch(FetchDescriptor<StudentModel>()) {
            for item in students where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let classes = try? modelContext.fetch(FetchDescriptor<ClassGroupModel>()) {
            for item in classes where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let sessions = try? modelContext.fetch(FetchDescriptor<TeachingSessionModel>()) {
            for item in sessions where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let exams = try? modelContext.fetch(FetchDescriptor<ExamModel>()) {
            for item in exams where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let questions = try? modelContext.fetch(FetchDescriptor<QuestionModel>()) {
            for item in questions where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let examResults = try? modelContext.fetch(FetchDescriptor<ExamResultModel>()) {
            for item in examResults where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let charges = try? modelContext.fetch(FetchDescriptor<ChargeModel>()) {
            for item in charges where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<PaymentModel>()) {
            for item in payments where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let assignments = try? modelContext.fetch(FetchDescriptor<AssignmentModel>()) {
            for item in assignments where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }
        if let assessments = try? modelContext.fetch(FetchDescriptor<AssessmentModel>()) {
            for item in assessments where item.ownerId.isEmpty {
                item.ownerId = cleanOwner
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            try modelContext.save()
        }
        return migratedCount
    }
}

