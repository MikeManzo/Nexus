//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit

/// Wraps the one public Spaces signal macOS provides —
/// `NSWorkspace.activeSpaceDidChangeNotification` — which carries no identity, count, or name
/// (`docs/01-capability-research.md` §2). It exists only to *log* that an external change
/// happened, not to trigger a live re-read: the only way to actually re-read state through the
/// Tier 2 backend is to briefly present Mission Control, and doing that automatically on every
/// space switch (including ones the user makes with a trackpad swipe, many times an hour) would
/// make Nexus far more disruptive than the Mission Control access it's meant to replace.
///
/// So: cached state can go briefly stale after an external change, until the user next performs
/// an action that already justifies a live read (opening Manage Desktops, switching/creating/
/// deleting through Nexus). Surfacing that staleness in the UI is left to Phase 10 polish.
@MainActor
final class SystemSpaceObserver {
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Log.spaceManager.info("Detected an external active-space change (cached state may be stale until next refresh)")
        }
    }
}
