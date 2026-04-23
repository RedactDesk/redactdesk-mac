import Foundation
import CoreGraphics

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

/// Merges per-scalar rects from `PDFExtractor` into line-level redaction rects
/// for each span returned by `PrivacyFilter`.
enum SpanMapper {
    /// Turns `RedactionSpan`s scoped to a page's decoded text into `PageSpan`s
    /// carrying one rect per text line the span occupies.
    static func mapSpans(
        _ spans: [RedactionSpan],
        onto page: ExtractedPage
    ) -> [PageSpan] {
        var result: [PageSpan] = []
        result.reserveCapacity(spans.count)
        for span in spans {
            let rects = lineRects(
                startScalar: span.start,
                endScalar: span.end,
                in: page
            )
            guard !rects.isEmpty else { continue }
            result.append(
                PageSpan(
                    pageIndex: page.pageIndex,
                    start: span.start,
                    end: span.end,
                    label: span.label,
                    text: span.text,
                    rects: rects
                )
            )
        }
        return result
    }

    /// Collects per-scalar rects within [start, end) and fuses adjacent rects
    /// that are vertically aligned into one line rectangle.
    private static func lineRects(
        startScalar: Int,
        endScalar: Int,
        in page: ExtractedPage
    ) -> [CGRect] {
        let lo = max(0, min(startScalar, page.bounds.count))
        let hi = max(lo, min(endScalar, page.bounds.count))
        guard lo < hi else { return [] }

        var lines: [CGRect] = []
        var current: CGRect?

        for i in lo..<hi {
            let r = page.bounds[i]
            // PDFKit returns CGRect.zero for characters without glyph geometry
            // (newlines, soft hyphens, control codes). Skip them.
            if r.isEmpty || r.width == 0 || r.height == 0 { continue }
            if var c = current {
                // Same line: roughly same y and overlapping height.
                let verticalOverlap = min(c.maxY, r.maxY) - max(c.minY, r.minY)
                if verticalOverlap >= min(c.height, r.height) * 0.5 {
                    c = c.union(r)
                    current = c
                    continue
                }
                lines.append(c)
                current = r
            } else {
                current = r
            }
        }
        if let c = current { lines.append(c) }
        return lines
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
