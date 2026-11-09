import Foundation
import CoreGraphics
import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Dữ liệu tổng hợp để kết xuất Hóa đơn / Biên nhận học phí PDF A4 chuyên nghiệp
public struct ReceiptPDFData: Sendable {
    public let receiptCode: String
    public let teacherName: String
    public let studentName: String
    public let amount: Int64
    public let paidAt: Date
    public let paymentMethod: String
    public let note: String
    public let remainingBalance: Int64
    public let items: [(title: String, date: Date, amount: Int64)]

    public init(
        receiptCode: String,
        teacherName: String = "Giáo viên EduPetal",
        studentName: String,
        amount: Int64,
        paidAt: Date,
        paymentMethod: String,
        note: String,
        remainingBalance: Int64,
        items: [(title: String, date: Date, amount: Int64)]
    ) {
        self.receiptCode = receiptCode
        self.teacherName = teacherName
        self.studentName = studentName
        self.amount = amount
        self.paidAt = paidAt
        self.paymentMethod = paymentMethod
        self.note = note
        self.remainingBalance = remainingBalance
        self.items = items
    }
}

/// Trình kết xuất file PDF Hóa đơn / Phiếu thu học phí khổ A4 chuyên nghiệp (ReceiptPDFRenderer)
public final class ReceiptPDFRenderer: @unchecked Sendable {
    public static let pageWidth: CGFloat = 595.2
    public static let pageHeight: CGFloat = 841.8
    public static let margin: CGFloat = 42.0

    public init() {}

    public func renderReceiptPDF(data: ReceiptPDFData) throws -> Data {
        let mutableData = NSMutableData()
        var pageRect = CGRect(x: 0, y: 0, width: Self.pageWidth, height: Self.pageHeight)

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw PDFRenderError.cannotCreateContext
        }

        context.beginPDFPage(nil)
        var currentY = Self.pageHeight - Self.margin
        let printableWidth = Self.pageWidth - (Self.margin * 2)

        // 1. Header Thương hiệu & Khung Tiêu đề Hóa đơn chuyên nghiệp
        currentY = drawProfessionalHeader(in: context, data: data, startY: currentY, width: printableWidth)

        // 2. Khung Thông tin Học sinh & Thông tin Thanh toán
        currentY = drawPartyInfoBox(in: context, data: data, startY: currentY, width: printableWidth)

        // 3. Bảng kê chi tiết các buổi học thanh toán
        currentY = drawItemsTable(in: context, data: data, startY: currentY, width: printableWidth)

        // 4. Khung Tổng kết Thanh toán & Công nợ còn lại
        currentY = drawSummaryBox(in: context, data: data, startY: currentY, width: printableWidth)

        // 5. Chữ ký xác nhận & Chân trang chuyên nghiệp
        drawSignaturesAndFooter(in: context, data: data, startY: currentY, width: printableWidth)

        context.endPDFPage()
        context.closePDF()

