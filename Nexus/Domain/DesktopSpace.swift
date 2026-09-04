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

/// A single macOS desktop/Space, as understood by Nexus.
///
/// `systemLabel` is whatever generic label the backend observed ("Desktop 3"); macOS has no
/// concept of a user-assigned Space name at all, so `customName` is always Nexus-owned metadata
/// layered on top, never a value read from or written to the system. See
/// `docs/01-capability-research.md` for why.
struct DesktopSpace: Identifiable, Hashable, Sendable, Codable {
    var id: SpaceIdentifier { identifier }

    let identifier: SpaceIdentifier
    var order: Int
    var isActive: Bool
    var displayID: UInt32?
    var systemLabel: String?
    var customName: String?
    var symbolName: String?
    /// User-assigned accent color as `#RRGGBB`, or `nil` for the app's default accent. Shown
    /// consistently as this desktop's identity everywhere it appears — popover, Space Manager,
    /// and (via `AccentPalette`) in the color picker itself.
    var accentColorHex: String?

    var displayName: String {
        customName ?? systemLabel ?? "Desktop \(order + 1)"
    }
}
