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

/// Abstraction over "however we're currently able to talk to Mission Control."
///
/// Deliberately narrower than the spec's original sketch: renaming is **not** a system operation
/// (macOS has nothing to rename ; see `docs/01-capability-research.md` §2) so it is not part of
/// this protocol. Renaming is handled entirely by `SpaceMetadataStoring`, called directly from
/// `AppCoordinator`. Keeping that split explicit means a conforming backend can never be tempted
/// to fake a system-level rename.
///
/// Conformers, by tier (see the research doc for the full tradeoff writeup):
/// - Tier 2 `AccessibilitySpaceManager` (default) ; drives Mission Control's accessibility tree.
/// - Tier 3 `ExperimentalSpaceManager` (opt-in, off by default) ; undocumented SkyLight symbols.
/// - `MockSpaceManager` ; in-memory, used until Tier 2 lands (Phase 4+) and in tests/previews.
@MainActor
protocol SpaceManaging: AnyObject {
    func spaces() async throws -> [DesktopSpace]
    func activeSpace() async throws -> DesktopSpace?
    func activate(_ space: DesktopSpace) async throws
    func createSpace() async throws -> DesktopSpace
    func delete(_ space: DesktopSpace) async throws
}
