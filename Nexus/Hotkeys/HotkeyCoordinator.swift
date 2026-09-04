import Foundation
import Observation

/// Owns the current shortcut bindings, persists changes, and keeps `GlobalHotkeyManager`'s live
/// registrations in sync with them. Settings → Shortcuts reads/writes through this; nothing else
/// touches `GlobalHotkeyManager` directly.
@MainActor
@Observable
final class HotkeyCoordinator {
    private(set) var bindings: [HotkeyAction: HotkeyBinding]
    private var registeredIDs: [HotkeyAction: UInt32] = [:]

    private let store: HotkeyPreferencesStoring
    private let manager: GlobalHotkeyManager
    private let appCoordinator: AppCoordinator
    private let openNexus: () -> Void

    init(
        appCoordinator: AppCoordinator,
        openNexus: @escaping () -> Void,
        store: HotkeyPreferencesStoring = UserDefaultsHotkeyPreferencesStore(),
        manager: GlobalHotkeyManager = .shared
    ) {
        self.appCoordinator = appCoordinator
        self.openNexus = openNexus
        self.store = store
        self.manager = manager
        self.bindings = store.loadBindings()
        applyAll()
    }

    func setEnabled(_ enabled: Bool, for action: HotkeyAction) {
        bindings[action]?.isEnabled = enabled
        persistAndReapply()
    }

    /// Returns `false` (and makes no change) if `shortcut` is already bound to a different
    /// *enabled* action — callers should surface `conflictingAction(for:excluding:)` to the user
    /// rather than silently overwriting it.
    @discardableResult
    func setShortcut(_ shortcut: KeyboardShortcut, for action: HotkeyAction) -> Bool {
        guard conflictingAction(for: shortcut, excluding: action) == nil else { return false }
        bindings[action]?.shortcut = shortcut
        persistAndReapply()
        return true
    }

    func conflictingAction(for shortcut: KeyboardShortcut, excluding: HotkeyAction) -> HotkeyAction? {
        bindings.first { key, value in key != excluding && value.isEnabled && value.shortcut == shortcut }?.key
    }

    private func persistAndReapply() {
        store.saveBindings(bindings)
        applyAll()
    }

    private func applyAll() {
        for id in registeredIDs.values { manager.unregister(id) }
        registeredIDs.removeAll()

        for (action, binding) in bindings where binding.isEnabled {
            guard let id = manager.register(binding.shortcut, handler: { [weak self] in self?.perform(action) }) else {
                continue
            }
            registeredIDs[action] = id
        }
    }

    private func perform(_ action: HotkeyAction) {
        Log.hotkeys.info("Hotkey fired: \(action.rawValue, privacy: .public)")
        if let slot = action.desktopSlot {
            guard slot < appCoordinator.spaces.count else {
                Log.hotkeys.info("No desktop in slot \(slot + 1, privacy: .public)")
                return
            }
            let space = appCoordinator.spaces[slot]
            Task { await appCoordinator.activate(space) }
            return
        }
        switch action {
        case .openNexus: openNexus()
        case .createDesktop: Task { await appCoordinator.createSpace() }
        default: break
        }
    }
}
