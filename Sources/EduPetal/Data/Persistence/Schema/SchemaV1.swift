import Foundation
import SwiftData

/// Định nghĩa phiên bản Schema V1 (1.0.0) của cơ sở dữ liệu SwiftData cho EduPetal
public enum EduPetalSchemaV1: VersionedSchema {
    public static let versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    /// Danh sách các persistent models thuộc Schema V1
    public static var models: [any PersistentModel.Type] {
        [
            StudentModel.self,
            ClassGroupModel.self,
            EnrollmentModel.self,
            TeachingSessionModel.self,
            AttendanceModel.self,
            SessionAttachmentModel.self,
            AssignmentModel.self,
            AssignmentRecordModel.self,
            AssessmentModel.self,
            GradeModel.self,
            // Các model legacy bên dưới chỉ giữ trong Schema V1 để tương thích ngược cơ sở dữ liệu
            // SwiftData hiện có trên thiết bị người dùng (không reset DB, không còn tính năng Đề thi hoạt động):
            QuestionModel.self,
            AnswerOptionModel.self,
            ExamModel.self,
            ExamQuestionModel.self,
            ExamResultModel.self,
            ChargeModel.self,
            PaymentModel.self,
            PaymentAllocationModel.self
        ]
    }
}
