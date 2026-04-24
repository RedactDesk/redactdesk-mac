import Foundation

/// Centralised Elephas-facing URLs and identifiers. Every outbound link from
/// RedactDesk flows through here so that:
///
/// 1. The `?ref=` attribution param can never be forgotten at a call site.
///    Each surface gets its own `Ref` case, and the URL builder always
///    appends it.
/// 2. When Elephas's own deep-link routes land, we swap a single constant
///    here rather than grepping call sites.
enum ElephasLinks {
    // MARK: - Base

    static let siteBase = "https://elephas.app"

    // MARK: - Bundle identifiers
    //
    // Elephas ships under three different bundle IDs depending on
    // distribution channel. `ElephasDetector.isInstalled` must check all of
    // them before concluding Elephas isn't present.

    static let directBundleID = "com.kamban.elephas"
    static let appStoreBundleID = "com.kamban.elephas-appstore"
    static let setappBundleID = "com.kamban.elephas-setapp"

    static let allBundleIDs: [String] = [
        directBundleID, appStoreBundleID, setappBundleID,
    ]

    // MARK: - URL scheme

    /// Registered by Elephas in its Info.plist. RedactDesk v1.0 does not
    /// currently send any `elephas://` URLs - handoff is via
    /// `NSWorkspace.open(bundleURL)`. Retained here for v1.0.1+ when a
    /// `elephas://redact/open?path=…` route is defined on both sides.
    static let urlScheme = "elephas"

    // MARK: - Attribution refs
    //
    // One case per promotion surface. Naming is URL-safe and readable in
    // Gumroad's referrer reports; stable across versions so campaign
    // analytics can aggregate over time.

    enum Ref: String {
        case welcome   = "redactdesk-welcome"
        case postExport = "redactdesk-postexport"
        case handoff   = "redactdesk-handoff"
        case settings  = "redactdesk-settings"
        case about     = "redactdesk-about"
        case footer    = "redactdesk-footer"
        case helpMenu  = "redactdesk-help"
    }

    // MARK: - URL builders

    /// Canonical landing URL with a tagged `?ref=…` query param.
    static func landing(_ ref: Ref) -> URL {
        guard var components = URLComponents(string: siteBase) else {
            // siteBase is a literal - unreachable, but fall back safely.
            return URL(string: siteBase)!
        }
        components.queryItems = [URLQueryItem(name: "ref", value: ref.rawValue)]
        return components.url!
    }

    /// View-source link - the repo README lives here.
    static let repoURL = URL(string: "https://github.com/RedactDesk/redactdesk-mac")!
}
