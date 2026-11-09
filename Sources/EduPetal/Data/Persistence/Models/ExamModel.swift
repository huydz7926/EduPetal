import Foundation
import SwiftData

/// Mô hình lưu trữ dữ liệu SwiftData cho Đề thi
@Model
public final class ExamModel {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var subject: String
    public var gradeLevel: String
    public var durationMinutes: Int
    public var instructions: String
    public var isPublished: Bool
    public var totalScore: Double
    public var createdAt: Date
    public var updatedAt: Date

    // Mở rộng cho Đề thi từ tài liệu (Section 7)
    public var examTypeRaw: String = "questionBank"
    public var documentFormatRaw: String? = nil
    public var documentFilePath: String? = nil
    public var sourceImageFilePaths: [String] = []
    public var teacherKeyFilePath: String? = nil
    public var pageCount: Int = 0
    public var note: String = ""
    public var ownerId: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ExamQuestionModel.exam)
    public var examQuestions: [ExamQuestionModel] = []

    public init(
        id: UUID = UUID(),
        title: String,
        subject: String = "",
        gradeLevel: String = "",
        durationMinutes: Int = 45,
        instructions: String = "",
        isPublished: Bool = false,
        totalScore: Double = 10.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        examTypeRaw: String = "questionBank",
        documentFormatRaw: String? = nil,
        documentFilePath: String? = nil,
        sourceImageFilePaths: [String] = [],
        teacherKeyFilePath: String? = nil,
        pageCount: Int = 0,
        note: String = "",
        ownerId: String = ""
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.gradeLevel = gradeLevel
        self.durationMinutes = durationMinutes
        self.instructions = instructions
        self.isPublished = isPublished
        self.totalScore = totalScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.examTypeRaw = examTypeRaw
        self.documentFormatRaw = documentFormatRaw
        self.documentFilePath = documentFilePath
        self.sourceImageFilePaths = sourceImageFilePaths
        self.teacherKeyFilePath = teacherKeyFilePath
        self.pageCount = pageCount
        self.note = note
        self.ownerId = ownerId
        self.examQuestions = []
    }
}

