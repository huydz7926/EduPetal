import Foundation

/// Ca sử dụng tự động sinh các Khoản học phí khi Buổi học hoàn thành (Idempotent Charge Generation)
/// Đảm bảo tính nhất quán dữ liệu, snapshot đơn giá và chống tạo trùng tuyệt đối
public struct GenerateSessionChargesUseCase: Sendable {
    private let priceUseCase = GetEffectiveStudentPriceUseCase()

    public init() {}

    public func execute(
        session: TeachingSessionEntity,
        attendances: [AttendanceEntity],
        students: [StudentEntity],
        classGroup: ClassGroupEntity,
        existingCharges: [ChargeEntity]
    ) -> [ChargeEntity] {
        // Chỉ sinh học phí khi buổi học có trạng thái .completed
        guard session.status == .completed else { return [] }

        let studentMap = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        // Tập hợp các studentId đã có Charge trong buổi học này (Idempotency Check)
        let existingStudentIds = Set(existingCharges.filter { $0.sessionId == session.id }.map { $0.studentId })

        var newCharges: [ChargeEntity] = []

        for att in attendances where att.sessionId == session.id {
            // Kiểm tra chống tạo trùng (Idempotency)
            if existingStudentIds.contains(att.studentId) {
                continue
            }

            guard let student = studentMap[att.studentId] else { continue }

            // Chỉ tính học phí cho học sinh có mặt (.present)
            if att.status == .present {
                let unitPrice = priceUseCase.execute(student: student, classGroup: classGroup)
                if unitPrice > 0 {
                    let charge = ChargeEntity(
                        sessionId: session.id,
                        studentId: student.id,
                        amount: unitPrice,
                        unitPriceSnapshot: unitPrice,
                        status: .unpaid,
                        createdAt: session.startTime
                    )
                    newCharges.append(charge)
                }
            }
        }

        return newCharges
    }
}

