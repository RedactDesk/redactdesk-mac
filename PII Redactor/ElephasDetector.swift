import AppKit
import Foundation

/// Detects whether Elephas is installed on the user's Mac and, if so,
/// opens it. v1.0 uses `NSWorkspace.open(bundleURL)` (no deep link) to keep
/// SafePaste's release train decoupled from Elephas's. A proper
/// `elephas://redact/open?path=...` handoff route requires a matching handler
/// in Elephas's `AppDelegate`.
enum ElephasDetector {
    /// `true` if any of the Elephas bundle variants (direct / MAS / Setapp)
    /// are installed. Computed on each call -cheap enough for a post-export
    /// UI that renders once per export.
    static var isInstalled: Bool { installedBundleURL != nil }

    /// The `URL` on disk of whichever Elephas variant is installed, or `nil`.
    static var installedBundleURL: URL? {
        for bundleID in ElephasLinks.allBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        return nil
    }

    /// Launches the installed Elephas app. No-op if Elephas isn't installed.
    /// Callers are expected to route users to the landing page in that case
    /// (see `ElephasLinks.landing(.handoff)`).
    static func openElephas() {
        guard let url = installedBundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                // Intentional: no user-facing surface for this today. If
                // launch fails (quarantine prompt, corrupted bundle, etc.)
                // the worst case is a silent no-op, which is acceptable for
                // a promotional button.
                NSLog("SafePaste: failed to open Elephas -\(error.localizedDescription)")
            }
        }
    }
}
