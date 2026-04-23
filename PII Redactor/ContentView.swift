import Combine
import SwiftUI

@MainActor
final class RedactorViewModel: ObservableObject {
    enum ModelState: Equatable {
        case idle
        case loading(fraction: Double)
        case ready
        case failed(String)
    }

    enum RunState: Equatable {
        case idle
        case running
        case done(elapsed: TimeInterval)
        case failed(String)
    }

    @Published var input: String = RedactorViewModel.defaultSample
    @Published var modelState: ModelState = .idle
    @Published var runState: RunState = .idle
    @Published var result: RedactionResult?
    @Published var variant: PrivacyFilter.ModelVariant = .q4

    private var filter: PrivacyFilter

    init() {
        self.filter = PrivacyFilter(variant: .q4)
    }

    func loadModel() {
        guard modelState != .ready else { return }
        if case .loading = modelState { return }
        modelState = .loading(fraction: 0)
        let selected = variant
        filter = PrivacyFilter(variant: selected)
        Task { [filter] in
            do {
                try await filter.load { fraction in
                    Task { @MainActor in
                        self.modelState = .loading(fraction: fraction)
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

    func redact() {
        guard modelState == .ready else { return }
        let text = input
        runState = .running
        Task { [filter] in
            let started = Date()
            do {
                let result = try await filter.detect(text: text)
                let elapsed = Date().timeIntervalSince(started)
                await MainActor.run {
                    self.result = result
                    self.runState = .done(elapsed: elapsed)
                }
            } catch {
                await MainActor.run {
                    self.runState = .failed(error.localizedDescription)
                }
            }
        }
    }

    static let defaultSample = """
    Hi, this is Alice Chen. Please email me at alice.chen@example.com or call \
    +1 (415) 555-0199. Wire payment to account 4111 1111 1111 1111 at Chase. \
    My API key is sk-proj-abc123XYZ and the dashboard lives at \
    https://admin.example.com/u/alice. I'll be there on March 5th, 2026 at \
    221B Baker Street, London.
    """
}

struct ContentView: View {
    @StateObject private var vm = RedactorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                inputPane
                    .frame(minWidth: 320)
                outputPane
                    .frame(minWidth: 320)
            }
        }
        .frame(minWidth: 860, minHeight: 520)
        .task {
            vm.loadModel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("PII Redactor")
                    .font(.headline)
                Text("openai/privacy-filter · on-device via ONNX Runtime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            modelStatus

            Button {
                vm.redact()
            } label: {
                Label("Redact", systemImage: "wand.and.stars")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(vm.modelState != .ready || vm.runState == .running)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch vm.modelState {
        case .idle:
            Label("Idle", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .loading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                Text("Downloading \(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Model ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failed(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $vm.input)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator)
                )
            HStack {
                Text("\(vm.input.count) characters")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset sample") {
                    vm.input = RedactorViewModel.defaultSample
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(16)
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Redacted output")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                runStatus
            }

            ScrollView {
                highlightedOutput
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator)
            )

            if let spans = vm.result?.spans, !spans.isEmpty {
                spanSummary(spans)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var runStatus: some View {
        switch vm.runState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .done(let elapsed):
            Text(String(format: "%.0f ms · %d spans", elapsed * 1000, vm.result?.spans.count ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var highlightedOutput: some View {
        if let result = vm.result {
            Text(Self.attributed(from: result))
                .font(.system(.body, design: .monospaced))
        } else {
            Text("Press Redact (⌘↩) to scan the input. Detected entities will highlight here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func spanSummary(_ spans: [RedactionSpan]) -> some View {
        let grouped = Dictionary(grouping: spans, by: { $0.label })
        return FlowLayout(spacing: 6) {
            ForEach(grouped.keys.sorted(), id: \.self) { label in
                let count = grouped[label]?.count ?? 0
                Text("\(Self.prettyLabel(label)) · \(count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Self.color(for: label).opacity(0.18))
                    )
                    .foregroundStyle(Self.color(for: label))
            }
        }
    }

    // MARK: - Styling

    private static func attributed(from result: RedactionResult) -> AttributedString {
        var attr = AttributedString(result.text)
        let scalarCount = result.text.unicodeScalars.count
        for span in result.spans {
            guard span.start >= 0, span.end <= scalarCount, span.start < span.end else {
                continue
            }
            let lower = attr.index(attr.startIndex, offsetByUnicodeScalars: span.start)
            let upper = attr.index(attr.startIndex, offsetByUnicodeScalars: span.end)
            let range = lower..<upper
            attr[range].backgroundColor = color(for: span.label).opacity(0.22)
            attr[range].foregroundColor = color(for: span.label)
        }
        return attr
    }

    fileprivate static func color(for label: String) -> Color {
        switch label {
        case "private_person": .blue
        case "private_email": .teal
        case "private_phone": .mint
        case "private_address": .indigo
        case "private_date": .purple
        case "private_url": .cyan
        case "account_number": .orange
        case "secret": .red
        default: .gray
        }
    }

    fileprivate static func prettyLabel(_ label: String) -> String {
        switch label {
        case "private_person": "person"
        case "private_email": "email"
        case "private_phone": "phone"
        case "private_address": "address"
        case "private_date": "date"
        case "private_url": "url"
        case "account_number": "account"
        case "secret": "secret"
        default: label
        }
    }
}

// MARK: - FlowLayout

/// A minimal wrapping HStack so span summary chips wrap instead of clipping.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth - spacing)
        return CGSize(width: maxRowWidth.isFinite ? maxRowWidth : 0, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    ContentView()
}
