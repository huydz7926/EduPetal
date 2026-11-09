# EDUPETAL — PROJECT PROGRESS TRACKER (PROGRESS.md)

**Current Status:** ALL 5 STEPS OF UI SIMPLIFICATION & CRASH FIX ROADMAP COMPLETED (100%) 🌸  
**Active Navigation Scope:** 5 Tabs (`Trang chủ`, `Học sinh`, `Lớp học`, `Lịch dạy`, `Học phí`)  
**Total Automated Tests:** **143 / 143 PASS (100% Pass Rate across 8 Test Suites)**  
**Device Verification:** Built, Installed & Verified Running on iPhone 15 Pro Max (`com.edupetal.app`)  
**Last Updated:** November 2026  

---

## 0. TIẾN ĐỘ LỘ TRÌNH 5 BƯỚC ƯU TIÊN HIỆN TẠI (SỬA VĂNG APP & ĐƠN GIẢN HÓA GIAO DIỆN)

| Bước | Nội dung công việc | Trạng thái | Kiểm thử & Bằng chứng thực tế |
| :---: | :--- | :--- | :--- |
| **Bước 1** | **Điều tra và sửa lỗi ứng dụng bị văng trên iPhone thật** (Thu thập 31 file `.ips` từ iPhone 15 Pro Max, xác định nguyên nhân gốc `EXC_BREAKPOINT / SIGTRAP` trong `Dictionary.init(dictionaryLiteral:)` khi khởi tạo `LocalizationManager.exactDictionary` từ `HomeViewModel.greeting` + gộp `.onAppear`/`.task` trong `EduPetalAppContainer`; chuyển sang khởi tạo an toàn `Dictionary(exactTranslationPairs, uniquingKeysWith:)` và bổ sung kiểm thử hồi quy chống trùng khóa) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `LocalizationManager.swift`, `EduPetalRootView.swift`, `DesignSystemTests.swift` (**140/140 PASS**, `Seq 2888`) |
| **Bước 2** | **Tinh gọn Trang chủ đúng bốn nhóm thông tin & Phông chữ chuẩn Native iOS (`SF Pro Rounded` / `SF Pro`)** (Thiết kế gọn gàng trong 1 màn hình với **Biểu đồ tròn (Donut Chart)** phối 3 tông màu tách biệt rõ ràng: **Xanh Indigo (`#4F46E5`)** cho `Học phí phát sinh`, **Xanh Ngọc Lục Bảo (`#059669`)** cho `Đã thu` và **Cam Hổ Phách (`#EA580C`)** cho `Còn nợ` kèm nhãn `Kỳ: Tất cả thời gian`; 2 ô ngang gọn phía trên cho **B. Học sinh đang hoạt động** và **C. Lớp học đang hoạt động**; khung gọn phía dưới cho **D. Lịch dạy hôm nay / sắp tới**; sử dụng hệ phông chữ chuẩn iOS `SF Pro Rounded` & `SF Pro`) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `AppTypography.swift`, `HomeView.swift` (**141/141 PASS**, `Seq 3053`) |
| **Bước 3** | **Sửa lỗi Giao diện Tối (Dark Mode) đổi tức thì & Rà soát vị trí hành động và điều hướng giữa 5 tab** (Đồng bộ `window.overrideUserInterfaceStyle` trên toàn bộ `UIWindow` và `UIColor` dynamic provider trực tiếp trong `ThemeManager.swift` & `Color+Hex.swift`; chuẩn hóa nhãn và thứ tự 5 tab `Trang chủ`, `Học sinh`, `Lớp học`, `Lịch dạy`, `Học phí`; loại bỏ các nút/sheet trùng lặp và bổ sung nhãn rõ ràng cho mọi hành động chính trên từng tab) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `ThemeManager.swift`, `Color+Hex.swift`, `MainTabView.swift`, `StudentListView.swift`, `StudentDetailView.swift`, `ScheduleCalendarView.swift` (**141/141 PASS**, `Seq 3055`) |
| **Bước 4** | **Tinh gọn lần lượt từng màn hình, bỏ chú thích thừa** (Lược bỏ các đoạn giải thích dài bên dưới tiêu đề/thẻ/ô nhập, hướng dẫn `"Bước 1, Bước 2..."`, khẩu hiệu trang trí và thuật ngữ kỹ thuật như `JSON (ISO-8601, Pretty)`; bổ sung nhãn cố định rõ ràng phía trên mọi ô nhập liệu trong `StudentEditView.swift` và `ClassEditView.swift`; rút gọn trạng thái trống về đúng 1 câu ngắn kèm nút hành động chính; giữ nguyên các thông tin bắt buộc gồm đơn vị tiền tệ/thời gian, cảnh báo xóa/tài chính, xin quyền ngữ cảnh và Chính sách Quyền riêng tư) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `StudentListView.swift`, `StudentEditView.swift`, `ClassListView.swift`, `ClassEditView.swift`, `ClassDetailView.swift`, `SessionDetailView.swift`, `RecordPaymentSheet.swift`, `FinanceDashboardView.swift`, `SettingsView.swift` (**141/141 PASS**, `Seq 3057`) |
| **Bước 5** | **Kiểm thử hồi quy và hiệu năng toàn diện** (Bổ sung kiểm thử hiệu năng khối lượng lớn 500 học sinh, 50 lớp, 1.000 buổi dạy, 2.000 khoản thu và 1.500 phiếu thu với độ trễ $< 250\text{ ms}$; kiểm thử hồi quy chuẩn hóa 5 tab điều hướng song ngữ Việt–Anh, cô lập dữ liệu `ownerId`, bất biến tài chính Single-Source, chống trùng khóa từ điển và cài đặt lên iPhone thật) | 🟢 **Đã hoàn thành — Chờ người dùng nghiệm thu cuối cùng** | `DashboardTests.swift`, `DesignSystemTests.swift` (**143/143 PASS**) |

