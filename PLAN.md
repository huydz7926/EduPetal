# EDUPETAL — DEVELOPMENT PLAN & ROADMAP (PLAN.md)

**Project:** EduPetal ("Where Teaching Blossoms")  
**Target:** iOS 17.0+ | Swift 6.2 | SwiftUI | SwiftData | Clean Architecture  
**Bundle Identifier:** `com.edupetal.app` (Team: `5Z73BW7X4C`)  
**Navigation Scope:** 5 Main Tabs (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Lớp học`, `Học phí`)  

---

## 1. LỘ TRÌNH CHỈNH SỬA & HOÀN THIỆN SẢN PHẨM THEO `/duan` (7 BƯỚC)

Kế hoạch này thay thế hoàn toàn kế hoạch phát triển Đề thi trước đây: loại bỏ tính năng Đề thi, thay bằng tab **Lớp học**, sửa triệt để thông báo nhắc lịch và tối ưu trải nghiệm cho người dùng mới.

| Bước | Hạng mục công việc | Trọng tâm bàn giao | Kiểm thử & Xác nhận |
| :---: | :--- | :--- | :---: |
| **Bước 1** | **Điều tra và sửa lỗi không nhận thông báo** | Nhắc trước buổi dạy 60 phút & Nhắc xem/thêm lịch lúc 22:00 hằng ngày; công tắc riêng; chỉnh giờ không tạo trùng; chạm thông báo mở đúng màn hình Lịch/Chi tiết buổi; hủy lời nhắc khi đổi tài khoản; nút test giờ gần hiện tại & khôi phục 22:00 | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 2** | **Gỡ Đề thi khỏi điều hướng và thay bằng tab Lớp học** | Thanh điều hướng 5 tab (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Lớp học`, `Học phí`); danh sách lớp hiển thị buổi dạy tiếp theo, số học sinh, đơn giá mặc định; bảo vệ dữ liệu tài chính khi lưu trữ/xóa lớp | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 3** | **Hoàn thiện Tạo lớp và Thêm học sinh** | Tạo lớp bắt buộc tên lớp + đơn giá hợp lệ ($> 0$), hiện sẵn phần bổ sung tùy chọn kèm **16 màu nhận diện lớp**, chống lưu trùng; thêm học sinh có sẵn hoặc tạo học sinh mới ngay trong Chi tiết lớp (chưa phát sinh học phí) | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 4** | **Hoàn thiện Lịch theo tháng và Chi tiết lớp** | Chi tiết lớp 4 phân khu (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Học phí`); thiết lập lịch theo tháng; mở buổi dạy để điểm danh/hoàn thành; xem khoản phải thu, lịch sử thu tiền và ghi nhận thanh toán trong lớp | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 5** | **Hoàn thiện Trải nghiệm người dùng lần đầu** | Luồng khởi đầu ngắn 3 bước (`1. Tạo lớp` $\rightarrow$ `2. Thêm học sinh` $\rightarrow$ `3. Lên lịch buổi đầu`); tự chuyển sang bước tiếp theo; cho phép bỏ qua theo từng `ownerId`; không tự chèn dữ liệu demo | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 6** | **Dọn phần code Đề thi còn dư & Migration an toàn** | Xóa toàn bộ UI, ViewModel, UseCase, Repository, Mapper, PDF Renderer và test của Đề thi; giữ 5 `@Model` thụ động trong `EduPetalSchemaV1` để tương thích ngược cơ sở dữ liệu cũ (không reset DB); bảo toàn Biên nhận PDF học phí, Điểm số, Ảnh minh chứng và Backup JSON | 🟢 **Đã hoàn thành & xác nhận** |
| **Bước 7** | **Kiểm thử hồi quy toàn bộ và tinh chỉnh giao diện** | Giảm thẻ lồng thẻ và nút/thông tin lặp; mỗi màn hình có 1 hành động chính rõ ràng; đồng bộ từ điển song ngữ Việt–Anh; chạy toàn bộ **139 bài test trên 8 test suites** và cài đặt kiểm chứng trên iPhone thật | 🟢 **Đã hoàn thành & xác nhận** |

---

## 2. KIẾN TRÚC PHÂN HỆ HIỆN TẠI (ACTIVE MODULES)

### Module 1 — Tổng quan (`Features/Home/`)
- **Files chính:** `HomeView.swift`, `HomeViewModel.swift`, `CalculateDashboardMetricsUseCase.swift`.
- **Chức năng:**
  - Thẻ hướng dẫn khởi đầu 3 bước (`FirstTimeSetupStep`: `.createClass` $\rightarrow$ `.addStudent` $\rightarrow$ `.scheduleFirstSession` $\rightarrow$ `.completed`).
  - 3 thẻ KPI cân đối (`Học sinh`, `Lớp học`, `Ca hôm nay`), thẻ `Tài chính học phí`, cảnh báo `Việc cần chú ý`, `Lịch dạy hôm nay` và `Thao tác nhanh`.

### Module 2 — Học sinh (`Features/Students/`)
- **Files chính:** `StudentListView.swift`, `StudentListViewModel.swift`, `StudentDetailView.swift`, `StudentDetailViewModel.swift`, `StudentEditView.swift`.
- **Chức năng:**
  - Danh sách học sinh hiển thị trực tiếp số lớp tham gia và chi tiết lớp.
  - Hồ sơ học sinh 4 phân khu (`Tổng quan`, `Điểm số`, `Học phí`, `Lớp học`), lưu trữ (`Archive`), khôi phục và kiểm tra công nợ trước khi xóa.

### Module 3 — Lịch dạy & Điểm danh (`Features/Schedule/`)
- **Files chính:** `ScheduleCalendarView.swift`, `ScheduleViewModel.swift`, `SessionDetailView.swift`, `SessionEditView.swift`, `CompleteTeachingSessionUseCase.swift`, `CheckScheduleOverlapUseCase.swift`, `GenerateRecurringSessionsUseCase.swift`.
- **Chức năng:**
  - Lịch ngày/tuần/tháng, kiểm tra trùng giờ, tạo chuỗi lịch lặp, điểm danh 1-chạm, đính kèm ảnh minh chứng và hoàn thành buổi dạy sinh khoản phải thu idempotent.
  - Đồng bộ tự động với `LocalNotificationService` khi tạo, sửa, hủy, xóa hoặc hoàn thành buổi dạy.

### Module 4 — Lớp học (`Features/Classes/`)
- **Files chính:** `ClassListView.swift`, `ClassListViewModel.swift`, `ClassDetailView.swift`, `ClassDetailViewModel.swift`, `ClassEditView.swift`.
- **Chức năng:**
  - Danh sách lớp học, tạo/sửa lớp với 16 màu nhận diện, chi tiết lớp 4 phân khu (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Học phí`), thêm học sinh có sẵn/tạo mới, thiết lập lịch theo tháng, thu học phí theo lớp và lưu trữ/xóa lớp an toàn không làm mất dữ liệu tài chính lịch sử.

