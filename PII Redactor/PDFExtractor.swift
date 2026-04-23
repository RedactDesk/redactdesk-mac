import Foundation
import PDFKit

/// A page's text plus per-character bounding boxes in page coordinates.
struct ExtractedPage {
    let pageIndex: Int
    /// Visible text concatenation for this page, in document order.
    let text: String
    /// `bounds[i]` is the rect for scalar `i` in `text`. Always same length as
    /// `text.unicodeScalars.count`. Rects are in PDF user-space for the page.
    let bounds: [CGRect]
    /// Native page size in points — handy for rendering.
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
            let text = page.string ?? ""
            let scalarCount = text.unicodeScalars.count
            var bounds: [CGRect] = []
            bounds.reserveCapacity(scalarCount)

            // `characterBounds(at:)` is indexed by UTF-16 code unit, not scalar.
            // Step through scalars and map each to its first UTF-16 offset.
            let utf16 = text.utf16
            var utf16Index = utf16.startIndex
            for scalar in text.unicodeScalars {
                let offset = utf16.distance(from: utf16.startIndex, to: utf16Index)
                let rect = page.characterBounds(at: offset)
                bounds.append(rect)
                // advance utf16Index by the scalar's UTF-16 length
                utf16Index = utf16.index(utf16Index, offsetBy: scalar.utf16.count)
            }

            pages.append(
                ExtractedPage(
                    pageIndex: i,
                    text: text,
                    bounds: bounds,
                    pageRect: page.bounds(for: .mediaBox)
                )
            )
        }
        return (doc, pages)
    }
}
