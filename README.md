# EduPetal 🌸
### *Where Teaching Blossoms* — All-in-One iOS App for Independent Teachers & Private Tutors

[![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat&logo=swift)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple.svg?style=flat)](https://developer.apple.com/xcode/swiftui/)
[![SwiftData](https://img.shields.io/badge/Database-SwiftData_Schema_V1-success.svg?style=flat)](https://developer.apple.com/documentation/swiftdata)
[![Swift Testing](https://img.shields.io/badge/Tests-139_Passed_100%25-brightgreen.svg?style=flat)](https://developer.apple.com/documentation/testing)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**EduPetal** là ứng dụng iOS chuyên biệt dành riêng cho **giáo viên tự do và gia sư độc lập**. Ứng dụng số hóa trọn vẹn quy trình quản lý lớp học, hồ sơ học sinh, lịch dạy theo tháng, điểm danh, nhắc lịch tự động và đối soát dòng tiền học phí theo nguyên lý kế toán đơn nguồn (**Single-Source Finance**) kèm xuất **Biên nhận học phí PDF chuẩn A4**.

Toàn bộ dữ liệu giảng dạy được lưu trữ **100% On-Device** thông qua **SwiftData Schema V1** và cô lập tuyệt đối theo từng tài khoản người dùng (`ownerId`).

---

## 🌟 5 Phân hệ Cốt lõi (5 Main Navigation Tabs)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                 EDUPETAL                                    │
│   🌸 Tab 1: Tổng quan (Home Dashboard & 3-Step Quick Start Guide)           │
│   👥 Tab 2: Học sinh (Students & 4-Section Detailed Profiles)               │
│   📅 Tab 3: Lịch dạy (Schedule, Overlap Prevention & 1-Tap Attendance)      │
│   🎓 Tab 4: Lớp học (Classes, Monthly Schedule & Class Tuition Overview)    │
│   💰 Tab 5: Học phí (Single-Source Finance, VietQR & A4 PDF Receipts)       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1. Tổng quan & Khởi đầu Nhanh (Tab 1 — Tổng quan)
- **Hướng dẫn khởi đầu 3 bước cho người mới (`FirstTimeSetupStep`):**
  1. `Tạo lớp` $\rightarrow$ 2. `Thêm học sinh` $\rightarrow$ 3. `Lên lịch buổi đầu`.
  - Tự động dẫn người dùng đến hành động tiếp theo ngay sau mỗi bước, cho phép bỏ qua (`Làm sau`) hoặc mở lại bất kỳ lúc nào theo từng tài khoản, không tự động chèn dữ liệu demo vào tài khoản thật.
- **3 Thẻ KPI cân đối:** Học sinh đang học, Lớp học đang mở, Ca dạy hoàn thành hôm nay.
- **Thẻ Tài chính Học phí & Việc cần chú ý:** Theo dõi tức thì tổng Đã thu, Còn nợ, buổi học quá giờ cần điểm danh và học sinh còn nợ học phí (chạm để mở thẳng màn hình xử lý).
- **Lịch dạy hôm nay (`Today's Schedule`):** Hiển thị các ca dạy trong ngày hoặc trạng thái trống có 1 nút hành động chính rõ ràng.

### 2. Quản lý Học sinh (Tab 2 — Học sinh)
- Danh sách học sinh gọn gàng, hiển thị trực tiếp **số lớp đang tham gia** và thông tin từng lớp (màu lớp, tên lớp, môn học, đơn giá áp dụng/buổi) ngay trên thẻ học sinh.
- Tìm kiếm tức thì theo tên/SĐT/email, lọc theo trạng thái `Đang học` / `Đã lưu trữ`.
- **Hồ sơ học sinh 4 phân khu:** `Tổng quan`, `Điểm số`, `Học phí`, `Lớp học`.
- Thiết lập đơn giá riêng cho từng học sinh hoặc tự động kế thừa đơn giá mặc định của lớp.
- Lưu trữ (`Archive`), khôi phục và kiểm tra công nợ/lịch sử trước khi xóa vĩnh viễn.

### 3. Lịch dạy, Điểm danh & Nhắc lịch (Tab 3 — Lịch dạy)
- Lịch dạy trực quan theo ngày/tuần/tháng; hỗ trợ tạo buổi lẻ hoặc chuỗi buổi học lặp theo thứ trong tuần.
- **Chống trùng lịch (`CheckScheduleOverlapUseCase`):** Cảnh báo ngay khi khung giờ mới giao thoa với buổi dạy hiện có.
- **Điểm danh & Hoàn thành buổi dạy (`CompleteTeachingSessionUseCase`):**
  - Khi mới tạo lịch hoặc ghi danh học sinh, điểm danh ở trạng thái `pending` và **chưa phát sinh học phí**.
  - Chỉ khi giáo viên xác nhận điểm danh 100% học sinh và hoàn thành buổi dạy, hệ thống mới sinh khoản phải thu (`ChargeEntity`) cho học sinh **Có mặt (`present`)** theo đơn giá snapshot; học sinh **Nghỉ (`absent` / `excused`)** không tính tiền (`0 ₫`).
  - Hỗ trợ chụp/đính kèm ảnh minh chứng buổi dạy lưu trữ an toàn trên thiết bị.
- **Thông báo nhắc lịch tự động (`LocalNotificationService`):**
  - **(A) Nhắc trước buổi dạy 60 phút** và **(B) Nhắc xem/thêm lịch dạy lúc 22:00 hằng ngày**.
  - Có công tắc bật/tắt riêng cho từng loại, cho phép chỉnh giờ nhắc hằng ngày (tự động thay thế thông báo cũ, không tạo trùng), hỗ trợ nút đặt giờ gần hiện tại để kiểm thử nhanh trên iPhone rồi khôi phục về 22:00.
  - Chạm vào thông báo mở đúng màn hình **Lịch dạy** hoặc **Chi tiết buổi học**.

### 4. Quản lý Lớp học (Tab 4 — Lớp học)
- **Danh sách lớp học:** Hiển thị tên lớp, môn học, số học sinh đang tham gia, buổi dạy tiếp theo, đơn giá mặc định mỗi buổi và thanh tìm kiếm gọn gàng.
- **Tạo & Chỉnh sửa lớp (`ClassEditView`):**
  - Bắt buộc tên lớp và đơn giá hợp lệ ($> 0$), có dải mức giá gợi ý nhanh.
  - Hiển thị sẵn phần **Bổ sung tùy chọn** gồm môn học, thời lượng buổi dạy và **bảng 16 màu nhận diện lớp** trực quan.
  - Chống bấm lưu trùng (`isSaving` guard) và tự động mở màn hình Chi tiết lớp vừa tạo để thêm học sinh ngay.
- **Chi tiết lớp 4 phân khu (`ClassDetailView`):**
  1. `Tổng quan`: Tóm tắt sĩ số, buổi dạy tiếp theo, thẻ gợi ý bước tiếp theo cho lớp mới, thông tin học phí lớp.
  2. `Học sinh`: Thêm học sinh có sẵn hoặc tạo học sinh mới ghi danh thẳng vào lớp (không phát sinh tiền khi mới thêm).
  3. `Lịch dạy`: Thiết lập lịch học theo tháng (chọn thứ trong tuần, khung giờ, khoảng ngày, xem trước danh sách buổi và kiểm tra trùng lịch) hoặc tạo buổi lẻ; chạm vào buổi dạy để điểm danh/hoàn thành.
  4. `Học phí`: Xem tổng Đã phát sinh, Đã thu, Còn nợ của riêng lớp, công nợ từng học sinh và lịch sử thu tiền; ghi nhận thanh toán ngay trong lớp.
- **Lưu trữ & Bảo vệ dữ liệu lịch sử:** Lưu trữ (`Archive`) và khôi phục lớp giữ nguyên toàn bộ lịch sử học sinh, buổi dạy và tài chính; xóa lớp vĩnh viễn có xác nhận và **không bao giờ cascade xóa** các buổi đã hoàn thành hoặc dữ liệu tài chính.

### 5. Quản lý Học phí Single-Source & Biên nhận PDF A4 (Tab 5 — Học phí)
- **Một nguồn sự thật tài chính duy nhất (`Single-Source Finance`):** Học phí và tiền công dạy là cùng một dòng tiền, không cộng hai lần:
  $$\text{Accrued Tuition (Phát sinh)} - \text{Collected Tuition (Đã thu)} = \text{Outstanding Balance (Còn nợ)}$$
- Toàn bộ tiền tệ lưu kiểu `Int64` (VND), dùng đơn giá `unitPriceSnapshot` tại thời điểm hoàn thành buổi học (việc đổi giá lớp/học sinh sau này không làm thay đổi các khoản đã phát sinh hay đã thu).
- Chống tạo trùng khoản thu (`idempotencyKey` theo `sessionId + studentId`) và phân bổ thanh toán tự động theo FIFO hoặc theo các buổi được chọn.
- Hỗ trợ cấu hình ngân hàng tạo mã **VietQR** tự động và kết xuất **Bản kê nháp / Biên nhận học phí PDF khổ A4** ([`ReceiptPDFRenderer.swift`](file:///Users/minhhuy/EduPetal/Sources/EduPetal/Data/PDF/ReceiptPDFRenderer.swift)) để chia sẻ hoặc in qua AirPrint.

---

## 🔐 Đăng nhập Thật & Cô lập Dữ liệu Đa Người Dùng (`ownerId`)

- Hỗ trợ đăng nhập **Sign in with Apple** native (`ASAuthorizationAppleIDProvider`), **Google Sign-In** (OAuth 2.0 PKCE / Firebase Auth `accounts:signInWithIdp` với kiểm tra chặt `state` chống CSRF và khóa chống gọi đăng nhập đồng thời), **Email & Mật khẩu** hoặc **Chế độ Khách (`guest_local`)**.
- Mọi bản ghi SwiftData và đường dẫn tệp (ảnh minh chứng, avatar) đều gắn `ownerId` riêng biệt (`apple_*`, `google_*`, `email_*`, `guest_local`).
- Khi chuyển tài khoản hoặc đăng xuất:
  - Xóa sạch RAM cache, hủy toàn bộ thông báo chờ của tài khoản cũ để không lộ thông tin lớp/học sinh sang tài khoản mới.
  - Kiểm tra `SessionContext` trước khi lưu kết quả của mọi tác vụ bất đồng bộ.

---

## 🎨 Ngôn ngữ Thiết kế — "Soft Pink Education"

- **Bảng màu Semantic hỗ trợ đầy đủ Light Mode & Dark Mode** ([`AppColors.swift`](file:///Users/minhhuy/EduPetal/Sources/EduPetal/Core/DesignSystem/Tokens/AppColors.swift)):
  - `primaryPink`: `#D9668A` (Light) / `#E88FA8` (Dark)
  - `accentRose`: `#A63D63` (Light) / `#E58BAA` (Dark)
  - `background`: `#FFF6F9` (Light) / `#171215` (Dark)
  - `surfaceCard`: `#FFFFFF` (Light) / `#251D21` (Dark)
- **Nguyên tắc bố cục tinh gọn:**
  - Mỗi màn hình có một hành động chính rõ ràng, giảm thẻ lồng thẻ và bỏ các nút/thông tin lặp.
  - Vùng chạm tối thiểu $44 \times 44\text{ pt}$ thuận tiện thao tác một tay, hỗ trợ Dynamic Type và chuyển đổi song ngữ **Tiếng Việt / Tiếng Anh** tức thì.

---

## 🏗️ Kiến trúc Phần mềm (Clean Architecture + MVVM)

```
┌──────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                        │
│        SwiftUI Views  •  @Observable ViewModels  •  DTOs     │
└──────────────────────────────┬───────────────────────────────┘
                               │ calls
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                       DOMAIN LAYER                           │
│        Use Cases (Pure Swift)  •  Entities  •  Protocols     │
│        (100% Decoupled from SwiftUI & SwiftData)             │
└──────────────────────────────▲───────────────────────────────┘
                               │ implements
┌──────────────────────────────┴───────────────────────────────┐
│                        DATA LAYER                            │
│     SwiftData Models (@Model)  •  Mappers  •  Repositories   │
│     Receipt A4 PDF Renderer  •  JSON Backup & Notification   │
└──────────────────────────────────────────────────────────────┘
```

- **Tương thích ngược Cơ sở dữ liệu (`EduPetalSchemaV1`):**
  - 13 `@Model` đang hoạt động trực tiếp cho Học sinh, Lớp học, Ghi danh, Buổi dạy, Điểm danh, Ảnh đính kèm, Bài tập, Điểm số và Học phí.
  - 5 `@Model` legacy của phân hệ Đề thi cũ được giữ thụ động trong `EduPetalSchemaV1` để đảm bảo các cơ sở dữ liệu đã lưu trên iPhone của người dùng luôn mở an toàn, **không bao giờ cần reset database**.

---

## 🧪 Kiểm thử Tự động (139 Tests — 100% Pass)

Dự án sử dụng **Swift Testing** (`@Suite`, `@Test`, `#expect`) với **139 bài kiểm thử tự động** trên **8 bộ kiểm thử (Test Suites)**:

```text
✔ Test run with 139 tests in 8 suites passed.
```

| STT | Bộ kiểm thử (Test Suite) | Số lượng Test | Trọng tâm kiểm chứng |
| :---: | :--- | :---: | :--- |
| 1 | `ScheduleTests` | **45** | Trùng lịch, chuỗi lịch lặp, điểm danh, hoàn thành buổi dạy, lập lịch & hủy thông báo nhắc 60 phút / 22:00 hằng ngày, cô lập thông báo khi đổi user |
| 2 | `StudentClassTests` | **29** | CRUD Học sinh & Lớp học, ghi danh không phát sinh phí, thiết lập lịch theo tháng, tổng hợp học phí theo lớp, lưu trữ & bảo vệ lịch sử tài chính khi xóa lớp |
| 3 | `FinanceTests` | **22** | Phương trình Single-Source Finance, snapshot đơn giá, chống tạo trùng khoản thu (Idempotent), phân bổ FIFO/chọn buổi, VietQR, kết xuất Biên nhận PDF A4 |
| 4 | `AssignmentGradeTests` | **11** | Giao bài tập, theo dõi nộp bài, kiểm tra hợp lệ điểm số ($0 \le \text{score} \le \text{maxScore}$), tính điểm trung bình trọng số |
| 5 | `IntegrationWorkflowTests` | **11** | 6 E2E Workflows: Vòng đời Lớp học $\rightarrow$ Lịch tháng $\rightarrow$ Điểm danh $\rightarrow$ Học phí, Sao lưu JSON, OAuth Google/Apple, cô lập đa tài khoản và chống Deadlock `0x8BADF00D` |
| 6 | `DesignSystemTests` | **9** | Định dạng tiền tệ VND `Int64`, Design Tokens (`AppColors`, `AppSpacing`, `AppRadius`), trạng thái Component |
| 7 | `DashboardTests` | **7** | Chỉ số KPI màn hình Tổng quan, lọc dữ liệu active, luồng hướng dẫn 3 bước cho người dùng lần đầu (`FirstTimeSetupStep`) |
| 8 | `ColorHexTests` | **5** | Khởi tạo màu từ mã Hex 3/6/8 ký tự và fallback an toàn |
| **Tổng** | **8 Test Suites** | **139 Tests** | **100% PASS** |

---

## 🚀 Hướng dẫn Cài đặt & Chạy ứng dụng

### Yêu cầu Môi trường
- **macOS:** macOS Sonoma 14.0+ / Sequoia 15.0+
- **Xcode:** Xcode 16.0+ / 26.3+
- **Deployment Target:** iOS 17.0+ (iPhone)
- **Bundle Identifier:** `com.edupetal.app` (Development Team: `5Z73BW7X4C`)

### Chạy Kiểm thử Tự động (Terminal)
```bash
cd /Users/minhhuy/EduPetal
swift test
```

### Build & Cài đặt lên iPhone hoặc Simulator
```bash
xcodebuild -project EduPetal.xcodeproj -scheme EduPetal -configuration Debug build
```

---

## 📄 Bản quyền & Tác giả
- Phát triển bởi **Minh Huy**.
- Phát hành theo giấy phép [MIT License](LICENSE).
- *"Where Teaching Blossoms"* 🌸
