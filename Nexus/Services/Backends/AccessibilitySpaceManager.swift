import AppKit
import ApplicationServices
import Foundation

/// Tier 2 `SpaceManaging`: drives Mission Control's accessibility tree. Built against the
/// verified structure captured by `MissionControlAccessibilityService`'s diagnostic dumps
/// (`~/Library/Application Support/Nexus/diagnostics/`), not guessed role/subrole names — see
/// `docs/01-capability-research.md` §2 for what's actually there:
///
/// - Dock.app exposes an `AXGroup` (`AXIdentifier == "mc.spaces.list"`) whose `AXChildren` are
///   one `AXButton` per desktop/full-screen space, in visual left-to-right order, and whose
///   `AXSelectedChildren` names the currently active one.
/// - Each of those buttons supports `AXPress` (switch to it, which also dismisses Mission
///   Control) and — unexpectedly, and better than the hover-then-click-a-close-button approach
///   most prior art uses — a direct `AXRemoveDesktop` action.
/// - A sibling `AXButton` (`AXIdentifier == "mc.spaces.add"`) creates a new desktop on `AXPress`.
///
/// Every operation here briefly presents Mission Control — that flash is expected, not a bug;
/// there is no way to read or change this state without it (§2, §11).
///
/// **Known untested gap:** `AXHelpers.findElement` returns the *first* match for
/// `mc.spaces.list`. On a single-display Mac (the only configuration this was built and verified
/// against) there's exactly one. Whether a multi-display setup with "Displays have separate
/// Spaces" enabled exposes a separate `Spaces Bar` group per display — which would mean this
/// silently only ever sees the first one — is unverified; `readObservations` logs a warning when
/// more than one display is attached so this doesn't fail invisibly. See
/// `docs/01-capability-research.md` §12.
@MainActor
final class AccessibilitySpaceManager: SpaceManaging {
    private var lastKnownSpaces: [DesktopSpace] = []

    func spaces() async throws -> [DesktopSpace] {
        try await withMissionControlPresented { axApp in
            try self.readObservations(from: axApp)
        }
    }

    func activeSpace() async throws -> DesktopSpace? {
        try await spaces().first { $0.isActive }
    }

