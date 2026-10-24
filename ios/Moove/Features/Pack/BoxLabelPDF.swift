import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import MooveKit

/// Draws MooveKit `BoxLabel`s into a PDF: a band in the room's color with the room name, the big box
/// number, a QR code (`moove://box/<n>`), what's inside, and FRAGILE / THIS SIDE UP / OPEN FIRST
/// badges. Black ink on white plus one color band, so it prints fine in grayscale too.
@MainActor
enum BoxLabelPDF {
    static func data(labels: [BoxLabel], layout: BoxLabelLayout) -> Data {
        let page = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: layout.pageSize.height)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Moove box labels", kCGPDFContextCreator as String: "Moove"]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        return renderer.pdfData { ctx in
            var currentPage = -1
            for (index, label) in labels.enumerated() {
                let slot = layout.slot(index)
                if slot.page != currentPage {
                    ctx.beginPage()
                    currentPage = slot.page
                }
                let r = slot.rect
                draw(label, in: CGRect(x: r.x, y: r.y, width: r.width, height: r.height), cutLine: layout == .letterTwoUp)
            }
            if labels.isEmpty { ctx.beginPage() }
        }
    }

    private static let ink = UIColor(white: 0.08, alpha: 1)
    private static let red = UIColor(red: 0.62, green: 0.13, blue: 0.08, alpha: 1)
    private static let green = UIColor(red: 0.18, green: 0.36, blue: 0.16, alpha: 1)

    private static func uiColor(_ c: VoxelColor) -> UIColor {
        let (r, g, b) = PackingPalette.rgb(c)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func font(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    @discardableResult
    private static func text(_ s: String, _ font: UIFont, _ color: UIColor, in rect: CGRect, lines: Int = 1,
                             align: NSTextAlignment = .left) -> CGFloat {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        p.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        let str = NSAttributedString(string: s, attributes: attrs)
        let maxH = font.lineHeight * CGFloat(lines) + 1
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, maxH))
        str.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        let used = str.boundingRect(with: CGSize(width: rect.width, height: maxH), options: [.usesLineFragmentOrigin], context: nil)
        return min(used.height, maxH)
    }

    private static func draw(_ label: BoxLabel, in r: CGRect, cutLine: Bool) {
        let h = r.height, w = r.width
        let pad = w * 0.05
        // Outline (dashed on letter paper, to cut along).
        let outline = UIBezierPath(roundedRect: r, cornerRadius: 10)
        outline.lineWidth = 1.5
        if cutLine { outline.setLineDash([6, 4], count: 2, phase: 0) }
        ink.setStroke()
        outline.stroke()

        // Room band.
        let bandH = h * 0.19
        let band = UIBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY, width: w, height: bandH),
                                byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10))
        uiColor(label.roomColor).setFill()
        band.fill()
        let glyphD = bandH * 0.62
        let roomFont = font(min(bandH * 0.42, w * 0.085), .heavy)
        text(label.room, roomFont, uiColor(PackingPalette.ink),
             in: CGRect(x: r.minX + pad, y: r.minY + (bandH - roomFont.lineHeight) / 2, width: w - pad * 3 - glyphD, height: bandH))
        // Size glyph in a white circle.
        let glyphRect = CGRect(x: r.maxX - pad - glyphD, y: r.minY + (bandH - glyphD) / 2, width: glyphD, height: glyphD)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: glyphRect).fill()
        let glyphFont = font(glyphD * 0.55, .heavy)
        text(label.sizeGlyph, glyphFont, ink,
             in: CGRect(x: glyphRect.minX, y: glyphRect.midY - glyphFont.lineHeight / 2, width: glyphD, height: glyphFont.lineHeight),
             align: .center)

        // Number and QR.
        var y = r.minY + bandH + h * 0.03
        let qrSide = min(h * 0.26, w * 0.34)
        let qrRect = CGRect(x: r.maxX - pad - qrSide, y: y, width: qrSide, height: qrSide)
        if let qr = qrImage(label.qrPayload) {
            let cg = UIGraphicsGetCurrentContext()
            cg?.interpolationQuality = .none
            qr.draw(in: qrRect)
        }
        text(label.qrPayload, font(max(6, qrSide * 0.065), .regular), ink,
             in: CGRect(x: qrRect.minX - 10, y: qrRect.maxY + 2, width: qrSide + 20, height: 12), align: .center)
        text("BOX", font(h * 0.035), ink, in: CGRect(x: r.minX + pad, y: y, width: w * 0.5, height: h * 0.05))
        let numberFont = font(min(qrSide * 0.95, w * 0.3), .heavy)
        text(label.number, numberFont, ink,
             in: CGRect(x: r.minX + pad - numberFont.pointSize * 0.04, y: y + h * 0.035, width: qrRect.minX - r.minX - pad * 2, height: numberFont.lineHeight))
        y = max(qrRect.maxY + 16, y + h * 0.035 + numberFont.lineHeight)

        // Contents.
        let lineFont = font(min(h * 0.032, 15), .regular)
        let badgeH = h * 0.075
        let footerH = h * 0.04
        let contentsBottom = r.maxY - pad - badgeH - footerH - 8
        text("CONTENTS", font(lineFont.pointSize * 0.8), ink, in: CGRect(x: r.minX + pad, y: y, width: w - pad * 2, height: lineFont.lineHeight))
        y += lineFont.lineHeight + 2
        var lines = label.contents
        if label.moreCount > 0 { lines.append("+ \(label.moreCount) more") }
        for line in lines where y + lineFont.lineHeight <= contentsBottom {
            y += text("• " + line, lineFont, ink, in: CGRect(x: r.minX + pad, y: y, width: w - pad * 2, height: contentsBottom - y))
        }

        // Badges.
        var x = r.minX + pad
        let badgeY = r.maxY - pad - footerH - badgeH
        let badgeFont = font(badgeH * 0.42, .heavy)
        for badge in label.badges {
            let title = badge == .thisSideUp ? "↑↑ " + badge.rawValue : badge.rawValue
            let width = (title as NSString).size(withAttributes: [.font: badgeFont]).width + badgeH * 0.5
            guard x + width <= r.maxX - pad else { break }
            let rect = CGRect(x: x, y: badgeY, width: width, height: badgeH)
            let color = badge.isWarning ? red : green
            color.setStroke()
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3)
            path.lineWidth = 3
            path.stroke()
            text(title, badgeFont, color, in: CGRect(x: rect.minX, y: rect.midY - badgeFont.lineHeight / 2, width: width, height: badgeFont.lineHeight),
                 align: .center)
            x += width + 8
        }
        text("\(label.sizeLine) · Moove", font(footerH * 0.6, .regular), ink,
             in: CGRect(x: r.minX + pad, y: r.maxY - pad - footerH + 4, width: w - pad * 2, height: footerH))
    }

    private static let ciContext = CIContext()

    /// A crisp QR code (medium error correction) as a small image; drawn without smoothing.
    private static func qrImage(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The labels as a shareable PDF: the share sheet offers Print (AirPrint), Save to Files and so on.
/// Rendered only when the user actually shares.
struct BoxLabelsFile: Transferable, Sendable {
    var labels: [BoxLabel]
    var layout: BoxLabelLayout

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in
            await BoxLabelPDF.data(labels: file.labels, layout: file.layout)
        }
        .suggestedFileName("Moove box labels.pdf")
    }
}

/// "Print labels": a menu of paper sizes, each a share link to the PDF.
struct PrintLabelsMenu<MenuLabel: View>: View {
    var boxes: [MovingBox]
    var title = "Moove box labels"
    @ViewBuilder var label: MenuLabel

    var body: some View {
        let labels = BoxLabel.labels(for: boxes)
        Menu {
            ForEach(BoxLabelLayout.allCases) { layout in
                ShareLink(
                    item: BoxLabelsFile(labels: labels, layout: layout),
                    preview: SharePreview(title, image: Image(systemName: "printer"))
                ) {
                    Text(layout.title)
                }
            }
        } label: {
            label
        }
        .disabled(boxes.isEmpty)
    }
}
