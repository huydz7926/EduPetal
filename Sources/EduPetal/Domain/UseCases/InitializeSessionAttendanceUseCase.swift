import Foundation

/// Ca sử dụng Khởi tạo danh sách điểm danh ban đầu cho buổi học
public struct InitializeSessionAttendanceUseCase: Sendable {
    public init() {}

    public func execute(
        sessionId: UUID,
        activeStudentIds: [UUID],
        existingAttendances: [AttendanceEntity]
    ) -> [AttendanceEntity] {
        var results: [AttendanceEntity] = []
        let existingMap = Dictionary(uniqueKeysWithValues: existingAttendances.map { ($0.studentId, $0) })

        for studentId in activeStudentIds {
            if let existing = existingMap[studentId] {
                results.append(existing)
            } else {
                let initial = AttendanceEntity(
                    sessionId: sessionId,
                    studentId: studentId,
                    status: .pending,
                    note: ""
                )
                results.append(initial)
            }
        }

        return results
    }
}

