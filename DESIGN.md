---
name: EduPetal
description: Where Teaching Blossoms — Hệ thống quản lý giảng dạy tinh tế dành cho giáo viên trên iOS
colors:
  primary: "#E88FA8"
  primary-light: "#F8DCE5"
  accent-rose: "#B84D73"
  neutral-bg: "#FFF8FA"
  surface: "#FFFFFF"
  surface-subtle: "#FDF2F5"
  divider: "#F0E1E6"
  text-primary: "#392D33"
  text-secondary: "#7A6A71"
  text-tertiary: "#A8989F"
  success: "#27B48B"
  warning: "#E69F00"
  error: "#D9534F"
  info: "#4A90E2"
typography:
  large-title:
    fontFamily: "SF Pro Rounded"
    fontSize: "34pt"
    fontWeight: "bold"
  title:
    fontFamily: "SF Pro Rounded"
    fontSize: "28pt"
    fontWeight: "bold"
  title2:
    fontFamily: "SF Pro Rounded"
    fontSize: "22pt"
    fontWeight: "bold"
  title3:
    fontFamily: "SF Pro Rounded"
    fontSize: "20pt"
    fontWeight: "semibold"
  headline:
    fontFamily: "SF Pro Text"
    fontSize: "17pt"
    fontWeight: "semibold"
  body:
    fontFamily: "SF Pro Text"
    fontSize: "17pt"
    fontWeight: "regular"
  callout:
    fontFamily: "SF Pro Text"
    fontSize: "16pt"
    fontWeight: "regular"
  subheadline:
    fontFamily: "SF Pro Text"
    fontSize: "15pt"
    fontWeight: "regular"
  footnote:
    fontFamily: "SF Pro Text"
    fontSize: "13pt"
    fontWeight: "regular"
  caption1:
    fontFamily: "SF Pro Text"
    fontSize: "12pt"
    fontWeight: "medium"
  caption2:
    fontFamily: "SF Pro Text"
    fontSize: "11pt"
    fontWeight: "medium"
rounded:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  full: "999px"
spacing:
  xxs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  xxl: "32px"
  xxxl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "14px 20px"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "16px"
  badge:
    rounded: "{rounded.full}"
    padding: "4px 10px"
---

# EduPetal Design System

## Overview

EduPetal tuân thủ phong cách **"Soft Pink Education"** — một ngôn ngữ thiết kế tinh tế, dịu mắt, truyền cảm hứng giáo dục nhưng giữ vững tính thực dụng và kỷ luật cao của một ứng dụng công cụ chuyên nghiệp (Chế độ **Operate**). 

Hệ thống được tối ưu hóa cho màn hình iPhone cảm ứng, ưu tiên tối đa việc sử dụng bằng **một tay**, tốc độ phản hồi tức thì và sự gọn gàng, không để các chi tiết trang trí làm xao nhãng giáo viên trong lúc giảng dạy.

## Colors

Hệ màu Semantic được cấu hình thích ứng tự động (Adaptive Dynamic Colors) giữa Light Mode và Dark Mode trong `AppColors.swift`:

| Semantic Token | Light Mode Hex | Dark Mode Hex | Vai trò & Mục đích sử dụng |
| :--- | :--- | :--- | :--- |
| `primaryPink` | `#E88FA8` | `#E88FA8` | Màu thương hiệu cốt lõi, nút CTA chính, icon tab đang chọn |
| `secondaryPink`| `#F8DCE5` | `#3D2630` | Nền thẻ phụ, badge mềm, thanh tiến trình |
| `accentRose` | `#B84D73` | `#D67094` | Nút hành động phụ, viền highlight, icon tiêu điểm |
| `background` | `#FFF8FA` | `#1C1619` | Màu nền toàn ứng dụng (ấm áp, không chói mắt) |
| `surfaceCard` | `#FFFFFF` | `#282024` | Bề mặt thẻ thông tin, ô nhập liệu nổi, sheet modal |
| `surfaceSubtle`| `#FDF2F5` | `#221B1F` | Bề mặt phụ, nền của nhóm nhập liệu lồng |
| `divider` | `#F0E1E6` | `#362C31` | Đường phân cách danh sách mềm mại |
| `primaryText` | `#392D33` | `#F5EEF0` | Văn bản chính, tiêu đề (đảm bảo độ tương phản cao) |
| `secondaryText`| `#7A6A71` | `#B0A2A8` | Nhãn phụ, phụ đề, thời gian, metadata |
| `tertiaryText` | `#A8989F` | `#75676D` | Chữ gợi ý, placeholder, văn bản thứ yếu |
| `success` | `#27B48B` | `#27B48B` | Trạng thái có mặt (`Present`), đã thu học phí, điểm cao |
| `warning` | `#E69F00` | `#E69F00` | Trạng thái chờ, học phí còn nợ, buổi học cần hoàn thành |
| `error` | `#D9534F` | `#D9534F` | Trạng thái vắng mặt (`Absent`), buổi bị hủy, nợ quá hạn |
| `info` | `#4A90E2` | `#4A90E2` | Trạng thái đã lên lịch, thông tin hướng dẫn |

