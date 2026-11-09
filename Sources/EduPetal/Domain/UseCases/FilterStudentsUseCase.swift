import Foundation

/// Ca sử dụng tìm kiếm và lọc danh sách học sinh theo từ khóa và trạng thái lưu trữ
public struct FilterStudentsUseCase: Sendable {
    public init() {}

    public func execute(
        students: [StudentEntity],
        query: String,
        showArchivedOnly: Bool
    ) -> [StudentEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return students.filter { student in
            let matchesArchiveStatus = showArchivedOnly ? student.isArchived : !student.isArchived
            guard matchesArchiveStatus else { return false }

            if trimmed.isEmpty {
                return true
            }

            return student.fullName.lowercased().contains(trimmed) ||
                   student.phoneNumber.contains(trimmed) ||
                   student.parentPhone.contains(trimmed) ||
                   student.email.lowercased().contains(trimmed)
        }
    }
}

