import Combine
import Foundation
import SwiftUI

/// Central wrapper around `UserDefaults` for SafePaste preferences that need
/// to persist across launches. Exposed as a single `@MainActor` observable so
/// views can `@EnvironmentObject` it and react to toggles without each view
/// threading its own `@AppStorage` key.
///
/// Keys are namespaced `safepaste.*` to keep the plist legible during debug.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    /// Bumped when the welcome flow gains a new required pane. A user who
    /// completed v1 stays completed for v1; a future v2 can re-show its own
    /// delta pane without re-running v1 for everyone.
    static let currentOnboardingVersion: Int = 1

    private enum Key {
        static let onboardingCompletedVersion = "safepaste.onboarding.completedVersion"
        static let watermarkEnabled           = "safepaste.export.watermarkEnabled"
        static let redactionCount             = "safepaste.stats.redactionCount"
    }

    private let defaults: UserDefaults

    @Published var watermarkEnabled: Bool {
        didSet { defaults.set(watermarkEnabled, forKey: Key.watermarkEnabled) }
    }

    @Published var onboardingCompletedVersion: Int {
        didSet { defaults.set(onboardingCompletedVersion, forKey: Key.onboardingCompletedVersion) }
    }

    @Published var redactionCount: Int {
        didSet { defaults.set(redactionCount, forKey: Key.redactionCount) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Watermark defaults to ON -opt-out, not opt-in, so early users see
        // the attribution until they actively disable it.
        if defaults.object(forKey: Key.watermarkEnabled) == nil {
            defaults.set(true, forKey: Key.watermarkEnabled)
        }
        self.watermarkEnabled           = defaults.bool(forKey: Key.watermarkEnabled)
        self.onboardingCompletedVersion = defaults.integer(forKey: Key.onboardingCompletedVersion)
        self.redactionCount             = defaults.integer(forKey: Key.redactionCount)
    }

    // MARK: - Derived

    var needsOnboarding: Bool {
        onboardingCompletedVersion < Self.currentOnboardingVersion
    }

    // MARK: - Mutations

    func markOnboardingComplete() {
        onboardingCompletedVersion = Self.currentOnboardingVersion
    }

    func resetOnboarding() {
        onboardingCompletedVersion = 0
    }

    /// Called once per successful export. Drives the milestone prompts
    /// planned for v1.1 -the counter is safe to increment now so that
    /// milestone UI can drop in without a data migration.
    func incrementRedactionCount(by amount: Int = 1) {
        guard amount > 0 else { return }
        redactionCount += amount
    }
}
