import SwiftUI

/// Retains the `PII_RedactorApp` type name to avoid a full Xcode-target
/// rename; the user-facing product is "SafePaste" (see
/// INFOPLIST_KEY_CFBundleDisplayName in the build settings).
@main
struct PII_RedactorApp: App {
    @StateObject private var controller = DocumentController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
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
        }
    }
}
