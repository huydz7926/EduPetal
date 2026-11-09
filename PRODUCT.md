# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

- **Người dùng chính:** Giáo viên tự do, gia sư cá nhân hoặc nhóm nhỏ (5–30 học sinh/lớp).
- **Tình huống sử dụng:** Thao tác trên iPhone trong lúc đứng lớp hoặc giữa các buổi dạy; thường xuyên dùng một tay khi đang di chuyển, quản lý lớp học, kiểm tra học sinh, điểm danh nhanh, hoặc xuất biên nhận học phí PDF gửi phụ huynh.

## Product Purpose

EduPetal là trợ lý quản lý giảng dạy độc lập (All-in-one Teaching OS) trên iPhone, loại bỏ sự phân mảnh giữa sổ ghi chép lớp học, học sinh, điểm danh, lịch dạy và đối soát học phí. Ứng dụng mang lại trải nghiệm tinh tế, nhanh gọn và an toàn bảo mật tuyệt đối trên thiết bị (Offline-First / On-Device).

## Positioning

Trợ lý quản lý dạy học độc lập chạy 100% On-Device với SwiftData, giao diện Soft Pink Education tinh tế, quản lý lớp học trực quan và tính toán học phí theo mô hình Single-Source bất biến (không nhầm lẫn giữa học phí và công nợ) dành riêng cho giáo viên Việt Nam.

## Operating Context

- **Môi trường hoạt động:** 100% Offline-First trên iPhone (iOS 17.0+), không bắt buộc kết nối mạng để sử dụng các tính năng quản lý cốt lõi.
- **Tần suất & Nhịp điệu:** Thao tác điểm danh và hoàn thành buổi dạy trong 10–30 giây mỗi buổi; nhận thông báo nhắc trước buổi dạy 60 phút và nhắc xem lịch lúc 22:00 hằng ngày; đối soát học phí theo từng buổi học thực tế và xuất biên nhận PDF A4.
- **Dữ liệu tiền tệ:** Đồng Việt Nam (VND), lưu trữ kiểu `Int64` nguyên vẹn (tuyệt đối không dùng `Double`/`Float` để tránh sai số thập phân).

## Capabilities and Constraints

- **5 Tab điều hướng cốt lõi:**
  1. *Tổng quan (Home):* Hướng dẫn khởi đầu 3 bước cho người mới (`1. Tạo lớp` → `2. Thêm học sinh` → `3. Lên lịch buổi đầu`), KPI 3 chỉ số, lịch dạy trong ngày, việc cần chú ý, thao tác nhanh.
  2. *Học sinh (Students):* Danh sách học sinh kèm thông tin lớp đang tham gia, tìm kiếm/lọc, hồ sơ chi tiết, lưu trữ (`Archive`), khôi phục và xác nhận xóa an toàn.
  3. *Lịch dạy (Schedule):* Lịch biểu theo ngày/tuần/tháng, tạo buổi dạy hoặc lịch lặp theo tháng, kiểm tra trùng giờ, điểm danh, chụp ảnh minh chứng và hoàn thành buổi dạy.
  4. *Lớp học (Classes):* Danh sách lớp học (tên lớp, môn học, số học sinh, buổi dạy tiếp theo, đơn giá mặc định, 16 màu nhận diện), chi tiết lớp 4 phân khu (`Tổng quan`, `Học sinh`, `Lịch dạy`, `Học phí`), thiết lập lịch tháng, lưu trữ/khôi phục lớp an toàn không làm mất lịch sử tài chính.
  5. *Học phí (Finance):* Quản lý công nợ Single-Source, ghi nhận thanh toán theo buổi học, mã QR chuyển khoản VietQR và xuất Biên nhận học phí PDF A4.
- **Ràng buộc kiến trúc:** Clean Architecture + MVVM, Swift Concurrency (`@MainActor`, `Sendable`), SwiftUI Declarative UI, SwiftData.
- **Phạm vi loại trừ (Out of Scope):** Đã loại bỏ hoàn toàn tính năng Đề thi / Ngân hàng câu hỏi khỏi sản phẩm; không có portal dành cho học sinh/phụ huynh, không gọi video/livestream, không tích hợp cổng thanh toán trực tuyến.

## Brand Commitments

- **Tên sản phẩm:** EduPetal
- **Khẩu hiệu (Tagline):** Where Teaching Blossoms
- **Bộ nhận diện thị giác:** "Soft Pink Education" — Tông màu hồng phấn nhẹ nhàng (`#E88FA8`), tạo cảm giác ấm áp, thân thiện, truyền cảm hứng giáo dục nhưng không sến súa; các thẻ bề mặt sáng sạch, bo góc mềm mại.
- **Biểu tượng ứng dụng:** Cánh hoa tri thức vươn nở (App Icon 1024x1024).

## Evidence on Hand

- Toàn bộ đặc tả kỹ thuật và nghiệp vụ tại `SPEC.md`, `ARCHITECTURE.md`, `PLAN.md`, `DESIGN.md`.
- Bộ token thiết kế hiện có tại `Sources/EduPetal/Core/DesignSystem/`.
- Bộ **139 unit và integration tests** trên 8 test suites kiểm chứng toàn bộ quy tắc bất biến (100% pass).
- Host project `EduPetal.xcodeproj` (`com.edupetal.app`) biên dịch và chạy thực tế trên iPhone (iOS 17.0+).

## Product Principles

1. **Thao tác một tay, nhịp độ dưới 10 giây:** Mọi tác vụ lặp lại thường xuyên (điểm danh, ghi nhận học phí, xem lịch) phải hoàn tất chỉ với vài chạm ở nửa dưới màn hình.
2. **Minh bạch tài chính tuyệt đối:** Một dòng tiền duy nhất, học sinh nghỉ không tính tiền, snapshot đơn giá vĩnh viễn theo buổi, chống ghi nhận trùng lặp.
3. **Bảo toàn dữ liệu giáo viên:** Ưu tiên lưu trữ (`Archive`) thay vì xóa cứng; mọi thao tác xóa vĩnh viễn đều yêu cầu xác nhận 2 bước và kiểm tra ràng buộc tài chính.
4. **Chuẩn mực iOS Native & HIG:** Tôn trọng văn hóa giao diện Apple: Dynamic Type, SF Symbols, cử chỉ vuốt tự nhiên, phản hồi xúc giác nhẹ (Haptics), chế độ Reduce Motion.

## Accessibility & Inclusion

- Hỗ trợ Dynamic Type trên toàn bộ nhãn chữ và form nhập liệu.
- Vùng chạm tối thiểu 44×44 pt cho mọi nút bấm và điều khiển.
- Độ tương phản chữ đạt chuẩn WCAG AA trên cả Light Mode và Dark Mode.
- Hỗ trợ VoiceOver với nhãn trợ năng mô tả rõ trạng thái (đã điểm danh, vắng mặt, đã nộp bài).

