import Foundation
import Observation

/// What Settings → Updates binds to. Exists so that view code depends on a small, `@Observable`
/// surface rather than reaching into `UpdateManaging` (a plain protocol, not itself Observable)
/// or, worse, a Sparkle type directly.
@MainActor
@Observable
final class UpdatePreferences {
    private let updateManager: UpdateManaging

    init(updateManager: UpdateManaging) {
        self.updateManager = updateManager
    }

    var automaticallyChecksForUpdates: Bool {
        get { updateManager.automaticallyChecksForUpdates }
        set { updateManager.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updateManager.automaticallyDownloadsUpdates }
        set { updateManager.automaticallyDownloadsUpdates = newValue }
    }

    var canCheckForUpdates: Bool { updateManager.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { updateManager.lastUpdateCheckDate }
    var installedVersion: String { Bundle.main.shortVersionString }

    func checkForUpdates() {
        updateManager.checkForUpdates()
    }
}
