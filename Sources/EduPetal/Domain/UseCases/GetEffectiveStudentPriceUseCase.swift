import Foundation

/// Ca sử dụng tính toán Đơn giá học phí hiệu dụng cho một học sinh trong một lớp học
/// Quy tắc: Đơn giá riêng của học sinh (nếu có) luôn ghi đè đơn giá mặc định của lớp
public struct GetEffectiveStudentPriceUseCase: Sendable {
    public init() {}

    public func execute(student: StudentEntity, classGroup: ClassGroupEntity) -> Int64 {
        if let customPrice = student.defaultPricePerSession, customPrice > 0 {
            return customPrice
        }
        return classGroup.defaultPricePerSession
    }
}

