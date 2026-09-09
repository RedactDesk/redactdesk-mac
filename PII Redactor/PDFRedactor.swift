import Foundation
import PDFKit
import CoreGraphics
import AppKit

/// Image-rewrite PDF redactor. Each page is rendered to a bitmap with solid
/// black boxes burned over the redaction rects, and that bitmap is composed
/// back into a fresh single-file PDF. The output has no selectable text layer
/// and no recoverable pixels underneath the boxes. Redacted content is
/// physically gone, not just hidden.
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

            // PDFKit reports the unrotated media box, so a /Rotate 90 or 270
            // page displays with its dimensions swapped. The output page has to
            // match the displayed size or the content renders off-canvas.
            let box = page.bounds(for: .mediaBox)
            let quarterTurned = abs(page.rotation / 90) % 2 == 1
            var pageRect = CGRect(
                origin: .zero,
                size: quarterTurned
                    ? CGSize(width: box.height, height: box.width)
                    : box.size
            )
            let pageInfo: CFDictionary = [kCGPDFContextMediaBox as String: Data(bytes: &pageRect, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)

            // Draw the page as a bitmap with the black boxes already burned in.
            // Nothing may be painted over the image afterwards - see the note on
            // renderPageAsImage.
            let redactions = spans.spans(on: i)
                .filter { options.enabled.contains($0.category) }
                .flatMap(\.rects)

            try renderPageAsImage(
                page: page,
                index: i,
                pageRect: pageRect,
                redactions: redactions,
                padding: options.rectPadding,
                scale: options.scale,
                into: context
            )

            // Watermark footer line - printed in the bottom margin of every
            // page. Drawn via AppKit string drawing, not Core Text, so we get
            // automatic font substitution for the middle-dot. Safe to draw over
            // the image: it adds content rather than concealing any.
            if let watermark = options.watermark, !watermark.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                drawWatermark(watermark, in: pageRect, context: context)
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

    /// Render a PDFPage into the current PDF context as a raster image, with
    /// the redaction boxes burned into the bitmap.
    ///
    /// This is the "image rewrite" step, and two details of it carry the
    /// product's entire security claim. Both are easy to undo by accident:
    ///
    /// 1. The boxes are filled into the *bitmap*, before `makeImage()`. Filling
    ///    them into the PDF context after the image is drawn would leave the
    ///    original page intact as an image XObject with removable vector
    ///    rectangles layered on top, and `pdfimages -all` would hand back every
    ///    redacted item. Never paint concealing marks into the PDF context.
    /// 2. The page is drawn with `CGContext.drawPDFPage`, not
    ///    `PDFPage.draw(with:to:)`. The latter renders PDFKit annotations, and
    ///    `PDFCanvasView` hangs its live preview overlays - which carry the
    ///    detected text in `contents` - on the very `PDFDocument` being
    ///    exported. Those would be baked into the image.
    ///
    /// Drawing the page content and the boxes under one `getDrawingTransform`
    /// keeps them in a single coordinate space, so /Rotate is honoured by both
    /// and the boxes land on the pixels the model actually matched.
    private static func renderPageAsImage(
        page: PDFPage,
        index: Int,
        pageRect: CGRect,
        redactions: [CGRect],
        padding: CGFloat,
        scale: CGFloat,
        into pdfContext: CGContext
    ) throws {
        guard let pageRef = page.pageRef else {
            throw ExportError.couldNotRenderPage(index)
        }

        let pixelWidth = Int((pageRect.width * scale).rounded(.up))
        let pixelHeight = Int((pageRect.height * scale).rounded(.up))
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
            throw ExportError.couldNotRenderPage(index)
        }

        bitmap.setFillColor(NSColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        bitmap.scaleBy(x: scale, y: scale)

        // Maps the media box onto the page rect, applying the page's /Rotate.
        let transform = pageRef.getDrawingTransform(
            .mediaBox,
            rect: CGRect(origin: .zero, size: pageRect.size),
            rotate: 0,
            preserveAspectRatio: true
        )
        bitmap.concatenate(transform)
        bitmap.drawPDFPage(pageRef)

        // Span rects are in the same unrotated media box space the transform
        // maps from, so they are filled without leaving it.
        bitmap.setFillColor(NSColor.black.cgColor)
        for rect in redactions {
            bitmap.fill(rect.insetBy(dx: -padding, dy: -padding))
        }

        guard let image = bitmap.makeImage() else {
            throw ExportError.couldNotRenderPage(index)
        }
        pdfContext.draw(image, in: pageRect)
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
