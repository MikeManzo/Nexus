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
}
