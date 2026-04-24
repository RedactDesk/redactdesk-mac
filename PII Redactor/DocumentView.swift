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
        .background(Design.workspaceSurface)
    }

    @ViewBuilder
    private var rightPane: some View {
        if let doc = controller.document {
            VStack(spacing: 0) {
                DocumentHeader()
                HairlineDivider()
                if doc.looksImageOnly {
                    ImageOnlyPDFBanner()
                }
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

// MARK: - Image-only PDF notice

/// Shown when the loaded PDF has no extractable text layer (i.e. a scan or
/// image export). Detection runs against PDFKit's text layer only - there
/// is no OCR pass - so the sidebar will stay empty and the export will be
/// a no-op mask. Tell the user plainly rather than looking broken.
private struct ImageOnlyPDFBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("No text layer found in this PDF.")
                    .font(Design.Font.captionStrong)
                Text("RedactDesk reads the PDF's text layer directly and does not OCR scanned images. Run the PDF through an OCR tool first, then reopen it here.")
                    .font(Design.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.35))
                .frame(height: 0.5),
            alignment: .bottom
        )
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
                PostExportCard(exportedURL: url)
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

// MARK: - Post-export attribution card
//
// The "workhorse" mechanic from the attribution plan. On a successful
// export we:
//   1. Confirm the redaction ("N items redacted locally"),
//   2. Give a calm, one-line Elephas pitch,
//   3. Offer a contextual handoff (Open in Elephas if installed, else a
//      link to elephas.app with a `?ref=redactdesk-handoff` param).
// Stays present for the session; there's no "dismiss" because the user
// already initiated the action and the copy is unobtrusive.
private struct PostExportCard: View {
    let exportedURL: URL

    @EnvironmentObject private var controller: DocumentController

    private var redactionCount: Int { controller.spans.totalCount }

    private var elephasInstalled: Bool { ElephasDetector.isInstalled }

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Design.Palette.successText)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(redactionCount) \(redactionCount == 1 ? "item" : "items") redacted locally.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Palette.fg)

                Text("Exported to \(exportedURL.lastPathComponent). RedactDesk handles PDFs. Elephas redacts across your whole workspace, with an optional local processing mode.")
                    .font(Design.Font.caption)
                    .foregroundStyle(Design.Palette.fgMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Design.Space.sm)

            HStack(spacing: Design.Space.xs) {
                Button("Show in Finder") { controller.revealExport() }
                    .buttonStyle(.borderless)
                    .font(Design.Font.caption)

                if elephasInstalled {
                    Button("Open in Elephas") {
                        ElephasDetector.openElephas()
                    }
                    .buttonStyle(GhostPillButtonStyle())
                } else {
                    Button("Get Elephas") {
                        NSWorkspace.shared.open(ElephasLinks.landing(.handoff))
                    }
                    .buttonStyle(BrandPillButtonStyle())
                }
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(
            Rectangle()
                .fill(Design.Palette.successTint)
                .overlay(
                    Rectangle()
                        .fill(Design.Palette.border)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }
}