---

## 1. TIẾN ĐỘ LỘ TRÌNH CHỈNH SỬA 7 BƯỚC TRƯỚC ĐÓ (HOÀN THÀNH 100%)

| Bước | Nội dung công việc | Trạng thái | Kiểm thử & Bằng chứng thực tế |
| :---: | :--- | :--- | :--- |
| **Bước 1** | **Điều tra và sửa lỗi ứng dụng không gửi thông báo** (Nhắc trước buổi dạy 60 phút & Nhắc xem/thêm lịch lúc 22:00 hằng ngày, xin quyền đúng ngữ cảnh, hiển thị banner khi app đang mở, chạm thông báo mở đúng màn hình Lịch/Chi tiết buổi, cô lập theo tài khoản, hỗ trợ đặt giờ gần hiện tại để test và khôi phục 22:00) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `LocalNotificationService.swift`, `SettingsView.swift`, `EduPetalApp.swift`, `MainTabView.swift` |
| **Bước 2** | **Gỡ Đề thi khỏi điều hướng và thay bằng tab Lớp học** (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Lớp học`, `Học phí`), hiển thị buổi dạy tiếp theo và bảo toàn dữ liệu lịch sử tài chính | 🟢 **Đã hoàn thành & người dùng xác nhận** | `MainTabView.swift`, `EduPetalRootView.swift`, `ClassListView.swift`, `ClassListViewModel.swift` |
| **Bước 3** | **Hoàn thiện Tạo lớp và Thêm học sinh** (Bắt buộc tên lớp + đơn giá $> 0$, hiển thị sẵn phần bổ sung tùy chọn kèm **16 màu nhận diện lớp**, chống bấm lưu trùng, thêm học sinh có sẵn hoặc tạo học sinh mới ngay trong Chi tiết lớp, không phát sinh học phí khi mới ghi danh) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `ClassEditView.swift`, `ClassDetailView.swift`, `ClassDetailViewModel.swift`, `StudentEditView.swift` |
| **Bước 4** | **Hoàn thiện Lịch theo tháng và Chi tiết lớp 4 phân khu** (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Học phí`, thiết lập lịch theo tháng, mở buổi dạy để điểm danh/hoàn thành, xem khoản phải thu & lịch sử thu tiền, ghi nhận thanh toán ngay trong lớp) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `ClassDetailView.swift`, `ClassDetailViewModel.swift`, `StudentClassTests.swift` |
| **Bước 5** | **Hoàn thiện Trải nghiệm người dùng lần đầu** (`1. Tạo lớp` $\rightarrow$ `2. Thêm học sinh` $\rightarrow$ `3. Lên lịch buổi đầu`, tự động dẫn bước tiếp theo, cho phép bỏ qua theo từng tài khoản, không dùng onboarding nhiều trang bắt buộc, không tự chèn dữ liệu demo, màn hình trống rõ ràng có 1 nút chính) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `HomeViewModel.swift`, `HomeView.swift`, `ClassDetailView.swift`, `FinanceDashboardView.swift`, `DashboardTests.swift` |
| **Bước 6** | **Dọn phần code Đề thi còn dư khi đã có phương án migration an toàn & cập nhật tài liệu** (Xóa toàn bộ UI, ViewModel, UseCase, Repository, Mapper, PDF Renderer đề thi và các test Đề thi; giữ lại 5 `@Model` thụ động trong `EduPetalSchemaV1` để mở database cũ an toàn không reset DB; bảo toàn Biên nhận PDF học phí, Điểm số, Ảnh minh chứng và Backup JSON) | 🟢 **Đã hoàn thành & người dùng xác nhận** | `SchemaV1.swift`, `BackupExportService.swift`, `ReceiptPDFRenderer.swift`, `IntegrationWorkflowTests.swift` |
| **Bước 7** | **Kiểm thử hồi quy toàn bộ và tinh chỉnh giao diện** (Giảm thông tin/nút bấm lặp trên các màn hình Tổng quan, Học sinh, Chi tiết học sinh; đồng bộ từ điển song ngữ Việt–Anh; mỗi màn hình có 1 hành động chính rõ ràng; chạy toàn bộ 139 bài test trên 8 test suites và cài đặt lên iPhone) | 🟢 **Đã hoàn thành & người dùng xác nhận** | **139/139 PASS** (`swift test` + `xcodebuild` Debug iPhone `Seq 2840`) |

