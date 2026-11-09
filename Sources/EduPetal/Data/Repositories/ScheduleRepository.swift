import Foundation
import SwiftData

/// Hiện thực hóa ScheduleRepositoryProtocol sử dụng SwiftData (Có kiểm soát cô lập `ownerId` theo phiên người dùng)
@MainActor
public final class ScheduleRepository: ScheduleRepositoryProtocol {
    private let modelContext: ModelContext
    private let explicitOwnerId: String?
    /// Ánh xạ ID buổi học bị trùng (classId + startTime) sang ID thực tế trong DB
    private var mergedSessionIdMap: [UUID: UUID] = [:]

    public var activeOwnerId: String {
        explicitOwnerId ?? UserSessionManager.shared.currentOwnerId
    }

    public init(modelContainer: ModelContainer, ownerId: String? = nil) {
        self.modelContext = modelContainer.mainContext
        self.explicitOwnerId = ownerId
    }

    public init(modelContext: ModelContext, ownerId: String? = nil) {
        self.modelContext = modelContext
        self.explicitOwnerId = ownerId
    }

    // MARK: - Session Operations

    public func fetchSessions(from startDate: Date, to endDate: Date) async throws -> [TeachingSessionEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<TeachingSessionModel>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        let allModels = try modelContext.fetch(descriptor)
        let filtered = allModels.filter { model in
            model.ownerId == currentOwner &&
            model.startTime >= startDate &&
            model.startTime <= endDate
        }
        return filtered.map { SessionMapper.toEntity($0) }
    }

    public func fetchSession(byId id: UUID) async throws -> TeachingSessionEntity? {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first,
              model.ownerId == currentOwner else {
            return nil
        }
        return SessionMapper.toEntity(model)
    }

