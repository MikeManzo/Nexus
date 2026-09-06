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

/// Identity for a `DesktopSpace`.
///
/// `systemToken` is a best-effort hint from whichever backend produced it (Accessibility label,
/// or ; if the experimental backend is enabled ; a private-API space id). It is not guaranteed
/// stable across reboot, logout, or an OS upgrade; see `docs/01-capability-research.md` §11.
/// `stableKey` is generated and persisted by Nexus itself and is what `SpaceMetadata` is keyed on,
/// so a custom name survives even when `systemToken` churns.
struct SpaceIdentifier: Hashable, Codable, Sendable {
    let systemToken: String?
    let stableKey: UUID

    init(systemToken: String? = nil, stableKey: UUID = UUID()) {
        self.systemToken = systemToken
        self.stableKey = stableKey
    }
}