    func activate(_ space: DesktopSpace) async throws {
        guard AXIsProcessTrusted() else { throw SpaceError.accessibilityPermissionDenied }

        // Opportunistic fast path: if the user has assigned macOS's own "Switch to Desktop N"
        // shortcut for this slot, triggering it is a genuine system-level switch with no UI
        // presented at all — strictly better than driving Mission Control. See
        // `SymbolicHotkeyLookup`. Most desktops won't have one configured (unassigned by
        // default), so this silently falls through to the Mission Control path below.
        if let binding = SymbolicHotkeyLookup.desktopSwitchBinding(forSlot: space.order) {
            AXHelpers.postKeystroke(keyCode: binding.keyCode, flags: binding.flags)
            Log.spaceManager.info("Silent switch via system shortcut for slot \(space.order + 1, privacy: .public)")
            try? await Task.sleep(for: .milliseconds(200))
            return
        }

        // Pressing a desktop's button both switches to it and dismisses Mission Control itself
        // (its own AXDescription is "exit to Desktop N") — no separate dismiss step needed.
        try await withMissionControlPresented(dismissAfter: false) { axApp in
            guard let spacesList = AXHelpers.findElement(axApp, matchingIdentifier: "mc.spaces.list") else {
                throw SpaceError.missionControlUnavailable
            }
            let buttons = self.children(of: spacesList)
            guard space.order < buttons.count else { throw SpaceError.spaceChangedDuringOperation }
            guard AXUIElementPerformAction(buttons[space.order], kAXPressAction as CFString) == .success else {
                throw SpaceError.missionControlUnavailable
            }
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    func createSpace() async throws -> DesktopSpace {
        let before = try await spaces()

        let after: [DesktopSpace] = try await withMissionControlPresented { axApp in
            guard let addButton = AXHelpers.findElement(axApp, matchingIdentifier: "mc.spaces.add") else {
                throw SpaceError.missionControlUnavailable
            }
            guard AXUIElementPerformAction(addButton, kAXPressAction as CFString) == .success else {
                throw SpaceError.missionControlUnavailable
            }
            try await Task.sleep(for: .milliseconds(400))
            return try self.readObservations(from: axApp)
        }

        if let created = after.first(where: { candidate in !before.contains { $0.identifier == candidate.identifier } }) {
            return created
        }
        guard let last = after.last else { throw SpaceError.missionControlUnavailable }
        return last
    }

    func delete(_ space: DesktopSpace) async throws {
        try await withMissionControlPresented { axApp in
            guard let spacesList = AXHelpers.findElement(axApp, matchingIdentifier: "mc.spaces.list") else {
                throw SpaceError.missionControlUnavailable
            }
            let buttons = self.children(of: spacesList)
            guard buttons.count > 1 else { throw SpaceError.cannotDeleteLastSpace }
            guard space.order < buttons.count else { throw SpaceError.spaceChangedDuringOperation }
            // No standard kAX constant for this — it only showed up as an available action name
            // in the diagnostic dump, specific to Dock.app's Spaces Bar buttons.
            guard AXUIElementPerformAction(buttons[space.order], "AXRemoveDesktop" as CFString) == .success else {
                throw SpaceError.missionControlUnavailable
            }
        }
        lastKnownSpaces.removeAll { $0.identifier == space.identifier }
    }

    // MARK: - Shared plumbing

    private func withMissionControlPresented<T: Sendable>(
        dismissAfter: Bool = true,
        _ body: (AXUIElement) async throws -> T
    ) async throws -> T {
        guard AXIsProcessTrusted() else { throw SpaceError.accessibilityPermissionDenied }
        guard let axApp = AXHelpers.dockAXApplication() else { throw SpaceError.missionControlUnavailable }
        guard let missionControlURL = AXHelpers.missionControlAppURL() else { throw SpaceError.unsupportedOnThisSystem }

        do {
            try await NSWorkspace.shared.openApplication(at: missionControlURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw SpaceError.missionControlUnavailable
        }
        try await Task.sleep(for: .milliseconds(700))

        let result: T
        do {
            result = try await body(axApp)
        } catch {
            // Always clean up on failure, even when the caller asked to skip the success-path
            // dismiss (e.g. `activate`, which normally dismisses itself by switching).
            AXHelpers.dismissMissionControl()
            throw error
        }

        if dismissAfter {
            AXHelpers.dismissMissionControl()
            try? await Task.sleep(for: .milliseconds(250))
        }
        return result
    }

    private func readObservations(from axApp: AXUIElement) throws -> [DesktopSpace] {
        if NSScreen.screens.count > 1 {
            Log.spaceManager.notice("Multiple displays attached; only the first Spaces Bar found is read — untested configuration, see AccessibilitySpaceManager's doc comment")
        }

        guard let spacesList = AXHelpers.findElement(axApp, matchingIdentifier: "mc.spaces.list") else {
            throw SpaceError.missionControlUnavailable
        }
        let buttons = children(of: spacesList)
        let selected = (AXHelpers.copyAttribute(spacesList, kAXSelectedChildrenAttribute as CFString) as? [AXUIElement]) ?? []

        let observations: [SpaceReconciler.Observation] = buttons.enumerated().map { index, button in
            let description = (AXHelpers.copyAttribute(button, kAXDescriptionAttribute as CFString) as? String) ?? ""
            let label = Self.parseLabel(fromExitDescription: description, fallbackOrder: index)
            let isActive = selected.contains { CFEqual($0, button) }
            return SpaceReconciler.Observation(order: index, systemLabel: label, isActive: isActive, displayID: nil)
        }

        let reconciled = SpaceReconciler.reconcile(previous: lastKnownSpaces, observed: observations)
        lastKnownSpaces = reconciled
        Log.spaceManager.info("Observed \(reconciled.count, privacy: .public) spaces via Accessibility")
        return reconciled
    }

    private func children(of list: AXUIElement) -> [AXUIElement] {
        (AXHelpers.copyAttribute(list, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []
    }

    /// Observed forms in the diagnostic dump: `"exit to Desktop 3"` and
    /// `"exit to full screen Windows App"` (a full-screen app counts as its own space).
    private static func parseLabel(fromExitDescription description: String, fallbackOrder: Int) -> String {
        let prefix = "exit to "
        guard description.hasPrefix(prefix) else { return "Desktop \(fallbackOrder + 1)" }
        var remainder = String(description.dropFirst(prefix.count))
        let fullScreenPrefix = "full screen "
        if remainder.hasPrefix(fullScreenPrefix) {
            remainder = String(remainder.dropFirst(fullScreenPrefix.count))
        }
        return remainder.isEmpty ? "Desktop \(fallbackOrder + 1)" : remainder
    }
}
