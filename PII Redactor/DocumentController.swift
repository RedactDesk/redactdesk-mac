import AppKit
import Combine
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentController: ObservableObject {
    // MARK: - Published state

    enum ModelState: Equatable {
        case idle
        case preparing(fraction: Double, phase: String)
        case ready
        case failed(String)
    }

    enum DetectState: Equatable {
        case idle
        case running(fraction: Double)
        case done(elapsed: TimeInterval)
        case failed(String)
    }

    enum ExportState: Equatable {
        case idle
        case exporting(fraction: Double)
        case done(URL)
        case failed(String)
    }

    struct LoadedDocument: Equatable {
        let url: URL
        let document: PDFDocument
        let pages: [ExtractedPage]

        var filename: String { url.lastPathComponent }
        var pageCount: Int { pages.count }

        /// True when no page has any extractable text. Usually means the PDF
        /// is a scan or image-only export: PDFKit finds no text layer, the
        /// model sees nothing, and detection returns zero spans silently.
        var looksImageOnly: Bool {
            !pages.isEmpty && pages.allSatisfy { $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }
        }

        static func == (lhs: LoadedDocument, rhs: LoadedDocument) -> Bool {
            lhs.url == rhs.url && lhs.document === rhs.document
        }
    }

    @Published var modelState: ModelState = .idle
    @Published var detectState: DetectState = .idle
    @Published var exportState: ExportState = .idle
    @Published var document: LoadedDocument?
    @Published var spans: DocumentSpans = .empty
    @Published var enabledCategories: Set<Design.Category> = Set(Design.Category.displayOrder)

    // MARK: - Private

    private let filter = PrivacyFilter(variant: .q4)
    private var currentLoadTask: Task<Void, Never>?
    private var currentDetectTask: Task<Void, Never>?

    // MARK: - Derived state

    var isLoaded: Bool { modelState == .ready }
    var hasDocument: Bool { document != nil }

    var canExport: Bool {
        guard document != nil else { return false }
        if case .exporting = exportState { return false }
        return spans.totalCount > 0
    }

    // MARK: - Init

    init() {
        prepareModel()
    }

    // MARK: - Actions

    /// Kicks off model download + session build in the background. Idempotent.
    func prepareModel() {
        if case .preparing = modelState { return }
        if case .ready = modelState { return }
        modelState = .preparing(fraction: 0, phase: "Preparing the privacy model…")
        Task { [filter] in
            do {
                try await filter.load { fraction in
                    Task { @MainActor in
                        let phase: String
                        if fraction < 0.85 {
                            phase = "Downloading privacy model…"
                        } else if fraction < 0.98 {
                            phase = "Preparing model for on-device use…"
                        } else {
                            phase = "Optimizing for your Mac…"
                        }
                        self.modelState = .preparing(fraction: fraction, phase: phase)
                    }
                }
                await MainActor.run { self.modelState = .ready }
            } catch {
                await MainActor.run {
                    self.modelState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Presents NSOpenPanel and opens a selected PDF.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    /// Opens a PDF from a URL (e.g. a drag-and-drop).
    func open(url: URL) {
        currentLoadTask?.cancel()
        currentDetectTask?.cancel()
        detectState = .idle
        exportState = .idle
        spans = .empty

        currentLoadTask = Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try PDFExtractor.extract(from: url)
                let loaded = LoadedDocument(url: url, document: result.document, pages: result.pages)
                await MainActor.run {
                    self.document = loaded
                }
                await self.runDetection()
            } catch {
                await MainActor.run {
                    self.detectState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Runs the privacy filter over every page of the loaded document and
    /// populates `spans`. Waits on model readiness if necessary.
    func runDetection() async {
        guard let loaded = document else { return }
        if !isLoaded {
            // Wait up to ~60s for the model to finish loading.
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                if case .ready = modelState { break }
                if case .failed = modelState { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard isLoaded else {
                detectState = .failed("Model did not finish loading in time.")
                return
            }
        }

        detectState = .running(fraction: 0)
        let started = Date()
        let totalPages = loaded.pages.count
        var perPage: [[PageSpan]] = Array(repeating: [], count: totalPages)

        for (idx, page) in loaded.pages.enumerated() {
            guard !Task.isCancelled else { return }
            do {
                let result = try await filter.detect(text: page.text)
                let mapped = SpanMapper.mapSpans(result.spans, onto: page)
                perPage[idx] = mapped

                let snapshot = perPage
                let fraction = Double(idx + 1) / Double(totalPages)
                await MainActor.run {
                    self.spans = DocumentSpans(byPage: snapshot)
                    self.detectState = .running(fraction: fraction)
                }
            } catch {
                await MainActor.run {
                    self.detectState = .failed(error.localizedDescription)
                }
                return
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        await MainActor.run {
            self.detectState = .done(elapsed: elapsed)
        }
    }

    /// Presents a save panel and writes a redacted copy of the current PDF.
    func requestExport() {
        guard let loaded = document, canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = loaded.url
            .deletingPathExtension()
            .lastPathComponent + "-redacted.pdf"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        if panel.runModal() == .OK, let destination = panel.url {
            export(to: destination, loaded: loaded)
        }
    }

    private func export(to destination: URL, loaded: LoadedDocument) {
        exportState = .exporting(fraction: 0)
        let watermark = AppPreferences.shared.watermarkEnabled
            ? "Redacted locally with RedactDesk · elephas.app"
            : nil
        let options = PDFRedactor.Options(
            enabled: enabledCategories,
            watermark: watermark
        )
        let spansCopy = spans
        let sourceDoc = loaded.document
        let redactedCount = spans.totalCount

        Task.detached(priority: .userInitiated) {
            do {
                try PDFRedactor.export(
                    source: sourceDoc,
                    spans: spansCopy,
                    options: options,
                    to: destination,
                    progress: { f in
                        Task { @MainActor in
                            self.exportState = .exporting(fraction: f)
                        }
                    }
                )
                await MainActor.run {
                    self.exportState = .done(destination)
                    // One export == one "redaction" for milestone purposes.
                    // We count the event, not the entity count, to keep the
                    // counter stable across the input's PII density.
                    _ = redactedCount
                    AppPreferences.shared.incrementRedactionCount()
                }
            } catch {
                await MainActor.run {
                    self.exportState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Toggles a category on/off for both preview overlays and export.
    func toggle(category: Design.Category) {
        if enabledCategories.contains(category) {
            enabledCategories.remove(category)
        } else {
            enabledCategories.insert(category)
        }
    }

    /// Opens the last exported file in Finder with the produced PDF selected.
    func revealExport() {
        if case .done(let url) = exportState {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Closes the current document.
    func closeDocument() {
        currentLoadTask?.cancel()
        currentDetectTask?.cancel()
        document = nil
        spans = .empty
        detectState = .idle
        exportState = .idle
    }
}
