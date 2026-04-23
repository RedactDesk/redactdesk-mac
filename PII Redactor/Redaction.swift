import Foundation
import CoreGraphics
import PDFKit

/// A single detected PII span mapped onto a PDF page, ready for redaction.
struct PageSpan: Identifiable, Sendable, Hashable {
    let id = UUID()
    let pageIndex: Int
    /// Character offset range in the page's extracted text (unicode scalars).
    let start: Int
    let end: Int
    /// Raw model label (e.g. `private_email`).
    let label: String
    /// Literal text slice — used for list/detail display.
    let text: String
    /// One rectangle per run of characters on the page. Most spans produce a
    /// single rect, but text wrapping or multi-column layout can break a span
    /// across lines — we merge collinear rects and keep each line separate.
    let rects: [CGRect]

    var category: Design.Category { Design.Category(label: label) }

    static func == (lhs: PageSpan, rhs: PageSpan) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Resolves `RedactionSpan`s (model offsets in decoded-text space) into
/// pixel-accurate rectangles on the PDF page.
///
/// Why text search, not token-decoded offsets: `PrivacyFilter` reports offsets
/// in `tokenizer.decode(all tokens)`, which is *almost* identical to the input
/// text but drifts by a handful of characters on leading whitespace, fused
/// punctuation, soft hyphens, etc. Indexing `PDFPage.characterBounds(at:)`
/// with those offsets causes visible drift in the redaction boxes — leaves
/// the first few characters of the PII exposed. We skip that class of bugs
/// entirely by searching for the literal PII text inside `page.text`, then
/// letting PDFKit compute the rects from an NSRange via its native selection
/// machinery (`PDFPage.selection(for:)` + `PDFSelection.selectionsByLine()`).
enum SpanMapper {
    static func mapSpans(
        _ spans: [RedactionSpan],
        onto page: ExtractedPage
    ) -> [PageSpan] {
        var result: [PageSpan] = []
        result.reserveCapacity(spans.count)

        let nsText = page.text as NSString
        // Walk a cursor forward so repeated strings (e.g. the name appearing
        // three times on a page) resolve to the right occurrence in order.
        var searchStart = 0

        for span in spans {
            guard !span.text.isEmpty else { continue }

            let remaining = NSRange(
                location: searchStart,
                length: max(0, nsText.length - searchStart)
            )
            var resolved = nsText.range(of: span.text, options: [.literal], range: remaining)

            // Fallback: if the model's decoded span text has a trailing trim
            // difference (e.g. dropped a soft hyphen), try without the last
            // character. This rescues most of the ~1% of spans where literal
            // match misses.
            if resolved.location == NSNotFound, span.text.count > 2 {
                let trimmed = String(span.text.dropLast())
                resolved = nsText.range(of: trimmed, options: [.literal], range: remaining)
            }
            // Last-ditch fallback: use the raw decoded-space offsets as a
            // best-effort so the span is at least *somewhere* in the PDF.
            if resolved.location == NSNotFound {
                let hintedStart = max(0, min(span.start, nsText.length))
                let hintedEnd = max(hintedStart, min(span.end, nsText.length))
                resolved = NSRange(location: hintedStart, length: hintedEnd - hintedStart)
            }

            searchStart = resolved.location + resolved.length

            let rects = pageRects(for: resolved, on: page.pdfPage)
            guard !rects.isEmpty else { continue }

            result.append(
                PageSpan(
                    pageIndex: page.pageIndex,
                    start: resolved.location,
                    end: resolved.location + resolved.length,
                    label: span.label,
                    text: span.text,
                    rects: rects
                )
            )
        }
        return result
    }

    /// Ask PDFKit for selection rects covering the given NSRange. If the range
    /// spans multiple visual lines, `selectionsByLine()` returns one selection
    /// per line, each with a single bounding rect — exactly what we want for
    /// drawing black boxes that don't cross whitespace between lines.
    private static func pageRects(for range: NSRange, on page: PDFPage) -> [CGRect] {
        guard range.length > 0, let selection = page.selection(for: range) else { return [] }
        let lineSelections = selection.selectionsByLine()
        guard !lineSelections.isEmpty else {
            let r = selection.bounds(for: page)
            return r.isEmpty ? [] : [r]
        }
        return lineSelections.compactMap { line -> CGRect? in
            let r = line.bounds(for: page)
            return r.isEmpty ? nil : r
        }
    }
}

/// A collected list of spans per page for the current document.
struct DocumentSpans {
    /// `byPage[i]` holds spans for page index i. Pages with no spans get [].
    var byPage: [[PageSpan]]

    var all: [PageSpan] { byPage.flatMap { $0 } }
    var totalCount: Int { byPage.reduce(0) { $0 + $1.count } }

    static let empty = DocumentSpans(byPage: [])

    func spans(on pageIndex: Int) -> [PageSpan] {
        guard byPage.indices.contains(pageIndex) else { return [] }
        return byPage[pageIndex]
    }

    /// Counts per `Design.Category`.
    func categoryCounts() -> [(category: Design.Category, count: Int)] {
        var tally: [Design.Category: Int] = [:]
        for span in all { tally[span.category, default: 0] += 1 }
        return Design.Category.displayOrder.compactMap { cat in
            guard let n = tally[cat], n > 0 else { return nil }
            return (cat, n)
        }
    }
}
