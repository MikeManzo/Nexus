import Foundation
import Observation

/// Owns the current, reconciled view of the user's desktops and mediates every UI action against
/// `SpaceManaging` (system operations) and `SpaceMetadataStoring` (Nexus-owned naming). Views read
/// `spaces`/`activeSpace`/`lastError` and call the action methods; they never touch a backend
/// directly.
@MainActor
@Observable
final class AppCoordinator {
    private(set) var spaces: [DesktopSpace] = []
    private(set) var activeSpaceID: SpaceIdentifier?
    var lastError: SpaceError?
    /// True while `activate`/`createSpace`/`delete` are in flight — these can take a second or
    /// two against the real backend (Mission Control's animation, or a synthesized keystroke's
    /// settle time), so views use this to show that a click registered rather than looking inert.
    private(set) var isBusy = false

    let spaceManager: SpaceManaging
    let updateManager: UpdateManaging
    let updatePreferences: UpdatePreferences
    let accessibilityPermission: AccessibilityPermissionManager
    let missionControlDiagnostics: MissionControlAccessibilityService
    /// Set by `AppDelegate` once the status item exists — `HotkeyCoordinator` needs an
    /// `openNexus` closure that isn't available until then, so it can't be built in `init`.
    var hotkeyCoordinator: HotkeyCoordinator?
    private let metadataStore: SpaceMetadataStoring

    init(
        spaceManager: SpaceManaging,
        updateManager: UpdateManaging,
        metadataStore: SpaceMetadataStoring,
        accessibilityPermission: AccessibilityPermissionManager,
        missionControlDiagnostics: MissionControlAccessibilityService
    ) {
        self.spaceManager = spaceManager
        self.updateManager = updateManager
        self.updatePreferences = UpdatePreferences(updateManager: updateManager)
        self.metadataStore = metadataStore
        self.accessibilityPermission = accessibilityPermission
        self.missionControlDiagnostics = missionControlDiagnostics
    }

    var activeSpace: DesktopSpace? {
        spaces.first { $0.id == activeSpaceID }
    }

    func refresh() async {
        do {
            var fetched = try await spaceManager.spaces()
            let metadata = await metadataStore.allMetadata()
            for index in fetched.indices {
                guard let entry = metadata[fetched[index].identifier.stableKey] else { continue }
                fetched[index].customName = entry.customName
                fetched[index].symbolName = entry.symbolName
                fetched[index].accentColorHex = entry.accentColorHex
            }
            spaces = fetched.sorted { $0.order < $1.order }
            // Derived from the same fetch rather than a separate `activeSpace()` call: the real
            // (Accessibility-backed) implementation briefly presents Mission Control per call, so
            // a second round-trip here would flash it twice for one logical refresh.
            activeSpaceID = fetched.first(where: \.isActive)?.identifier
        } catch {
            record(error)
        }
    }

    // Every action below updates local state directly from what the backend call already told
    // us, instead of following up with `refresh()`. Against the real (Accessibility-backed)
    // manager, `refresh()` briefly presents Mission Control — so calling it after an action whose
    // own backend call already did that (or, for `rename`, never needed to at all) meant every
    // click flashed Mission Control twice. `activate`/`createSpace` are exactly correct this way;
    // `delete` renumbers remaining spaces' `order` locally but their system-derived `systemLabel`
    // can go briefly stale until the next real read (§ cached-first tradeoff also used for popover
    // opens — see `StatusItemController`/`SystemSpaceObserver`).

    func activate(_ space: DesktopSpace) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await spaceManager.activate(space)
            for index in spaces.indices {
                spaces[index].isActive = (spaces[index].identifier == space.identifier)
            }
            activeSpaceID = space.identifier
        } catch {
            record(error)
        }
    }

    func createSpace() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let created = try await spaceManager.createSpace()
            spaces.append(created)
            spaces.sort { $0.order < $1.order }

            // If the user has already opted into flash-free switching (Settings → Shortcuts →
            // "Enable for All Desktops"), extend it to newly created desktops automatically too
            // — otherwise every new desktop would silently fall back to flashing until the user
            // remembered to revisit Settings and click the button again.
            if SystemShortcutConfigurator.isEnabled {
                _ = try? SystemShortcutConfigurator.ensureShortcut(forSlot: created.order)
            }
        } catch {
            record(error)
        }
    }

    func delete(_ space: DesktopSpace) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await spaceManager.delete(space)
            await metadataStore.removeMetadata(for: space.identifier.stableKey)
            spaces.removeAll { $0.identifier == space.identifier }
            for index in spaces.indices { spaces[index].order = index }
            if activeSpaceID == space.identifier {
                activeSpaceID = spaces.first?.identifier
            }
        } catch {
            record(error)
        }
    }

    func rename(_ space: DesktopSpace, to name: String) async {
        await metadataStore.setCustomName(name, for: space.identifier.stableKey)
        if let index = spaces.firstIndex(where: { $0.identifier == space.identifier }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            spaces[index].customName = trimmed.isEmpty ? nil : trimmed
        }
    }

    func setAccentColor(_ hex: String?, for space: DesktopSpace) async {
        await metadataStore.setAccentColor(hex, for: space.identifier.stableKey)
        if let index = spaces.firstIndex(where: { $0.identifier == space.identifier }) {
            spaces[index].accentColorHex = hex
        }
    }

    private func record(_ error: Error) {
        let spaceError = error as? SpaceError ?? .underlying(error.localizedDescription)
        lastError = spaceError
        Log.spaceManager.error("Operation failed: \(spaceError.errorDescription ?? "unknown", privacy: .public)")
    }
}
