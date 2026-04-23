import SwiftUI
import UniformTypeIdentifiers

/// Initial screen shown when no document is loaded. Big drop zone + secondary
/// "Open PDF" button + marketing copy.
struct EmptyStateView: View {
    @EnvironmentObject private var controller: DocumentController
    @Binding var isDraggingOver: Bool

    var body: some View {
        VStack(spacing: Design.Space.xl) {
            Spacer(minLength: Design.Space.lg)

            dropZone

            Spacer(minLength: Design.Space.md)

            featureRow

            Spacer(minLength: Design.Space.lg)
        }
        .padding(Design.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: Design.Space.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 96, height: 96)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: Design.Space.xs) {
                Text("Redact PII from any PDF")
                    .font(Design.Font.largeTitle)
                Text("Drop a PDF here or open one to get started.")
                    .font(Design.Font.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                controller.presentOpenPanel()
            } label: {
                Label("Open PDF", systemImage: "doc.badge.plus")
                    .padding(.horizontal, Design.Space.sm)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            .disabled({
                if case .preparing = controller.modelState { return true }
                if case .failed = controller.modelState { return true }
                return false
            }())
        }
        .padding(Design.Space.xxl)
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .fill(isDraggingOver ? Design.dropHighlight : Color.clear)
                .animation(.easeOut(duration: 0.15), value: isDraggingOver)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .strokeBorder(
                    isDraggingOver ? Color.accentColor : Design.separator,
                    style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1, dash: isDraggingOver ? [] : [6, 4])
                )
                .animation(.easeOut(duration: 0.15), value: isDraggingOver)
        )
    }

    // MARK: - Feature row

    private var featureRow: some View {
        HStack(alignment: .top, spacing: Design.Space.md) {
            Feature(
                icon: "cpu",
                title: "100% on-device",
                detail: "Your documents never leave this Mac. No cloud. No telemetry."
            )
            Feature(
                icon: "sparkles",
                title: "8 entity categories",
                detail: "People, emails, phones, addresses, dates, URLs, account numbers, secrets."
            )
            Feature(
                icon: "lock.shield",
                title: "Irreversible redaction",
                detail: "Redacted content is removed from the exported PDF, not just hidden."
            )
        }
        .frame(maxWidth: 820)
    }

    private struct Feature: View {
        let icon: String
        let title: String
        let detail: String

        var body: some View {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(Design.Font.headline)
                Text(detail)
                    .font(Design.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                    .fill(Design.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                    .strokeBorder(Design.separator.opacity(0.4), lineWidth: 0.5)
            )
        }
    }
}