    public func fetchSessionsForClass(classId: UUID) async throws -> [TeachingSessionEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.classId == classId },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let models = try modelContext.fetch(descriptor)
        return models
            .filter { $0.ownerId == currentOwner }
            .map { SessionMapper.toEntity($0) }
    }

    public func saveSession(_ session: TeachingSessionEntity) async throws {
        let currentOwner = activeOwnerId
        if !session.ownerId.isEmpty && session.ownerId != currentOwner {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: session.ownerId,
                currentUserId: currentOwner
            )
        }

        let sessionId = session.id
        let descriptor = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == sessionId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            var owned = session
            owned.ownerId = currentOwner
            SessionMapper.updateModel(existing, from: owned)
            try modelContext.save()
            return
        }

        // Chống tạo trùng buổi học của cùng một lớp tại cùng thời điểm bắt đầu trong phạm vi cùng ownerId
        let targetClassId = session.classId
        let classDesc = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.classId == targetClassId }
        )
        let classSessions = try modelContext.fetch(classDesc).filter { $0.ownerId == currentOwner }
        if let duplicate = classSessions.first(where: {
            $0.statusRaw != SessionStatus.cancelled.rawValue &&
            abs($0.startTime.timeIntervalSince(session.startTime)) < 60
        }) {
            mergedSessionIdMap[session.id] = duplicate.id
            duplicate.title = session.title
            duplicate.endTime = session.endTime
            duplicate.lessonNotes = session.lessonNotes
            duplicate.homeworkAssigned = session.homeworkAssigned
            duplicate.updatedAt = Date()
            try modelContext.save()
            return
        }

        var owned = session
        owned.ownerId = currentOwner
        let newModel = SessionMapper.toModel(owned)
        modelContext.insert(newModel)
        try modelContext.save()
    }

    public func deleteSession(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let resolvedId = mergedSessionIdMap[id] ?? id
        let descriptor = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == resolvedId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.ownerId == currentOwner else {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: existing.ownerId,
                    currentUserId: currentOwner
                )
            }
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Attendance Operations

    public func fetchAttendances(forSessionId sessionId: UUID) async throws -> [AttendanceEntity] {
        let currentOwner = activeOwnerId
        let resolvedId = mergedSessionIdMap[sessionId] ?? sessionId
        let sessionDesc = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == resolvedId }
        )
        guard let sessionModel = try modelContext.fetch(sessionDesc).first,
              sessionModel.ownerId == currentOwner else {
            return []
        }
        return sessionModel.attendances.map { SessionMapper.toAttendanceEntity($0) }
    }

    public func fetchAttendancesForStudent(studentId: UUID) async throws -> [AttendanceEntity] {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<AttendanceModel>()
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { $0.studentId == studentId && $0.session?.ownerId == currentOwner }
        return filtered.map { SessionMapper.toAttendanceEntity($0) }
    }

    public func saveAttendance(_ attendance: AttendanceEntity) async throws {
        try await saveAttendances([attendance])
    }

    public func saveAttendances(_ attendances: [AttendanceEntity]) async throws {
        let currentOwner = activeOwnerId
        guard let first = attendances.first else { return }
        let resolvedId = mergedSessionIdMap[first.sessionId] ?? first.sessionId
        let sessionDesc = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == resolvedId }
        )
        guard let sessionModel = try modelContext.fetch(sessionDesc).first else {
            return
        }
        guard sessionModel.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: sessionModel.ownerId,
                currentUserId: currentOwner
            )
        }

        for item in attendances {
            if let existing = sessionModel.attendances.first(where: { $0.studentId == item.studentId }) {
                existing.statusRaw = item.status.rawValue
                existing.note = item.note
                existing.markedAt = item.markedAt ?? Date()
            } else {
                let newModel = AttendanceModel(
                    id: item.id,
                    session: sessionModel,
                    studentId: item.studentId,
                    statusRaw: item.status.rawValue,
                    note: item.note,
                    markedAt: item.markedAt ?? Date()
                )
                modelContext.insert(newModel)
                sessionModel.attendances.append(newModel)
            }
        }
        try modelContext.save()
    }

    // MARK: - Attachment Operations

    public func fetchAttachments(forSessionId sessionId: UUID) async throws -> [SessionAttachmentEntity] {
        let currentOwner = activeOwnerId
        let sessionDesc = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == sessionId }
        )
        guard let sessionModel = try modelContext.fetch(sessionDesc).first,
              sessionModel.ownerId == currentOwner else {
            return []
        }
        return sessionModel.attachments.map { SessionMapper.toAttachmentEntity($0) }
    }

    public func addAttachment(_ attachment: SessionAttachmentEntity) async throws {
        let currentOwner = activeOwnerId
        let sessionId = attachment.sessionId
        let sessionDesc = FetchDescriptor<TeachingSessionModel>(
            predicate: #Predicate<TeachingSessionModel> { $0.id == sessionId }
        )
        guard let sessionModel = try modelContext.fetch(sessionDesc).first else {
            return
        }
        guard sessionModel.ownerId == currentOwner else {
            throw SessionIsolationError.unauthorizedRecordAccess(
                ownerId: sessionModel.ownerId,
                currentUserId: currentOwner
            )
        }

        let newModel = SessionAttachmentModel(
            id: attachment.id,
            session: sessionModel,
            filePath: attachment.filePath,
            fileType: attachment.fileType,
            caption: attachment.caption,
            createdAt: attachment.createdAt
        )
        modelContext.insert(newModel)
        sessionModel.attachments.append(newModel)
        try modelContext.save()
    }

    public func deleteAttachment(id: UUID) async throws {
        let currentOwner = activeOwnerId
        let descriptor = FetchDescriptor<SessionAttachmentModel>(
            predicate: #Predicate<SessionAttachmentModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            if let sessionOwner = existing.session?.ownerId, sessionOwner != currentOwner {
                throw SessionIsolationError.unauthorizedRecordAccess(
                    ownerId: sessionOwner,
                    currentUserId: currentOwner
                )
            }
            modelContext.delete(existing)
            try modelContext.save()
        }
    }
}