### Bảng 16 Màu Nhận diện Lớp học (`ClassEditView`)
Khi tạo hoặc chỉnh sửa lớp học, giáo viên có thể chọn trực tiếp 1 trong **16 màu sắc phân biệt** hiển thị trên lưới 2×8:
`#E88FA8`, `#C94A6A`, `#E0565B`, `#E67E45`, `#D99B26`, `#7CB342`, `#27B48B`, `#17A2B8`, `#3B82F6`, `#4F46E5`, `#7C5CBF`, `#9B51E0`, `#D65DB1`, `#8D6E63`, `#5C768D`, `#4A5568`.

## Typography

Hệ thống phông chữ sử dụng bộ phông chuẩn Native iOS của Apple (**Apple Human Interface Guidelines**): **SF Pro Rounded** cho các tiêu đề và con số nhằm tạo sự hiện đại, sắc nét, và **SF Pro Text** cho các văn bản nội dung nhằm tối ưu độ đọc tiếng Việt.

- **Dynamic Type:** Luôn gắn kết với các text style hệ thống để tôn trọng cỡ chữ người dùng cài đặt trong iOS Settings.
- **Hiển thị Số tiền & Chỉ số:** Sử dụng định dạng `monospacedDigit()` cho số tiền VND và điểm số để các con số luôn thẳng hàng khi cuộn xem danh sách.
- **Sàn kích thước chữ:** Tối thiểu 11pt (`caption2`), cỡ chữ văn bản cơ bản là 17pt (`body`).

## Layout

- **Mô hình điều hướng:** 
  - `TabView` 5 mục ở đáy màn hình: **Tổng quan (0)**, **Học sinh (1)**, **Lịch dạy (2)**, **Lớp học (3)**, **Học phí (4)** (đã thay thế hoàn toàn tab Đề thi cũ bằng tab **Lớp học**).
  - `NavigationStack` lồng bên trong từng tab để duy trì lịch sử màn hình và cử chỉ vuốt mép trái để quay lại (Edge-swipe back).
  - `Sheet` phương thức modal cho các tác vụ tạo mới, chỉnh sửa ngắn gọn hoặc xác nhận thao tác.
- **Nguyên tắc tinh gọn & Trải nghiệm người dùng mới:**
  - Mỗi màn hình chỉ có **một hành động chính (Primary CTA)** rõ ràng; giảm thẻ lồng thẻ và loại bỏ các nút/thông tin lặp lại.
  - Luồng khởi đầu ngắn 3 bước ngay trên màn hình Tổng quan (`1. Tạo lớp` $\rightarrow$ `2. Thêm học sinh` $\rightarrow$ `3. Lên lịch buổi đầu`), tự chuyển sang bước kế tiếp và có thể bỏ qua bất kỳ lúc nào, không dùng onboarding nhiều trang bắt buộc.
- **Vùng an toàn (Safe Area):** Tất cả nội dung tương tác nằm trong Safe Area, không bị che bởi Dynamic Island, tai thỏ hay Home Indicator.
- **Thumb Zone (Thao tác một tay):** Các nút bấm hành động chính (Primary Actions) ưu tiên đặt ở nửa dưới màn hình hoặc thanh công cụ thanh thoát dễ với tới bằng ngón tay cái.
- **Khoảng cách tiêu chuẩn (Spacing Scale):**
  - Viền lề màn hình (Screen Margin): `16pt` (`AppSpacing.md`).
  - Khoảng cách giữa các thẻ danh sách: `12pt` (`AppSpacing.sm`).
  - Khoảng cách giữa các phần tử trong thẻ: `8pt` (`AppSpacing.xs`).

