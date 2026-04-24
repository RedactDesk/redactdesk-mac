import Foundation
import PDFKit
import CoreGraphics
import AppKit

/// Image-rewrite PDF redactor. Each page is rendered to a bitmap, redaction
/// rects are painted as solid black boxes, and the result is composed back
/// into a fresh single-file PDF. The output has no selectable text layer.
/// Redacted content is physically gone, not just hidden.
enum PDFRedactor {
    enum ExportError: LocalizedError {
        case couldNotCreateContext
        case couldNotRenderPage(Int)
        case couldNotWrite(URL)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateContext: "Failed to start a PDF writer."
            case .couldNotRenderPage(let i): "Failed to render page \(i + 1)."
            case .couldNotWrite(let url): "Failed to write \(url.lastPathComponent)."
            }
        }
    }

    struct Options {
        /// Enabled categories. Spans outside this set are ignored when writing.
        var enabled: Set<Design.Category>
        /// Render scale. 2.0 is "retina-quality" bitmap fallback; higher values
        /// mean bigger output files.
        var scale: CGFloat = 2.0
        /// Extra padding around each black box, in PDF points.
        var rectPadding: CGFloat = 1.5
        /// Footer attribution text. `nil` disables the watermark. Respected
        /// per-export rather than read from preferences directly so the
        /// redactor remains a pure function over its inputs.
        var watermark: String? = nil
    }

    /// Writes a redacted copy of `source` to `outputURL`.
    /// - Parameter progress: called with 0.0…1.0 on an arbitrary queue.
    static func export(
        source: PDFDocument,
        spans: DocumentSpans,
        options: Options,
        to outputURL: URL,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) throws {
        let pageCount = source.pageCount
        guard pageCount > 0 else { throw ExportError.couldNotRenderPage(0) }

        // Kick off the PDF writer with the first page's MediaBox as a hint;
        // each page's box is re-declared when we begin that page.
        var mediaBox = source.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.couldNotCreateContext
        }

        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)

        for i in 0..<pageCount {
            guard let page = source.page(at: i) else {
                context.closePDF()
                throw ExportError.couldNotRenderPage(i)
            }
            var box = page.bounds(for: .mediaBox)
            let pageInfo: CFDictionary = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)

            // 1. Draw the original page into the PDF page as a bitmap.
            try renderPageAsImage(page: page, box: box, scale: options.scale, into: context)

            // 2. Paint black redaction rectangles on top, in page coordinates.
            let pageSpans = spans.spans(on: i).filter { options.enabled.contains($0.category) }
            if !pageSpans.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                context.setFillColor(NSColor.black.cgColor)
                for span in pageSpans {
                    for rect in span.rects {
                        let padded = rect.insetBy(dx: -options.rectPadding, dy: -options.rectPadding)
                        context.fill(padded)
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            }

            // 3. Watermark footer line - printed in the bottom margin of every
            //    page. Drawn via AppKit string drawing, not Core Text, so we
            //    get automatic font substitution for the middle-dot.
            if let watermark = options.watermark, !watermark.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                drawWatermark(watermark, in: box, context: context)
                NSGraphicsContext.restoreGraphicsState()
            }

            context.endPDFPage()
            progress(Double(i + 1) / Double(pageCount))
        }

        context.closePDF()
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            throw ExportError.couldNotWrite(outputURL)
        }
    }

    /// Render a PDFPage into the current PDF context as a raster image.
    /// This is the "image rewrite" step - any text layer in the source PDF is
    /// intentionally not preserved so redacted content cannot be recovered via
    /// copy/paste, accessibility APIs, or PDF text extraction tools.
    private static func renderPageAsImage(
        page: PDFPage,
        box: CGRect,
        scale: CGFloat,
        into pdfContext: CGContext
    ) throws {
        let pixelWidth = Int((box.width * scale).rounded(.up))
        let pixelHeight = Int((box.height * scale).rounded(.up))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let bitmap = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ExportError.couldNotRenderPage(page.pageRef?.pageNumber ?? 0)
        }

        bitmap.setFillColor(NSColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        bitmap.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: bitmap)

        guard let image = bitmap.makeImage() else {
            throw ExportError.couldNotRenderPage(page.pageRef?.pageNumber ?? 0)
        }
        pdfContext.draw(image, in: box)
    }

    /// Draws the attribution footer centred horizontally near the bottom of
    /// the page. The text is intentionally small (7pt) and low-contrast (45%
    /// gray) so it reads as a colophon rather than a banner.
    private static func drawWatermark(
        _ text: String,
        in box: CGRect,
        context: CGContext
    ) {
        let font = NSFont.systemFont(ofSize: 7, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.withAlphaComponent(0.45),
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()

        // Bottom margin: 12pt above the edge, but never overlapping the
        // existing page content. A 24pt vertical band is plenty for a 7pt line.
        let y: CGFloat = 10
        let x: CGFloat = box.minX + (box.width - textSize.width) / 2
        let drawRect = CGRect(
            x: x,
            y: box.minY + y,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: drawRect)
    }
}
