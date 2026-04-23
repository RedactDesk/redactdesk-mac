import SwiftUI

/// Main workspace shown when a PDF is loaded. Sidebar on the left with
/// category toggles + detected entity list; PDF canvas on the right.
struct DocumentView: View {
    @EnvironmentObject private var controller: DocumentController
    @State private var focusedSpan: PageSpan?

    var body: some View {
        HSplitView {
            EntitySidebar(focusedSpan: $focusedSpan)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            rightPane
                .frame(minWidth: 480)
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }

    @ViewBuilder
    private var rightPane: some View {
        if let doc = controller.document {
            VStack(spacing: 0) {
                DocumentHeader()
                HairlineDivider()
                PDFCanvasView(
                    document: doc.document,
                    spans: controller.spans,
                    enabled: controller.enabledCategories,
                    focusedSpan: focusedSpan
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ExportStatusBar()
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Header

private struct DocumentHeader: View {
    @EnvironmentObject private var controller: DocumentController

    var body: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.document?.filename ?? "")
                    .font(Design.Font.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Design.Space.xs) {
                    if let count = controller.document?.pageCount {
                        Label("\(count) \(count == 1 ? "page" : "pages")", systemImage: "doc.richtext")
                            .labelStyle(.titleAndIcon)
                            .font(Design.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    statusBadge
                }
            }
            Spacer()
            detectStatus
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
    }

    @ViewBuilder
    private var statusBadge: some View {
        let total = controller.spans.totalCount
        if total > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(total) detected")
                    .font(Design.Font.captionStrong)
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var detectStatus: some View {
        switch controller.detectState {
        case .idle:
            EmptyView()
        case .running(let f):
            HStack(spacing: Design.Space.xs) {
                ProgressView(value: f)
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                Text("Scanning \(Int(f * 100))%")
                    .font(Design.Font.monoSmall)
                    .foregroundStyle(.secondary)
            }
        case .done(let elapsed):
            Text(String(format: "Scanned in %.1f s", elapsed))
                .font(Design.Font.monoSmall)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Design.Font.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

// MARK: - Export status bar

private struct ExportStatusBar: View {
    @EnvironmentObject private var controller: DocumentController

    var body: some View {
        Group {
            switch controller.exportState {
            case .idle:
                EmptyView()
            case .exporting(let f):
                HStack(spacing: Design.Space.sm) {
                    ProgressView(value: f)
                        .progressViewStyle(.linear)
                    Text("Exporting redacted PDF… \(Int(f * 100))%")
                        .font(Design.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Design.Space.lg)
                .padding(.vertical, Design.Space.sm)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
            case .done(let url):
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Exported to \(url.lastPathComponent)")
                        .font(Design.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") { controller.revealExport() }
                        .buttonStyle(.borderless)
                        .font(Design.Font.caption)
                }
                .padding(.horizontal, Design.Space.lg)
                .padding(.vertical, Design.Space.sm)
                .background(Color.green.opacity(0.08))
            case .failed(let message):
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(Design.Font.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, Design.Space.lg)
                .padding(.vertical, Design.Space.sm)
                .background(Color.red.opacity(0.08))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.exportState)
    }
}
