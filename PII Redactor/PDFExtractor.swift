import Foundation
import PDFKit

/// A page's text plus a reference to its PDFPage for native selection rects.
struct ExtractedPage {
    let pageIndex: Int
    /// Visible text concatenation for this page, in document order. Sourced
    /// from `PDFPage.string`.
    let text: String
    /// The PDFPage is retained so we can ask PDFKit to produce pixel-accurate
    /// selection rectangles via `PDFPage.selection(for: NSRange)`.
    let pdfPage: PDFPage
    /// Native page size in points.
    let pageRect: CGRect
}

enum PDFExtractorError: LocalizedError {
    case couldNotOpen(URL)
    case encrypted
    case empty

    var errorDescription: String? {
        switch self {
        case .couldNotOpen(let url): "Could not open \(url.lastPathComponent)."
        case .encrypted: "This PDF is password-protected. Unlock it and try again."
        case .empty: "This PDF has no pages."
        }
    }
}

enum PDFExtractor {
    /// Opens a PDF and extracts text + per-character bounds for every page.
    /// Safe to call off the main thread; `PDFDocument` is Sendable-ish in
    /// practice as long as we never hand the same instance to two threads.
    static func extract(from url: URL) throws -> (document: PDFDocument, pages: [ExtractedPage]) {
        guard let doc = PDFDocument(url: url) else { throw PDFExtractorError.couldNotOpen(url) }
        guard !doc.isLocked else { throw PDFExtractorError.encrypted }
        let count = doc.pageCount
        guard count > 0 else { throw PDFExtractorError.empty }

        var pages: [ExtractedPage] = []
        pages.reserveCapacity(count)
        for i in 0..<count {
            guard let page = doc.page(at: i) else { continue }
            pages.append(
                ExtractedPage(
                    pageIndex: i,
                    text: page.string ?? "",
                    pdfPage: page,
                    pageRect: page.bounds(for: .mediaBox)
                )
            )
        }
        return (doc, pages)
    }
}
