import AppKit
import PDFKit
import SwiftUI

/// SwiftUI wrapper around `PDFView` that shows the source PDF with translucent
/// preview annotations for every enabled redaction span. Annotations are
/// rebuilt whenever the spans or enabled categories change.
struct PDFCanvasView: NSViewRepresentable {
    let document: PDFDocument
    let spans: DocumentSpans
    let enabled: Set<Design.Category>
    let focusedSpan: PageSpan?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = NSColor.underPageBackgroundColor
        view.interpolationQuality = .high
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        rebuildAnnotations(on: view, coordinator: context.coordinator)
        if let focus = focusedSpan {
            scrollTo(span: focus, in: view)
        }
    }

    // MARK: - Annotation management

    private func rebuildAnnotations(on view: PDFView, coordinator: Coordinator) {
        // Remove previously-added preview annotations.
        for (page, annotations) in coordinator.annotationsByPage {
            for annotation in annotations {
                page.removeAnnotation(annotation)
            }
        }
        coordinator.annotationsByPage.removeAll()

        guard let doc = view.document else { return }

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let spans = self.spans.spans(on: pageIndex).filter { enabled.contains($0.category) }
            guard !spans.isEmpty else { continue }

            var built: [PDFAnnotation] = []
            built.reserveCapacity(spans.reduce(0) { $0 + $1.rects.count })
            for span in spans {
                for rect in span.rects {
                    let padded = rect.insetBy(dx: -1.5, dy: -1.5)
                    let annotation = PDFAnnotation(bounds: padded, forType: .square, withProperties: nil)
                    let uiColor = NSColor(span.category.color)
                    annotation.color = uiColor.withAlphaComponent(0.85)
                    annotation.interiorColor = uiColor.withAlphaComponent(0.22)
                    annotation.border = {
                        let b = PDFBorder()
                        b.lineWidth = 1.2
                        return b
                    }()
                    annotation.contents = span.category.title + ": " + span.text
                    page.addAnnotation(annotation)
                    built.append(annotation)
                }
            }
            coordinator.annotationsByPage[page] = built
        }
    }

    private func scrollTo(span: PageSpan, in view: PDFView) {
        guard let doc = view.document,
              span.pageIndex < doc.pageCount,
              let page = doc.page(at: span.pageIndex),
              let firstRect = span.rects.first
        else { return }
        // Center scroll on the span's first rect.
        let selection = PDFSelection(document: doc)
        selection.add(PDFSelection(document: doc))
        _ = selection
        view.go(to: firstRect, on: page)
    }

    final class Coordinator {
        var annotationsByPage: [PDFPage: [PDFAnnotation]] = [:]
    }
}
