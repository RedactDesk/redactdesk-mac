import Combine
import Foundation
import Sparkle
import SwiftUI

/// SwiftUI-friendly wrapper around `SPUStandardUpdaterController`.
///
/// Sparkle's `SPUStandardUpdater` is an Obj-C object whose properties are
/// KVO-observable but not directly usable from a SwiftUI view. This class
/// owns the controller and republishes the two pieces of state the UI needs:
/// whether an update check can currently start, and whether automatic checks
/// are enabled. Views bind to those `@Published` values; mutations round-trip
/// through `SPUUpdater` so Sparkle's own `UserDefaults` keys stay authoritative.
///
/// The controller is created eagerly (`startingUpdater: true`) so the first
/// scheduled check fires on launch without any extra wiring.
@MainActor
final class UpdaterViewModel: NSObject, ObservableObject {
    /// Whether the Check For Updates menu item should be enabled. Sparkle
    /// disables it while a check is in flight.
    @Published var canCheckForUpdates = false

    /// Mirrored `SPUUpdater.automaticallyChecksForUpdates`. Two-way binding for
    /// the Settings toggle; the setter forwards to Sparkle so it persists to
    /// the standard `SUEnableAutomaticChecks` default.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    let controller: SPUStandardUpdaterController

    private var cancellables: Set<AnyCancellable> = []

    override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)

        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self, self.automaticallyChecksForUpdates != value else { return }
                self.automaticallyChecksForUpdates = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Menu-bar button that triggers `checkForUpdates(_:)`. Declared here rather
/// than inline in the App body so the App file stays focused on scene wiring.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
