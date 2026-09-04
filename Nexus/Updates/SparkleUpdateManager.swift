import Foundation
import Observation
import Sparkle

/// The only file in Nexus that imports Sparkle. Everything else depends on `UpdateManaging`.
///
/// Uses `SPUStandardUpdaterController` (Sparkle's own standard UI: update-available dialogs,
/// permission prompts, progress) rather than a custom user-driver — per the spec's "use Sparkle's
/// established update experience" requirement. `automaticallyChecksForUpdates` and
/// `automaticallyDownloadsUpdates` forward directly to `SPUUpdater`, which persists them itself;
/// Nexus does not duplicate that storage.
@MainActor
@Observable
final class SparkleUpdateManager: NSObject, UpdateManaging {
    // Implicitly-unwrapped: Sparkle's delegate must be supplied at init time, which means `self`
    // has to be fully valid first — so `super.init()` runs before `controller` is assigned.
    // Optional-typed stored properties don't block that definite-initialization check.
    private var controller: SPUStandardUpdaterController!
    private(set) var lastUpdateCheckDate: Date?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        Log.sparkle.info("SPUStandardUpdaterController started")
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        Log.sparkle.info("User-initiated update check")
        controller.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        Log.sparkle.info("Background update check")
        controller.updater.checkForUpdatesInBackground()
    }
}

extension SparkleUpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            self.lastUpdateCheckDate = updater.lastUpdateCheckDate
            if let error {
                Log.sparkle.error("Update cycle finished with error: \(error.localizedDescription, privacy: .public)")
            } else {
                Log.sparkle.info("Update cycle finished")
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Log.sparkle.error("Updater aborted: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Log.sparkle.error("Failed to download update \(item.versionString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}
