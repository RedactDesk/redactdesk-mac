import SwiftUI

/// Two-pane first-run onboarding. Shown once per install version via
/// `AppPreferences.needsOnboarding`. Dismissible at any time - the welcome
/// is polite, not blocking, so a user can always skip straight into the app.
///
/// Layout mirrors the milestone modals in the design: centred card, indigo
/// brand badge at top-left, serif headline, body copy, two pill CTAs
/// bottom-right (primary + secondary).
struct WelcomeView: View {
    @Binding var isPresented: Bool

    @State private var paneIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                BrandBadge(paneIndex == 0 ? "Welcome" : "About us")

                Group {
                    if paneIndex == 0 {
                        pane1
                    } else {
                        pane2
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                Spacer(minLength: Design.Space.md)

                footerControls
            }
            .padding(Design.Space.xl)
            .frame(width: 560, height: 420)

            closeButton
                .padding(Design.Space.md)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.xxl, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 30, y: 8)
        .animation(.easeInOut(duration: 0.25), value: paneIndex)
    }

    // MARK: - Panes

    private var pane1: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("Redact PII before it leaves your Mac.")
                .font(Design.Font.serifDisplay)
                .foregroundStyle(Design.Palette.fg)
                .fixedSize(horizontal: false, vertical: true)

            Text("RedactDesk finds sensitive information in PDFs (names, emails, phone numbers, addresses, account numbers) and removes it cleanly, so you can share the redacted copy with any AI or any person without worry.")
                .font(Design.Font.body)
                .foregroundStyle(Design.Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Space.xs) {
                FeatureChip(label: "100% on-device")
                FeatureChip(label: "No telemetry")
                FeatureChip(label: "Irreversible redaction")
            }
            .padding(.top, Design.Space.xs)

            poweredByLine
                .padding(.top, Design.Space.xxs)
        }
    }

    /// Small trust caption under the feature chips. Cites the open-source
    /// model RedactDesk uses, with a tap-to-open link to OpenAI's launch post.
    /// Rendered via SwiftUI markdown so the link is keyboard-accessible and
    /// respects the accent tint without us hand-rolling an NSAttributedString.
    private var poweredByLine: some View {
        let markdown: LocalizedStringKey = "Powered by OpenAI's open-source [privacy-filter](https://openai.com/index/introducing-openai-privacy-filter/) model, running on your Mac."
        return Text(markdown)
            .font(Design.Font.caption)
            .foregroundStyle(Design.Palette.fgSubtle)
            .tint(Design.Brand.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pane2: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("Built by the Elephas team.")
                .font(Design.Font.serifDisplay)
                .foregroundStyle(Design.Palette.fg)
                .fixedSize(horizontal: false, vertical: true)

            Text("Elephas is our full Mac app for working with sensitive documents in AI: folder-wide redaction, summarization, and sensitive-document search, with a fully local processing mode. RedactDesk is a small, open-source slice of that world.")
                .font(Design.Font.body)
                .foregroundStyle(Design.Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Space.xs) {
                FeatureChip(label: "Folder-wide redaction")
                FeatureChip(label: "Sensitive-doc search")
                FeatureChip(label: "Free to try")
            }
            .padding(.top, Design.Space.xs)
        }
    }

    // MARK: - Chrome

    private var footerControls: some View {
        HStack {
            pageDots
            Spacer()
            if paneIndex == 0 {
                Button("Get started") {
                    withAnimation { paneIndex = 1 }
                }
                .buttonStyle(BrandPillButtonStyle(size: .large))
            } else {
                Button("Learn about Elephas") {
                    NSWorkspace.shared.open(ElephasLinks.landing(.welcome))
                }
                .buttonStyle(GhostPillButtonStyle(size: .large))

                Button("Start using RedactDesk") {
                    dismiss()
                }
                .buttonStyle(BrandPillButtonStyle(size: .large))
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<2) { idx in
                Circle()
                    .fill(idx == paneIndex ? Design.Brand.primary : Design.Palette.border)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Palette.fgSubtle)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Design.Palette.bgMuted)
                )
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        AppPreferences.shared.markOnboardingComplete()
        isPresented = false
    }
}