---

## 2. CÁC HẠNG MỤC NỀN TẢNG ĐÃ HOÀN THÀNH TRƯỚC ĐÓ

| Hạng mục | Trạng thái | Tóm tắt kỹ thuật |
| :--- | :--- | :--- |
| **Chống Deadlock `0x8BADF00D` & Tối ưu luồng chính** | 🟢 **Đã hoàn thành** | Triệt tiêu AB-BA Deadlock giữa `UserSessionManager.lock` / `LocalizationManager.lock` và `ObservationCenter`, cô lập `@MainActor` cho các hàm đổi phiên và cache `SessionWorkspaceDependencies`. |
| **Đăng nhập Apple & Google thật + Cô lập dữ liệu (`ownerId`)** | 🟢 **Đã hoàn thành** | `AppleSignInService` (`ASAuthorizationAppleIDProvider` native, lưu bền vững họ tên/email lần đầu) và `GoogleOAuthService` (PKCE & Firebase Auth `accounts:signInWithIdp`, kiểm tra chặt `state` chống CSRF, sửa triệt để lỗi `missing initial state`), cô lập `ownerId` trên toàn bộ SwiftData và file storage. |
| **Tài chính Học phí Single-Source & Biên nhận PDF A4** | 🟢 **Đã hoàn thành** | Công thức bất biến $\text{Accrued} - \text{Collected} = \text{Outstanding}$ (`Int64` VND), snapshot đơn giá theo buổi, chống tạo trùng (`idempotencyKey`), mã QR chuyển khoản VietQR, kết xuất Bản kê nháp & Biên nhận học phí PDF khổ A4 (`ReceiptPDFRenderer`). |
| **Tối ưu hiệu năng tra cứu $O(1)$ & Vùng bấm Safe Area** | 🟢 **Đã hoàn thành** | Chỉ mục $O(1)$ trong `FinanceViewModel`, hiển thị lớp trực tiếp trên thẻ học sinh trong `StudentListView`, bọc `AvatarEditorView` trong `NavigationStack` chuẩn Safe Area. |

---

## 3. THỐNG KÊ BỘ KIỂM THỬ TỰ ĐỘNG HIỆN TẠI (143 TESTS — 8 TEST SUITES)

| STT | Bộ kiểm thử (Test Suite) | File kiểm thử | Số lượng Test | Trạng thái |
| :---: | :--- | :--- | :---: | :---: |
| 1 | **Schedule & Notifications** | `Tests/EduPetalTests/ScheduleTests/ScheduleTests.swift` | **45** | 🟢 **45 PASS** |
| 2 | **Student & Class Management** | `Tests/EduPetalTests/StudentClassTests/StudentClassTests.swift` | **29** | 🟢 **29 PASS** |
| 3 | **Finance & PDF Receipts** | `Tests/EduPetalTests/FinanceTests/FinanceTests.swift` | **22** | 🟢 **22 PASS** |
| 4 | **Assignments & Grades** | `Tests/EduPetalTests/AssignmentGradeTests/AssignmentGradeTests.swift` | **11** | 🟢 **11 PASS** |
| 5 | **End-to-End Integration Workflows** | `Tests/EduPetalTests/IntegrationTests/IntegrationWorkflowTests.swift` | **11** | 🟢 **11 PASS** |
| 6 | **Design System & Formatters** | `Tests/EduPetalTests/DesignSystemTests/DesignSystemTests.swift` | **11** | 🟢 **11 PASS** |
| 7 | **Dashboard & First-Time UX** | `Tests/EduPetalTests/DashboardTests/DashboardTests.swift` | **9** | 🟢 **9 PASS** |
| 8 | **Color Hex & Semantic Tokens** | `Tests/EduPetalTests/DesignSystemTests/ColorHexTests.swift` | **5** | 🟢 **5 PASS** |
| **TỔNG** | **8 Test Suites** | `Tests/EduPetalTests/` | **143** | 🟢 **143 / 143 PASS (100%)** |