### Module 5 — Học phí & Biên nhận PDF (`Features/Finance/`, `Data/PDF/ReceiptPDFRenderer.swift`)
- **Files chính:** `FinanceDashboardView.swift`, `FinanceViewModel.swift`, `RecordPaymentSheet.swift`, `ReceiptPreviewSheet.swift`, `ReceiptPDFRenderer.swift`.
- **Chức năng:**
  - Quản lý học phí Single-Source ($\text{Accrued} - \text{Collected} = \text{Outstanding}$), kiểu `Int64` VND, snapshot đơn giá theo buổi, chống tạo trùng, phân bổ thanh toán FIFO/chọn buổi, VietQR và xuất Biên nhận học phí PDF khổ A4.

### Module 6 — Xác thực, Cô lập Đa người dùng & Cài đặt (`Core/Services/`, `Features/Auth/`, `Features/Settings/`)
- **Files chính:** `UserSessionManager.swift`, `GoogleOAuthService.swift`, `AppleSignInService.swift`, `LocalNotificationService.swift`, `BackupExportService.swift`, `SettingsView.swift`, `LoginView.swift`.
- **Chức năng:**
  - Đăng nhập Apple/Google thật, cô lập dữ liệu và tệp theo `ownerId`, cài đặt thông báo nhắc lịch, chuyển đổi chủ đề Sáng/Tối, ngôn ngữ Việt/Anh và sao lưu JSON.

---

## 3. BẢNG PHÂN TÍCH RỦI RO KỸ THUẬT & PHƯƠNG ÁN GIẢM THIỂU

| STT | Rủi ro kỹ thuật | Mức độ | Phương án giải quyết đã triển khai |
| :---: | :--- | :---: | :--- |
| **1** | **Tạo trùng học phí khi bấm Hoàn thành nhiều lần** | **Nghiêm trọng** | Sử dụng `idempotencyKey` (`sessionId_studentId`) trong `GenerateSessionChargesUseCase` và `FinanceRepository` để đảm bảo mỗi học sinh có mặt chỉ phát sinh tối đa 1 khoản thu cho mỗi buổi. |
| **2** | **Mất lịch sử tài chính khi lưu trữ hoặc xóa lớp/học sinh** | **Nghiêm trọng** | Ưu tiên lưu trữ (`isArchived = true`); khi xóa lớp chỉ xóa các buổi chưa diễn ra (`scheduled`/`cancelled`), giữ nguyên 100% các buổi `completed` và toàn bộ bản ghi `Charge` / `Payment`. |
| **3** | **Reset database trên máy người dùng khi gỡ tính năng Đề thi** | **Nghiêm trọng** | Giữ lại 5 lớp `@Model` thụ động (`QuestionModel`, `AnswerOptionModel`, `ExamModel`, `ExamQuestionModel`, `ExamResultModel`) trong `EduPetalSchemaV1.models` để SQLite hiện có mở an toàn không lỗi migration. |
| **4** | **Lộ thông báo hoặc dữ liệu khi chuyển tài khoản trên cùng thiết bị** | **Cao** | Gắn `ownerId` cho mọi bản ghi và đường dẫn file; gọi `cancelAllUserNotificationsOnSessionChange()` và xóa cache ngay khi đăng xuất hoặc đổi user. |
| **5** | **Vượt giới hạn 64 thông báo chờ của iOS** | **Trung bình** | `LocalNotificationService.syncSessionReminders` lọc các buổi `.scheduled` trong tương lai, sắp xếp tăng dần theo `startTime` và chỉ lên lịch tối đa 48 buổi gần nhất (dành chỗ cho lời nhắc hằng ngày 22:00). |
