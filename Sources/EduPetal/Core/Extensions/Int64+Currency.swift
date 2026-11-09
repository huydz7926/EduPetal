import Foundation

public extension Int64 {
    /// Định dạng số tiền VND chuẩn Việt Nam (ví dụ: `150.000 ₫` hoặc `0 ₫`)
    var formattedVND: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.maximumFractionDigits = 0
        formatter.currencySymbol = "₫"
        formatter.positiveFormat = "#,##0 ¤"
        formatter.negativeFormat = "-#,##0 ¤"

        let number = NSNumber(value: self)
        return formatter.string(from: number) ?? "\(self) ₫"
    }

    /// Định dạng số tiền chỉ gồm số và dấu chấm phân cách hàng nghìn (ví dụ: `150.000`)
    var formattedGrouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 0

        let number = NSNumber(value: self)
        return formatter.string(from: number) ?? "\(self)"
    }

    /// Chuyển đổi an toàn từ chuỗi người dùng nhập thành `Int64` VND
    static func parseVND(from rawString: String) -> Int64 {
        // Loại bỏ mọi ký tự không phải chữ số hoặc dấu trừ
        let clean = rawString
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "₫", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Int64(clean) ?? 0
    }
}

public extension Int {
    var formattedVND: String {
        Int64(self).formattedVND
    }

    var formattedGrouped: String {
        Int64(self).formattedGrouped
    }
}

