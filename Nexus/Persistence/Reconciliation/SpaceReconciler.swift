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
}
