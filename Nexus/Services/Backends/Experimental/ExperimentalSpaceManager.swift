import Foundation

/// Tier 3 `SpaceManaging`: reads and switches spaces via the private `CGSCopyManagedDisplaySpaces`
/// / `CGSManagedDisplaySetCurrentSpace` API (`PrivateSpacesAPI`), verified against a real dump
/// from this exact machine (`~/Library/Application Support/Nexus/diagnostics/private-spaces-dump-*.txt`)
/// rather than assumed dictionary keys.
///
/// Deliberately narrow: **only** `spaces()`/`activeSpace()`/`activate(_:)` use the private API.
/// `createSpace()`/`delete(_:)` delegate to `AccessibilitySpaceManager` — `CGSSpaceCreate` and
/// `CGSSpaceDestroy` exist, but nothing in the community reverse-engineering confirms the full,
/// correct sequence to attach a newly created space to a display's visible rotation (or safely
/// detach one before destroying it) without risking a corrupted or orphaned space on a real
/// system. Switching is the operation that actually benefits from being silent and happens far
/// more often than create/delete, so that's what's worth the private-API risk; create/delete stay
/// on the already-proven Mission Control path.
///
/// If the private API is unavailable for any reason (symbol resolution failure, a future macOS
/// changing this undocumented structure), every method here falls back to the Accessibility
/// backend automatically rather than throwing — see `docs/01-capability-research.md` §11 on why
/// this can't be treated as a guaranteed-stable mechanism.
@MainActor
final class ExperimentalSpaceManager: SpaceManaging {
    private let fallback: AccessibilitySpaceManager
    private var lastKnownSpaces: [DesktopSpace] = []

    init(fallback: AccessibilitySpaceManager = AccessibilitySpaceManager()) {
        self.fallback = fallback
    }

    func spaces() async throws -> [DesktopSpace] {
        guard let observed = Self.readObservations() else {
            Log.spaceManager.info("Private Spaces API unavailable, falling back to Accessibility")
            return try await fallback.spaces()
        }
        let reconciled = SpaceReconciler.reconcile(previous: lastKnownSpaces, observed: observed)
        lastKnownSpaces = reconciled
        return reconciled
    }

    func activeSpace() async throws -> DesktopSpace? {
        try await spaces().first { $0.isActive }
    }

    func activate(_ space: DesktopSpace) async throws {
        guard let cid = PrivateSpacesAPI.connectionID(),
              let displayIdentifier = Self.mainDisplayIdentifier(),
              let token = space.identifier.systemToken,
              let managedID = UInt(token)
        else {
            try await fallback.activate(space)
            return
        }
        PrivateSpacesAPI.setCurrentSpace(cid: cid, display: displayIdentifier as CFString, spaceID: managedID)
        Log.spaceManager.info("Silent switch via private API to space \(managedID, privacy: .public)")
        try? await Task.sleep(for: .milliseconds(150))
    }

    func createSpace() async throws -> DesktopSpace {
        try await fallback.createSpace()
    }

    func delete(_ space: DesktopSpace) async throws {
        try await fallback.delete(space)
    }

    // MARK: - Private API structure (verified, not assumed — see the diagnostic dump referenced above)

    private static func readObservations() -> [SpaceReconciler.Observation]? {
        guard PrivateSpacesAPI.isAvailable,
              let cid = PrivateSpacesAPI.connectionID(),
              let displaysArray = PrivateSpacesAPI.managedDisplaySpaces(cid: cid) as? [[String: Any]],
              let firstDisplay = displaysArray.first,
              let spacesList = firstDisplay["Spaces"] as? [[String: Any]],
              let currentSpace = firstDisplay["Current Space"] as? [String: Any],
              let activeManagedID = (currentSpace["ManagedSpaceID"] as? NSNumber)?.uintValue
        else {
            return nil
        }

        return spacesList.enumerated().compactMap { index, entry in
            guard let managedID = (entry["ManagedSpaceID"] as? NSNumber)?.uintValue else { return nil }
            return SpaceReconciler.Observation(
                order: index,
                systemLabel: "Desktop \(index + 1)",
                isActive: managedID == activeManagedID,
                displayID: nil,
                systemToken: "\(managedID)"
            )
        }
    }

    private static func mainDisplayIdentifier() -> String? {
        guard PrivateSpacesAPI.isAvailable,
              let cid = PrivateSpacesAPI.connectionID(),
              let displaysArray = PrivateSpacesAPI.managedDisplaySpaces(cid: cid) as? [[String: Any]],
              let firstDisplay = displaysArray.first
        else {
            return nil
        }
        return firstDisplay["Display Identifier"] as? String
    }
}
