//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
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
    /// True while `activate`/`createSpace`/`delete` are in flight ; these can take a second or
    /// two against the real backend (Mission Control's animation, or a synthesized keystroke's
    /// settle time), so views use this to show that a click registered rather than looking inert.
    private(set) var isBusy = false

    let spaceManager: SpaceManaging
    let updateManager: UpdateManaging
    let updatePreferences: UpdatePreferences
    let accessibilityPermission: AccessibilityPermissionManager
    let missionControlDiagnostics: MissionControlAccessibilityService
    let screenRecordingPermission: ScreenRecordingPermissionManager
    let thumbnailCache: DesktopThumbnailCache
    /// Set by `AppDelegate` once the status item exists ; `HotkeyCoordinator` needs an
    /// `openNexus` closure that isn't available until then, so it can't be built in `init`.
    var hotkeyCoordinator: HotkeyCoordinator?
    private let metadataStore: SpaceMetadataStoring

    init(
        spaceManager: SpaceManaging,
        updateManager: UpdateManaging,
        metadataStore: SpaceMetadataStoring,
        accessibilityPermission: AccessibilityPermissionManager,
        missionControlDiagnostics: MissionControlAccessibilityService,
        screenRecordingPermission: ScreenRecordingPermissionManager = ScreenRecordingPermissionManager(),
        thumbnailCache: DesktopThumbnailCache = DesktopThumbnailCache()
    ) {
        self.spaceManager = spaceManager
        self.updateManager = updateManager
        self.updatePreferences = UpdatePreferences(updateManager: updateManager)
        self.metadataStore = metadataStore
        self.accessibilityPermission = accessibilityPermission
        self.missionControlDiagnostics = missionControlDiagnostics
        self.screenRecordingPermission = screenRecordingPermission
        self.thumbnailCache = thumbnailCache
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
                fetched[index].launchAppBundleIDs = entry.launchAppBundleIDs
                fetched[index].hotkeyShortcut = entry.shortcut
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
    // manager, `refresh()` briefly presents Mission Control ; so calling it after an action whose
    // own backend call already did that (or, for `rename`, never needed to at all) meant every
    // click flashed Mission Control twice. `activate`/`createSpace` are exactly correct this way;
    // `delete` renumbers remaining spaces' `order` locally but their system-derived `systemLabel`
    // can go briefly stale until the next real read (§ cached-first tradeoff also used for popover
    // opens ; see `StatusItemController`/`SystemSpaceObserver`).

    func activate(_ space: DesktopSpace) async {
        isBusy = true
        defer { isBusy = false }

        // "Last seen" thumbnails, not live ones ; capture the desktop being left right before we
        // switch away from it (its content won't change again until it's revisited), and the
        // destination again once we've arrived. See `DesktopThumbnailCache`'s doc comment for why
        // this is the best that's possible at all. Both are no-ops when the user hasn't opted in
        // or hasn't granted Screen Recording access.
        let previewsEnabled = UserDefaults.standard.bool(forKey: DesktopThumbnailCache.enabledDefaultsKey)
        if !previewsEnabled {
            Log.thumbnails.notice("Desktop previews toggle is off; skipping captures for this switch")
        }
        if previewsEnabled, let leaving = activeSpace, leaving.identifier != space.identifier {
            await thumbnailCache.captureCurrentScreen(for: leaving)
        }

        do {
            try await spaceManager.activate(space)
            for index in spaces.indices {
                spaces[index].isActive = (spaces[index].identifier == space.identifier)
            }
            activeSpaceID = space.identifier
            if previewsEnabled {
                await thumbnailCache.captureCurrentScreen(for: space)
            }
            launchConfiguredApps(for: space)
        } catch {
            record(error)
        }
    }

    /// Fires and forgets — this is a convenience, never something a switch should be seen to wait
    /// on or fail over. Only launches an app that isn't already running: the goal is "have my
    /// tools ready," not repeatedly stealing focus or relaunching something you deliberately quit.
    private func launchConfiguredApps(for space: DesktopSpace) {
        guard let bundleIDs = space.launchAppBundleIDs, !bundleIDs.isEmpty else { return }
        for bundleID in bundleIDs {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { continue }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                Log.spaceManager.notice("Launch-on-arrival: no installed app found for \(bundleID, privacy: .public)")
                continue
            }
            Task {
                do {
                    try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                } catch {
                    Log.spaceManager.notice("Launch-on-arrival failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
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
            // ; otherwise every new desktop would silently fall back to flashing until the user
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

    func setSymbol(_ symbolName: String?, for space: DesktopSpace) async {
        await metadataStore.setSymbolName(symbolName, for: space.identifier.stableKey)
        if let index = spaces.firstIndex(where: { $0.identifier == space.identifier }) {
            spaces[index].symbolName = symbolName
        }
    }

    func setLaunchAppBundleIDs(_ bundleIDs: [String], for space: DesktopSpace) async {
        await metadataStore.setLaunchAppBundleIDs(bundleIDs, for: space.identifier.stableKey)
        if let index = spaces.firstIndex(where: { $0.identifier == space.identifier }) {
            spaces[index].launchAppBundleIDs = bundleIDs.isEmpty ? nil : bundleIDs
        }
    }

    /// Nil clears the binding. Callers (`ShortcutsSettingsView`) are responsible for conflict
    /// checking against both this and the fixed-slot bindings before calling this — see
    /// `HotkeyCoordinator.conflictingBinding(for:excludingSpace:)`.
    func setShortcut(_ shortcut: KeyboardShortcut?, for space: DesktopSpace) async {
        await metadataStore.setShortcut(shortcut, for: space.identifier.stableKey)
        if let index = spaces.firstIndex(where: { $0.identifier == space.identifier }) {
            spaces[index].hotkeyShortcut = shortcut
        }
    }

    private func record(_ error: Error) {
        let spaceError = error as? SpaceError ?? .underlying(error.localizedDescription)
        lastError = spaceError
        Log.spaceManager.error("Operation failed: \(spaceError.errorDescription ?? "unknown", privacy: .public)")
    }
}
