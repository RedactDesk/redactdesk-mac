import SwiftUI
import UniformTypeIdentifiers

/// Top-level content view. Routes to either the empty drop zone or the
/// document workspace based on whether a PDF is loaded. Also surfaces the
/// first-run model preparation overlay.
struct RootView: View {
    @EnvironmentObject private var controller: DocumentController
    @EnvironmentObject private var prefs: AppPreferences
    @State private var isDraggingOverWindow: Bool = false
    @State private var showWelcome: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                backgroundLayer
                Group {
                    if controller.hasDocument {
                        DocumentView()
                    } else {
                        EmptyStateView(isDraggingOver: $isDraggingOverWindow)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: controller.hasDocument)

                if case .preparing(let fraction, let phase) = controller.modelState,
                   !controller.hasDocument {
                    ModelPreparingOverlay(fraction: fraction, phase: phase)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if case .failed(let message) = controller.modelState {
                    ModelFailureOverlay(message: message) { controller.prepareModel() }
                        .transition(.opacity)
                }
            }
            AttributionFooter()
        }
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOverWindow) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(isPresented: $showWelcome)
        }
        .onAppear {
            // Defer the sheet one runloop tick so the main window is on
            // screen first - otherwise the sheet animates in without a
            // backdrop on fresh launches.
            if prefs.needsOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showWelcome = true
                }
            }
        }
        .onChange(of: prefs.onboardingCompletedVersion) { _, newValue in
            // Settings → "Show welcome again" resets the version to 0. Re-open
            // the sheet immediately so the user can confirm it still works.
            if newValue < AppPreferences.currentOnboardingVersion {
                showWelcome = true
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("SafePaste")
                .font(Design.Font.headline)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if controller.hasDocument {
                Button(role: .destructive) {
                    controller.closeDocument()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close this document")

                Button {
                    controller.requestExport()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canExport)
                .help("Export a redacted copy")
            } else {
                Button {
                    controller.presentOpenPanel()
                } label: {
                    Label("Open PDF", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled({
                    if case .preparing = controller.modelState { return true }
                    if case .failed = controller.modelState { return true }
                    return false
                }())
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Subtle large accent orb in the upper-left for warmth.
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 500, height: 500)
                .blur(radius: 120)
                .offset(x: -240, y: -220)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Drag & drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                controller.open(url: url)
            }
        }
        return true
    }
}

// MARK: - Model preparation overlay

private struct ModelPreparingOverlay: View {
    let fraction: Double
    let phase: String

    var body: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 4) {
                Text("Setting up SafePaste")
                    .font(Design.Font.title)
                Text(phase)
                    .font(Design.Font.callout)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .frame(width: 280)
            Text("\(Int(fraction * 100))%")
                .font(Design.Font.monoSmall)
                .foregroundStyle(.secondary)
            Text("SafePaste runs 100% on your Mac. Nothing leaves this device.")
                .font(Design.Font.caption)
                .foregroundStyle(.secondary.opacity(0.8))
                .padding(.top, Design.Space.xs)
        }
        .padding(Design.Space.xl)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .strokeBorder(Design.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 30, y: 8)
        .padding(Design.Space.lg)
    }
}

private struct ModelFailureOverlay: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.red)
            VStack(spacing: 4) {
                Text("Could not set up SafePaste")
                    .font(Design.Font.title)
                Text(message)
                    .font(Design.Font.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(Design.Space.xl)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 30, y: 8)
    }
}