        return mutableData as Data
    }

    // MARK: - Drawing Sections

    private func drawProfessionalHeader(
        in context: CGContext,
        data: ReceiptPDFData,
        startY: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let bannerHeight: CGFloat = 78
        let bannerRect = CGRect(x: Self.margin, y: startY - bannerHeight, width: width, height: bannerHeight)

        // Nền header màu hồng đậm thương hiệu EduPetal
        context.setFillColor(CGColor(srgbRed: 0.72, green: 0.23, blue: 0.38, alpha: 1.0))
        let bannerPath = CGPath(roundedRect: bannerRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(bannerPath)
        context.fillPath()

        let brandAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1.0, green: 0.88, blue: 0.92, alpha: 1.0)
        ]
        let titleAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 19, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ]
        let codeAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 10.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ]
        let subAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.98, green: 0.90, blue: 0.93, alpha: 1.0)
        ]

        _ = drawTextLine(in: context, text: "HỆ THỐNG QUẢN LÝ ĐÀO TẠO EDUPETAL", attributes: brandAttr, x: Self.margin + 18, y: startY - 22)
        _ = drawTextLine(in: context, text: "PHIẾU THU & BẢNG KÊ HỌC PHÍ", attributes: titleAttr, x: Self.margin + 18, y: startY - 46)
        _ = drawTextLine(in: context, text: "Chứng từ xác nhận thanh toán học phí chính thức", attributes: subAttr, x: Self.margin + 18, y: startY - 64)

        // Góc phải: Số chứng từ & Ngày lập
        _ = drawTextLine(in: context, text: "Số HĐ: \(data.receiptCode)", attributes: codeAttr, x: Self.margin + width - 175, y: startY - 28)
        _ = drawTextLine(in: context, text: "Ngày lập: \(data.paidAt.formatted(date: .numeric, time: .shortened))", attributes: subAttr, x: Self.margin + width - 175, y: startY - 46)
        _ = drawTextLine(in: context, text: "Trạng thái: ĐÃ XÁC NHẬN", attributes: subAttr, x: Self.margin + width - 175, y: startY - 64)

        return startY - bannerHeight - 16
    }

    private func drawPartyInfoBox(
        in context: CGContext,
        data: ReceiptPDFData,
        startY: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let boxHeight: CGFloat = 86
        let boxRect = CGRect(x: Self.margin, y: startY - boxHeight, width: width, height: boxHeight)

        context.setFillColor(CGColor(srgbRed: 0.99, green: 0.98, blue: 0.985, alpha: 1.0))
        let path = CGPath(roundedRect: boxRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()

        context.setStrokeColor(CGColor(srgbRed: 0.88, green: 0.82, blue: 0.85, alpha: 1.0))
        context.setLineWidth(0.9)
        context.addPath(path)
        context.strokePath()

        let colWidth = width / 2
        let dividerX = Self.margin + colWidth

        context.move(to: CGPoint(x: dividerX, y: startY - boxHeight + 10))
        context.addLine(to: CGPoint(x: dividerX, y: startY - 10))
        context.strokePath()

        let sectionHeaderAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.72, green: 0.23, blue: 0.38, alpha: 1.0)
        ]
        let labelAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.38, green: 0.36, blue: 0.37, alpha: 1.0)
        ]
        let valAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 11.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.14, green: 0.12, blue: 0.13, alpha: 1.0)
        ]

        // Cột Trái: Thông tin Học sinh / Phụ huynh
        _ = drawTextLine(in: context, text: "THÔNG TIN HỌC SINH", attributes: sectionHeaderAttr, x: Self.margin + 14, y: startY - 20)
        _ = drawTextLine(in: context, text: data.studentName, attributes: valAttr, x: Self.margin + 14, y: startY - 38)
        _ = drawTextLine(in: context, text: "Phương thức thanh toán: \(data.paymentMethod)", attributes: labelAttr, x: Self.margin + 14, y: startY - 56)
        let noteText = data.note.isEmpty ? "Thu học phí theo bảng kê buổi học" : data.note
        _ = drawTextLine(in: context, text: "Nội dung: \(noteText)", attributes: labelAttr, x: Self.margin + 14, y: startY - 72)

        // Cột Phải: Đơn vị / Giáo viên phụ trách
        _ = drawTextLine(in: context, text: "ĐƠN VỊ / GIÁO VIÊN THU HỌC PHÍ", attributes: sectionHeaderAttr, x: dividerX + 14, y: startY - 20)
        _ = drawTextLine(in: context, text: data.teacherName, attributes: valAttr, x: dividerX + 14, y: startY - 38)
        _ = drawTextLine(in: context, text: "Hệ thống quản lý lớp học EduPetal", attributes: labelAttr, x: dividerX + 14, y: startY - 56)
        _ = drawTextLine(in: context, text: "Số buổi thanh toán: \(max(1, data.items.count)) mục", attributes: labelAttr, x: dividerX + 14, y: startY - 72)

        return startY - boxHeight - 16
    }

    private func drawItemsTable(
        in context: CGContext,
        data: ReceiptPDFData,
        startY: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        var y = startY

        let tableHeaderAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.22, green: 0.18, blue: 0.20, alpha: 1.0)
        ]

        // Table Header
        let headerHeight: CGFloat = 26
        let headerRect = CGRect(x: Self.margin, y: y - headerHeight, width: width, height: headerHeight)
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.91, blue: 0.93, alpha: 1.0))
        context.fill(headerRect)

        context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.78, blue: 0.81, alpha: 1.0))
        context.setLineWidth(0.8)
        context.stroke(headerRect)

        _ = drawTextLine(in: context, text: "STT", attributes: tableHeaderAttr, x: Self.margin + 10, y: y - 17)
        _ = drawTextLine(in: context, text: "CHI TIẾT BUỔI HỌC / NỘI DUNG THU", attributes: tableHeaderAttr, x: Self.margin + 48, y: y - 17)
        _ = drawTextLine(in: context, text: "NGÀY HỌC", attributes: tableHeaderAttr, x: Self.margin + width - 190, y: y - 17)
        _ = drawTextLine(in: context, text: "THÀNH TIỀN", attributes: tableHeaderAttr, x: Self.margin + width - 105, y: y - 17)

        y -= headerHeight

        let cellAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1.0)
        ]
        let amountAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.12, green: 0.52, blue: 0.30, alpha: 1.0)
        ]

        let rows: [(title: String, date: Date, amount: Int64)] = data.items.isEmpty
            ? [(title: "Thanh toán học phí cho học sinh \(data.studentName)", date: data.paidAt, amount: data.amount)]
            : data.items

        let rowHeight: CGFloat = 24
        for (idx, item) in rows.prefix(16).enumerated() {
            let rowRect = CGRect(x: Self.margin, y: y - rowHeight, width: width, height: rowHeight)
            if idx % 2 == 1 {
                context.setFillColor(CGColor(srgbRed: 0.99, green: 0.975, blue: 0.98, alpha: 1.0))
                context.fill(rowRect)
            }
            context.setStrokeColor(CGColor(srgbRed: 0.91, green: 0.88, blue: 0.89, alpha: 1.0))
            context.setLineWidth(0.6)
            context.stroke(rowRect)

            _ = drawTextLine(in: context, text: "\(idx + 1)", attributes: cellAttr, x: Self.margin + 14, y: y - 16)
            let truncatedTitle = item.title.count > 52 ? String(item.title.prefix(52)) + "..." : item.title
            _ = drawTextLine(in: context, text: truncatedTitle, attributes: cellAttr, x: Self.margin + 48, y: y - 16)
            _ = drawTextLine(in: context, text: item.date.formatted(date: .numeric, time: .omitted), attributes: cellAttr, x: Self.margin + width - 190, y: y - 16)
            _ = drawTextLine(in: context, text: item.amount.formattedVND, attributes: amountAttr, x: Self.margin + width - 105, y: y - 16)

            y -= rowHeight
        }

        return y - 16
    }

    private func drawSummaryBox(
        in context: CGContext,
        data: ReceiptPDFData,
        startY: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let y = startY
        let boxWidth: CGFloat = 265
        let boxHeight: CGFloat = 68
        let boxRect = CGRect(x: Self.margin + width - boxWidth, y: y - boxHeight, width: boxWidth, height: boxHeight)

        context.setFillColor(CGColor(srgbRed: 0.985, green: 0.955, blue: 0.965, alpha: 1.0))
        let path = CGPath(roundedRect: boxRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()

        context.setStrokeColor(CGColor(srgbRed: 0.82, green: 0.68, blue: 0.73, alpha: 1.0))
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        let labelAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.32, green: 0.28, blue: 0.30, alpha: 1.0)
        ]
        let totalValAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 13.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.12, green: 0.55, blue: 0.30, alpha: 1.0)
        ]
        let balValAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 10.5, nil),
            kCTForegroundColorAttributeName: data.remainingBalance > 0
                ? CGColor(srgbRed: 0.82, green: 0.28, blue: 0.22, alpha: 1.0)
                : CGColor(srgbRed: 0.12, green: 0.55, blue: 0.30, alpha: 1.0)
        ]

        let boxX = Self.margin + width - boxWidth + 14
        _ = drawTextLine(in: context, text: "TỔNG SỐ TIỀN ĐÃ THU:", attributes: labelAttr, x: boxX, y: y - 24)
        _ = drawTextLine(in: context, text: data.amount.formattedVND, attributes: totalValAttr, x: boxX + 132, y: y - 24)

        _ = drawTextLine(in: context, text: "Dư nợ còn lại sau thu:", attributes: labelAttr, x: boxX, y: y - 48)
        _ = drawTextLine(in: context, text: data.remainingBalance.formattedVND, attributes: balValAttr, x: boxX + 132, y: y - 48)

        return y - boxHeight - 28
    }

    private func drawSignaturesAndFooter(
        in context: CGContext,
        data: ReceiptPDFData,
        startY: CGFloat,
        width: CGFloat
    ) {
        let sigAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.22, green: 0.20, blue: 0.21, alpha: 1.0)
        ]
        let subSigAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Oblique" as CFString, 8.5, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.48, green: 0.46, blue: 0.47, alpha: 1.0)
        ]

        let colW = width / 2
        _ = drawTextLine(in: context, text: "PHỤ HUYNH / HỌC SINH", attributes: sigAttr, x: Self.margin + 40, y: startY)
        _ = drawTextLine(in: context, text: "(Ký và ghi rõ họ tên)", attributes: subSigAttr, x: Self.margin + 46, y: startY - 14)

        _ = drawTextLine(in: context, text: "GIÁO VIÊN / NGƯỜI LẬP PHIẾU", attributes: sigAttr, x: Self.margin + colW + 30, y: startY)
        _ = drawTextLine(in: context, text: "(Ký và xác nhận đã thu)", attributes: subSigAttr, x: Self.margin + colW + 50, y: startY - 14)

        let thankAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.72, green: 0.23, blue: 0.38, alpha: 1.0)
        ]
        let footnoteAttr: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.50, green: 0.48, blue: 0.49, alpha: 1.0)
        ]

        _ = drawTextLine(
            in: context,
            text: "Trân trọng cảm ơn Quý Phụ huynh và Học sinh đã đồng hành cùng lớp học!",
            attributes: thankAttr,
            x: Self.margin,
            y: Self.margin / 2 + 14
        )
        _ = drawTextLine(
            in: context,
            text: "Phiếu thu học phí điện tử xuất từ ứng dụng EduPetal • Mã đối soát: \(data.receiptCode)",
            attributes: footnoteAttr,
            x: Self.margin,
            y: Self.margin / 2
        )
    }

    private func drawTextLine(
        in context: CGContext,
        text: String,
        attributes: [CFString: Any],
        x: CGFloat,
        y: CGFloat
    ) -> CGFloat {
        let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        return y
    }
}

// MARK: - Trình Chia Sẻ Hệ Thống Tin Cậy (Khắc phục lỗi ShareLink trong Sheet trên iOS)

#if canImport(UIKit)
@MainActor
public enum ShareSheetPresenter {
    /// Hiển thị UIActivityViewController trực tiếp trên ViewController đang nằm trên cùng (kể cả bên trong nhiều tầng .sheet)
    public static func present(items: [Any]) {
        guard !items.isEmpty else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? windowScene.windows.first?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 60, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}
#endif

public enum PDFRenderError: Error, LocalizedError {
    case cannotCreateContext

    public var errorDescription: String? {
        "Không thể khởi tạo CoreGraphics PDF Context để xuất file A4."
    }
}
