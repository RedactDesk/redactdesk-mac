import SwiftUI

/// SwiftUI `Settings` scene body. Two tabs - General (behavioural prefs) and
/// "More from us" (a calm Elephas pitch that respects the "never nag" rule
/// in CLAUDE.md's attribution plan).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            MoreFromUsTab()
                .tabItem { Label("More from us", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 360)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section("Export") {
                Toggle(isOn: $prefs.watermarkEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include SafePaste watermark on exported PDFs")
                        Text("Small footer line: \"Redacted locally with SafePaste · elephas.app\". On by default - helps other people discover the app when you share a redacted file.")
                            .font(Design.Font.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Onboarding") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show welcome again")
                        Text("Re-displays the two-pane intro on next launch.")
                            .font(Design.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") { prefs.resetOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - More from us

private struct MoreFromUsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.sm) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Design.Brand.gradient)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elephas")
                        .font(Design.Font.title)
                    Text("From the makers of SafePaste")
                        .font(Design.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Elephas is our full Mac app for working with sensitive documents in AI: folder-wide redaction, summarization, and sensitive-document search, with a fully local processing mode.")
                .font(Design.Font.body)
                .foregroundStyle(Design.Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Space.xs) {
                FeatureChip(label: "Folder-wide redaction")
                FeatureChip(label: "Sensitive-doc search")
                FeatureChip(label: "Local mode")
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(ElephasLinks.landing(.settings))
                } label: {
                    Text("Learn about Elephas")
                }
                .buttonStyle(BrandPillButtonStyle())
            }
        }
        .padding(Design.Space.lg)
    }
}
