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
import Observation

/// Owns the current shortcut bindings, persists changes, and keeps `GlobalHotkeyManager`'s live
/// registrations in sync with them. Settings → Shortcuts reads/writes through this; nothing else
/// touches `GlobalHotkeyManager` directly.
@MainActor
@Observable
final class HotkeyCoordinator {
    private(set) var bindings: [HotkeyAction: HotkeyBinding]
    private var registeredIDs: [HotkeyAction: UInt32] = [:]
    /// Per-desktop shortcuts (`DesktopSpace.hotkeyShortcut`), keyed by `stableKey` rather than a
    /// fixed `HotkeyAction` case — these bind to a specific desktop's *identity*, independent of
    /// its numbered slot, so reordering or renaming doesn't disconnect them. Kept as a second,
    /// parallel registration table rather than folding into `bindings`/`HotkeyAction` since that
    /// enum is a fixed, `CaseIterable` set by design (see its own doc comment) ; desktops are not.
    private var spaceRegisteredIDs: [UUID: (id: UInt32, shortcut: KeyboardShortcut)] = [:]

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
        applySpaceShortcuts()
        observeSpaceChanges()
    }

    func setEnabled(_ enabled: Bool, for action: HotkeyAction) {
        bindings[action]?.isEnabled = enabled
        persistAndReapply()
    }

    /// Returns `false` (and makes no change) if `shortcut` is already bound to a different
    /// *enabled* action ; callers should surface `conflictingAction(for:excluding:)` to the user
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

    /// Checked before assigning a desktop-specific shortcut (`SpaceManagerView`'s customize
    /// sheet) — a human-readable description of whatever already uses `shortcut`, across *both*
    /// registration tables (a numbered-slot action, or another desktop), or `nil` if it's free.
    func conflictDescription(for shortcut: KeyboardShortcut, excludingSpace: DesktopSpace) -> String? {
        if let action = bindings.first(where: { $0.value.isEnabled && $0.value.shortcut == shortcut })?.key {
            return action.label
        }
        if let other = appCoordinator.spaces.first(where: {
            $0.identifier != excludingSpace.identifier && $0.hotkeyShortcut == shortcut
        }) {
            return other.displayName
        }
        return nil
    }

    /// `AppCoordinator` is `@Observable`, but this class isn't a SwiftUI view, so it doesn't get
    /// automatic re-renders — without this, a shortcut just assigned in `SpaceManagerView` (or a
    /// desktop that's renamed, deleted, or newly created) wouldn't reach `GlobalHotkeyManager`
    /// until something else happened to call `applySpaceShortcuts()` again. Re-registers itself
    /// after every change since tracking is one-shot, same pattern as
    /// `StatusItemController.observeActiveSpaceChanges`.
    private func observeSpaceChanges() {
        withObservationTracking {
            _ = appCoordinator.spaces
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySpaceShortcuts()
                self?.observeSpaceChanges()
            }
        }
    }

    /// Registers exactly the desktops that currently have a `hotkeyShortcut` set, unregistering
    /// anything stale first (a shortcut that changed, was cleared, or whose desktop no longer
    /// exists). The handler looks the space up again by `stableKey` at fire time rather than
    /// capturing it now, so it always switches to wherever that desktop currently is — the whole
    /// point of binding by identity instead of by slot.
    private func applySpaceShortcuts() {
        let current = Dictionary(uniqueKeysWithValues: appCoordinator.spaces.compactMap { space in
            space.hotkeyShortcut.map { (space.identifier.stableKey, $0) }
        })

        for (key, registration) in spaceRegisteredIDs where current[key] != registration.shortcut {
            manager.unregister(registration.id)
            spaceRegisteredIDs.removeValue(forKey: key)
        }

        for (key, shortcut) in current where spaceRegisteredIDs[key] == nil {
            guard let id = manager.register(shortcut, handler: { [weak self] in self?.performSpaceSwitch(stableKey: key) }) else {
                continue
            }
            spaceRegisteredIDs[key] = (id, shortcut)
        }
    }

    private func performSpaceSwitch(stableKey: UUID) {
        guard let space = appCoordinator.spaces.first(where: { $0.identifier.stableKey == stableKey }) else {
            Log.hotkeys.info("Desktop shortcut fired for a desktop that no longer exists")
            return
        }
        Log.hotkeys.info("Desktop shortcut fired: \(space.displayName, privacy: .public)")
        Task { await appCoordinator.activate(space) }
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
