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

/// Assigns stable `stableKey`s to freshly observed spaces by matching them against the last known
/// snapshot.
///
/// Strategy, in order:
/// 1. Match by `systemToken`, when both sides have one — a genuine persistent identifier
///    (`ManagedSpaceID`, only available from the Tier 3 private-API backend; Accessibility
///    exposes nothing this stable — see `docs/01-capability-research.md` §11).
/// 2. Match by identical `systemLabel` text — a full-screen app's stable name, or a generic
///    "Desktop N" whose N shifts for every space after one that gets deleted, so this is a weaker
///    signal than a token match but stronger than raw position.
/// 3. Match by identical order position.
/// 4. Anything left over is treated as newly created and gets a fresh key.
enum SpaceReconciler {
    struct Observation {
        let order: Int
        let systemLabel: String
        let isActive: Bool
        let displayID: UInt32?
        var systemToken: String?

        init(order: Int, systemLabel: String, isActive: Bool, displayID: UInt32?, systemToken: String? = nil) {
            self.order = order
            self.systemLabel = systemLabel
            self.isActive = isActive
            self.displayID = displayID
            self.systemToken = systemToken
        }
    }

    static func reconcile(previous: [DesktopSpace], observed: [Observation]) -> [DesktopSpace] {
        var remainingPrevious = previous
        var result: [DesktopSpace] = []

        for observation in observed {
            if let token = observation.systemToken,
               let index = remainingPrevious.firstIndex(where: { $0.identifier.systemToken == token }) {
                result.append(merge(remainingPrevious.remove(at: index), observation))
                continue
            }
            if let index = remainingPrevious.firstIndex(where: { $0.systemLabel == observation.systemLabel }) {
                result.append(merge(remainingPrevious.remove(at: index), observation))
                continue
            }
            if let index = remainingPrevious.firstIndex(where: { $0.order == observation.order }) {
                result.append(merge(remainingPrevious.remove(at: index), observation))
                continue
            }
            result.append(
                DesktopSpace(
                    identifier: SpaceIdentifier(systemToken: observation.systemToken ?? observation.systemLabel),
                    order: observation.order,
                    isActive: observation.isActive,
                    displayID: observation.displayID,
                    systemLabel: observation.systemLabel,
                    customName: nil,
                    symbolName: nil
                )
            )
        }

        return result
    }

    private static func merge(_ existing: DesktopSpace, _ observation: Observation) -> DesktopSpace {
        var updated = existing
        updated.order = observation.order
        updated.isActive = observation.isActive
        updated.systemLabel = observation.systemLabel
        updated.displayID = observation.displayID
        return updated
    }

    // MARK: - Cross-launch snapshot

    // Without this, `previous` is always `[]` on the very first `reconcile` call after a fresh
    // launch (both backends' `lastKnownSpaces` start empty), so every space falls through to the
    // "newly created" branch above and gets a brand-new random `stableKey` — meaning
    // `SpaceMetadataStore`'s saved names/colors, keyed by the *old* stableKey, would never be
    // found again after quitting and relaunching Nexus, even though that file itself persists
    // correctly. Persisting the last reconciled snapshot here and loading it as `previous` for a
    // backend's first call after launch lets rule 2/3 (label/order matching) recover the same
    // stableKeys, so metadata lookups keep hitting. Both `AccessibilitySpaceManager` and
    // `ExperimentalSpaceManager` share this one file — reconciliation only ever matches by
    // label/order/token regardless of which backend wrote it, so this is safe even if the user
    // switches backends between launches.

    static func loadSnapshot() -> [DesktopSpace] {
        guard let data = try? Data(contentsOf: snapshotURL()),
              let decoded = try? JSONDecoder().decode([DesktopSpace].self, from: data)
        else {
            return []
        }
        return decoded
    }

    static func saveSnapshot(_ spaces: [DesktopSpace]) {
        guard let data = try? JSONEncoder().encode(spaces) else {
            Log.persistence.error("Failed to encode space reconciliation snapshot")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL().deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL(), options: .atomic)
        } catch {
            Log.persistence.error("Failed to write space reconciliation snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func snapshotURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Nexus", isDirectory: true)
            .appendingPathComponent("space-reconciliation-snapshot.json")
    }
}
