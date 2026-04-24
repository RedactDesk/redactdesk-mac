import SwiftUI

/// Retains the `PII_RedactorApp` type name to avoid a full Xcode-target
/// rename; the user-facing product is "RedactDesk" (see
/// INFOPLIST_KEY_CFBundleDisplayName in the build settings).
@main
struct PII_RedactorApp: App {
    @StateObject private var controller = DocumentController()
    @StateObject private var prefs = AppPreferences.shared
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .environmentObject(prefs)
                .frame(minWidth: 980, minHeight: 640)
                .navigationTitle("RedactDesk")
                // Design tokens in DesignSystem.swift are hardcoded light
                // sRGB values (bgSoft, fg, border, GhostPill's Color.white,
                // etc.). Rendering under dark appearance leaves text
                // invisible on near-white surfaces. Pin the app to light
                // until the palette has a real dark counterpart.
                .preferredColorScheme(.light)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") { controller.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Export Redacted PDF…") { controller.requestExport() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!controller.canExport)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About RedactDesk") { showAbout() }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
            CommandGroup(replacing: .help) {
                Button("RedactDesk Help") {
                    NSWorkspace.shared.open(ElephasLinks.repoURL)
                }
                Divider()
                Button("Discover Elephas") {
                    NSWorkspace.shared.open(ElephasLinks.landing(.helpMenu))
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(updater)
                .preferredColorScheme(.light)
        }
    }

    /// Presents the standard About panel with Elephas attribution in the
    /// credits field. Credits accept HTML via the `.credits` option, which
    /// lets us render a clickable `elephas.app` link without having to stand
    /// up a custom NSPanel.
    private func showAbout() {
        let creditsHTML = """
        <p style="font-family:-apple-system; font-size:11px; color:#374151; line-height:1.5; text-align:center;">
        RedactDesk redacts sensitive information from PDFs entirely on your Mac.<br/>
        Nothing is sent to any server.
        </p>
        <p style="font-family:-apple-system; font-size:11px; color:#6B7280; line-height:1.5; text-align:center;">
        Built by the <a href="\(ElephasLinks.landing(.about).absoluteString)">Elephas</a> team.
        </p>
        """

        let credits: NSAttributedString = {
            if let data = creditsHTML.data(using: .utf8),
               let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
               ) {
                return attributed
            }
            return NSAttributedString(string: "Built by the Elephas team.")
        }()

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: credits,
            NSApplication.AboutPanelOptionKey.applicationName: "RedactDesk",
        ])
    }
}