## Elevation & Depth

- **Triết lý:** Tránh lạm dụng đổ bóng đậm hoặc viền nổi cứng nhắc. Sử dụng đổ bóng mềm mại (Soft Shadows) kết hợp phân tầng màu sắc bề mặt.
- **Token Đổ bóng:**
  - `AppShadows.subtle`: Dành cho các thẻ phẳng nhẹ (`radius: 6, y: 2, opacity: 0.03`).
  - `AppShadows.card`: Dành cho thẻ nội dung chính (`radius: 10, y: 3, opacity: 0.05`).
  - `AppShadows.floating`: Dành cho nút nổi hoặc sheet xuất hiện (`radius: 14, y: 6, opacity: 0.25 primaryPink`).

## Shapes

- Bo góc theo thang `AppRadius`:
  - `AppRadius.sm` (8pt): Tag, Badge trạng thái.
  - `AppRadius.md` (12pt): Nút bấm tiêu chuẩn (`PrimaryButton`, `SecondaryButton`), ô nhập liệu (`CurrencyTextField`).
  - `AppRadius.lg` (16pt): Thẻ nội dung chính (`AppCard`).
  - `AppRadius.xl` (24pt): Sheet modal, popover nổi.
  - `AppRadius.full` (999pt): Dạng viên thuốc (Capsule / Pill Badge).

## Components

1. **PrimaryButton:** Nút bấm màu hồng chủ đạo (`primaryPink`), chữ trắng in đậm, chiều cao tối thiểu 50pt, có hiệu ứng nén nhẹ khi chạm, hỗ trợ spinner khi đang xử lý.
2. **SecondaryButton:** Nút viền pastel mềm (`accentRose`), nền trong suốt hoặc mờ nhẹ.
3. **AppCard:** Thẻ bao bọc nội dung có nền dynamic, bo góc 16pt, viền phân cách mỏng 1px (`divider`) và bóng nhẹ.
4. **StatusBadge:** Huy hiệu con nhộng hiển thị trạng thái điểm danh (Có mặt / Vắng mặt), bài tập và thanh toán.
5. **CurrencyTextField:** Ô nhập tiền tệ tích hợp bộ phân cách hàng nghìn VND tự động, căn phải, phông chữ số cố định chiều rộng.
6. **EmptyStateView:** Trực quan hóa khi chưa có dữ liệu bằng SF Symbols chủ đề, tiêu đề, mô tả ngắn và nút hành động nhanh.

## Do's and Don'ts

### Do's:
- **Ưu tiên Native:** Tận dụng tối đa thành phần SwiftUI gốc (`List`, `Picker`, `DatePicker`, `swipeActions`, `confirmationDialog`) và tùy biến nhẹ theo EduPetal.
- **Vùng chạm chuẩn:** Luôn duy trì vùng chạm tối thiểu 44×44 pt cho mọi icon và nút bấm.
- **Haptics:** Kích hoạt phản hồi rung nhẹ (`UIImpactFeedbackGenerator(.light)`) khi thực hiện các hành động hoàn tất như điểm danh, lưu buổi học, ghi nhận học phí.
- **Reduce Motion:** Tôn trọng cài đặt giảm chuyển động của hệ điều hành, ưu tiên hiệu ứng mờ dần (`opacity`) thay vì dịch chuyển lớn.

### Don'ts:
- **Không nhái giao diện Web:** Tuyệt đối không tự làm nút Back tùy biến, không tắt cử chỉ vuốt mép quay lại, không sử dụng thanh cuộn giả lập.
- **Không phối màu chói gắt:** Không sử dụng các màu hồng dạ quang hoặc tím đậm gây nhức mắt khi giáo viên nhìn màn hình trong thời gian dài.
- **Không đặt nút xóa nguy hiểm ngay cạnh nút bấm chính:** Mọi hành động hủy/xóa phải nằm sau cử chỉ vuốt hoặc menu ba chấm kèm hộp thoại xác nhận hủy hoại (destructive confirmation).
- **Không để màn hình rơi vào trạng thái chết (Frozen UI):** Luôn có trạng thái loading, vô hiệu hóa nút bấm chống lưu đúp (anti-double-tap) khi đang thực hiện tác vụ lưu dữ liệu.

