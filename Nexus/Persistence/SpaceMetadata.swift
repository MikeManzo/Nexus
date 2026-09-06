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

/// Nexus-owned metadata for a Space, keyed by `SpaceIdentifier.stableKey`. Deliberately separate
/// from `DesktopSpace` (system-derived) so persistence code never accidentally treats a
/// system-observed value as something Nexus is free to overwrite, or vice versa.
struct SpaceMetadata: Codable, Sendable, Equatable {
    var stableKey: UUID
    var customName: String?
    var symbolName: String?
    var accentColorHex: String?
    var createdAt: Date
    /// Bundle identifiers to launch (if not already running) whenever you switch to this desktop.
    /// Optional, not defaulted to `[]` — a non-optional new field would fail to decode any
    /// already-saved metadata file that predates it, silently discarding every name/color already
    /// on disk. `nil` means "none configured," same as an empty list.
    var launchAppBundleIDs: [String]?
    /// A global shortcut bound to *this specific desktop* (by `stableKey`, so it survives renames
    /// and reordering) rather than to a numbered slot — see `HotkeyCoordinator`'s per-space
    /// registration. Optional for the same decode-safety reason as `launchAppBundleIDs`.
    var shortcut: KeyboardShortcut?
}
