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
import Observation

/// Stands in for `SparkleUpdateManager` in tests and previews. Exercises the same
/// `UpdateManaging` surface the real Sparkle-backed implementation does, backed by plain stored
/// properties instead of `SPUUpdater`.
@MainActor
@Observable
final class MockUpdateManager: UpdateManaging {
    private(set) var canCheckForUpdates: Bool = true
    private(set) var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false

    func checkForUpdates() {
        Log.updates.info("Mock: user-initiated update check")
        lastUpdateCheckDate = Date()
    }

    func checkForUpdatesInBackground() {
        Log.updates.info("Mock: background update check")
        lastUpdateCheckDate = Date()
    }
}
