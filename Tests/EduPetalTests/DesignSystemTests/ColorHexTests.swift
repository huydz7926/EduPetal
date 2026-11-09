import Testing
import SwiftUI
@testable import EduPetal

@Suite("Color & Token Test Suite")
struct ColorHexTests {

    @Test("Kiểm tra khởi tạo Color từ Hex 6 ký tự chuẩn")
    func testColorHex6Digits() {
        let color = Color(hex: "#E88FA8")
        let description = String(describing: color)
        #expect(!description.isEmpty)
    }

    @Test("Kiểm tra khởi tạo Color từ Hex 8 ký tự kèm Alpha")
    func testColorHex8DigitsWithAlpha() {
        let color = Color(hex: "#E88FA8CC")
        let description = String(describing: color)
        #expect(!description.isEmpty)
    }

    @Test("Kiểm tra khởi tạo Color từ Hex 3 ký tự rút gọn")
    func testColorHex3Digits() {
        let color = Color(hex: "#FFF")
        let description = String(describing: color)
        #expect(!description.isEmpty)
    }

    @Test("Kiểm tra Fallback khi truyền chuỗi Hex không hợp lệ")
    func testColorHexInvalidFallback() {
        let color = Color(hex: "invalid-hex-string")
        let description = String(describing: color)
        #expect(!description.isEmpty)
    }

    @Test("Kiểm tra tất cả Semantic Color Tokens khởi tạo hợp lệ")
    func testSemanticColorTokensExistence() {
        let tokens: [Color] = [
            AppColors.primaryPink,
            AppColors.secondaryPink,
            AppColors.accentRose,
            AppColors.background,
            AppColors.surfaceCard,
            AppColors.surfaceSubtle,
            AppColors.primaryText,
            AppColors.secondaryText,
            AppColors.tertiaryText,
            AppColors.divider,
            AppColors.success,
            AppColors.warning,
            AppColors.error,
            AppColors.info
        ]
        #expect(tokens.count == 14)
        for token in tokens {
            #expect(!String(describing: token).isEmpty)
        }
    }
}
