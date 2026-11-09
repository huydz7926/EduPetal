import Foundation

// MARK: - Backup Export DTOs

public struct StudentExportDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let fullName: String
    public let phoneNumber: String
    public let parentPhone: String
    public let email: String
    public let defaultPricePerSession: Int64?
    public let isArchived: Bool
    public let notes: String
    public let createdAt: Date
}

public struct ClassExportDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let subject: String
    public let sessionDurationMinutes: Int
    public let defaultPricePerSession: Int64
    public let colorHex: String
    public let isArchived: Bool
    public let createdAt: Date
}

public struct SessionExportDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let classId: UUID
    public let title: String
    public let startTime: Date
    public let endTime: Date
    public let status: String
    public let lessonNotes: String
}

public struct ChargeExportDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionId: UUID
    public let studentId: UUID
    public let amount: Int64
    public let unitPriceSnapshot: Int64
    public let status: String
    public let createdAt: Date
}

public struct PaymentExportDTO: Codable, Sendable, Equatable {
    public let id: UUID
    public let studentId: UUID
    public let amount: Int64
    public let paidAt: Date
    public let paymentMethod: String
    public let note: String
}

/// DTO gói toàn bộ dữ liệu sao lưu của EduPetal
public struct EduPetalBackupData: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let appVersion: String
    public let exportedAt: Date
    public let teacherName: String
    public let studentsCount: Int
    public let classesCount: Int
    public let sessionsCount: Int
    public let chargesCount: Int
    public let paymentsCount: Int

    public let students: [StudentExportDTO]
    public let classes: [ClassExportDTO]
    public let sessions: [SessionExportDTO]
    public let charges: [ChargeExportDTO]
    public let payments: [PaymentExportDTO]
}

/// Tóm tắt kết quả kiểm tra tính toàn vẹn của tệp sao lưu
public struct BackupSummary: Sendable, Equatable {
    public let schemaVersion: String
    public let exportedAt: Date
    public let studentsCount: Int
    public let classesCount: Int
    public let sessionsCount: Int
    public let chargesCount: Int
    public let paymentsCount: Int
}

// MARK: - Backup Export Service

public struct BackupExportService: Sendable {
    public init() {}

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Xuất toàn bộ dữ liệu ra đối tượng Codable EduPetalBackupData
    public func createBackup(
        teacherName: String = "Giáo viên EduPetal",
        students: [StudentEntity],
        classes: [ClassGroupEntity],
        sessions: [TeachingSessionEntity],
        charges: [ChargeEntity],
        payments: [PaymentEntity],
        now: Date = Date()
    ) -> EduPetalBackupData {
        let studentDTOs = students.map {
            StudentExportDTO(
                id: $0.id,
                fullName: $0.fullName,
                phoneNumber: $0.phoneNumber,
                parentPhone: $0.parentPhone,
                email: $0.email,
                defaultPricePerSession: $0.defaultPricePerSession,
                isArchived: $0.isArchived,
                notes: $0.notes,
                createdAt: $0.createdAt
            )
        }

        let classDTOs = classes.map {
            ClassExportDTO(
                id: $0.id,
                name: $0.name,
                subject: $0.subject,
                sessionDurationMinutes: $0.sessionDurationMinutes,
                defaultPricePerSession: $0.defaultPricePerSession,
                colorHex: $0.colorHex,
                isArchived: $0.isArchived,
                createdAt: $0.createdAt
            )
        }

        let sessionDTOs = sessions.map {
            SessionExportDTO(
                id: $0.id,
                classId: $0.classId,
                title: $0.title,
                startTime: $0.startTime,
                endTime: $0.endTime,
                status: $0.status.rawValue,
                lessonNotes: $0.lessonNotes
            )
        }

        let chargeDTOs = charges.map {
            ChargeExportDTO(
                id: $0.id,
                sessionId: $0.sessionId,
                studentId: $0.studentId,
                amount: $0.amount,
                unitPriceSnapshot: $0.unitPriceSnapshot,
                status: $0.status.rawValue,
                createdAt: $0.createdAt
            )
        }

        let paymentDTOs = payments.map {
            PaymentExportDTO(
                id: $0.id,
                studentId: $0.studentId,
                amount: $0.amount,
                paidAt: $0.paidAt,
                paymentMethod: $0.paymentMethod,
                note: $0.note
            )
        }

        return EduPetalBackupData(
            schemaVersion: "1.0.0",
            appVersion: "1.0.0",
            exportedAt: now,
            teacherName: teacherName,
            studentsCount: studentDTOs.count,
            classesCount: classDTOs.count,
            sessionsCount: sessionDTOs.count,
            chargesCount: chargeDTOs.count,
            paymentsCount: paymentDTOs.count,
            students: studentDTOs,
            classes: classDTOs,
            sessions: sessionDTOs,
            charges: chargeDTOs,
            payments: paymentDTOs
        )
    }

    /// Chuyển đổi dữ liệu sao lưu thành Data JSON có định dạng đẹp (Pretty Printed)
    public func exportToJSONData(
        teacherName: String = "Giáo viên EduPetal",
        students: [StudentEntity],
        classes: [ClassGroupEntity],
        sessions: [TeachingSessionEntity],
        charges: [ChargeEntity],
        payments: [PaymentEntity],
        now: Date = Date()
    ) throws -> Data {
        let backup = createBackup(
            teacherName: teacherName,
            students: students,
            classes: classes,
            sessions: sessions,
            charges: charges,
            payments: payments,
            now: now
        )
        return try jsonEncoder.encode(backup)
    }

    /// Giải mã và kiểm tra tính toàn vẹn của tệp JSON sao lưu
    public func verifyBackupIntegrity(data: Data) throws -> BackupSummary {
        let decoded = try jsonDecoder.decode(EduPetalBackupData.self, from: data)

        // Kiểm tra tính nhất quán giữa trường count và số phần tử thực tế
        guard decoded.studentsCount == decoded.students.count,
              decoded.classesCount == decoded.classes.count,
              decoded.sessionsCount == decoded.sessions.count,
              decoded.chargesCount == decoded.charges.count,
              decoded.paymentsCount == decoded.payments.count else {
            throw BackupError.integrityCheckFailed
        }

        return BackupSummary(
            schemaVersion: decoded.schemaVersion,
            exportedAt: decoded.exportedAt,
            studentsCount: decoded.studentsCount,
            classesCount: decoded.classesCount,
            sessionsCount: decoded.sessionsCount,
            chargesCount: decoded.chargesCount,
            paymentsCount: decoded.paymentsCount
        )
    }
}

public enum BackupError: Error, LocalizedError, Equatable {
    case integrityCheckFailed

    public var errorDescription: String? {
        switch self {
        case .integrityCheckFailed:
            return "Kiểm tra tính toàn vẹn của tệp sao lưu thất bại: Số lượng bản ghi thực tế không khớp với thông tin header."
        }
    }
}
