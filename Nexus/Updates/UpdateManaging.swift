import Foundation

/// Isolates the rest of Nexus from Sparkle. Only `SparkleUpdateManager` may `import Sparkle`.
///
/// `automaticallyChecksForUpdates`/`automaticallyDownloadsUpdates` are read/write here rather
/// than mirrored into a separate Nexus preferences store: `SparkleUpdateManager` forwards them
/// straight through to `SPUUpdater`'s own persisted settings, so there is exactly one source of
/// truth for update behavior, per the "do not build a custom update engine" rule.
@MainActor
protocol UpdateManaging: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
    func checkForUpdatesInBackground()
}
