//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

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
