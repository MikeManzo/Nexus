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
import Observation
import SwiftUI

/// Owns the `NSStatusItem` and its click-to-open `NSPopover` (the full feature set: create,
/// manage, settings, quit). The glanceable hover-to-preview-and-switch experience lives
/// separately in `MenuBarLandingZoneController`, centered in the menu bar ; not here, and
/// deliberately not triggered from this status item: verified live that a hover trigger far from
/// where its content appears doesn't work as an interaction (the cursor has to cross real screen
/// distance with nothing under it). AppKit, not `MenuBarExtra` ; see
/// `docs/01-capability-research.md` §6: `MenuBarExtra`'s `.window` style still has gaps around
/// transient-popover dismissal and activation-policy control that a hosted `NSPopover` doesn't
/// have. The popover's *content* is plain SwiftUI.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let coordinator: AppCoordinator
    private var defaultsObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(coordinator: coordinator, dismiss: { [weak self] in
                self?.popover.performClose(nil)
            })
        )

        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        updateAppearance()
        observeActiveSpaceChanges()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateAppearance() }
        }

        Task {
            await coordinator.refresh()
            updateAppearance()
        }
    }

    /// Public entry point for `HotkeyCoordinator`'s "Open Nexus" action ; same behavior as
    /// clicking the status item.
    func togglePopoverFromHotkey() {
        togglePopover()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Deliberately does not call `coordinator.refresh()` here: against the real
            // (Accessibility-backed) SpaceManaging, that briefly presents Mission Control, and
            // doing that on every single popover open would be far more disruptive than the
            // Mission Control access Nexus exists to avoid. Shows cached state instantly instead
            // ; see `SystemSpaceObserver` for the tradeoff this implies.
            updateAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// `AppCoordinator` is `@Observable`, but this class isn't a SwiftUI view, so it doesn't get
    /// automatic re-renders ; without this, editing a desktop's name or accent color (via the
    /// popover's right-click "Rename & Color…") wouldn't reach the status item's own button until
    /// the *next* popover open/close cycle happened to call `updateAppearance()` again. This
    /// tracks `activeSpace` (name, order, and accent all live under it) via the Observation
    /// framework directly, and re-registers itself after every change since tracking is one-shot.
    private func observeActiveSpaceChanges() {
        withObservationTracking {
            _ = coordinator.activeSpace
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateAppearance()
                self?.observeActiveSpaceChanges()
            }
        }
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let mode = MenuBarDisplayMode(rawValue: UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? "") ?? .name
        switch mode {
        case .name:
            // A small dot in the active desktop's own accent color, plus its full name ; matches
            // the "current Space visible at a glance" pattern several menu-bar Spaces utilities
            // use, adapted to Nexus's own per-desktop accent colors rather than a fixed brand mark.
            if let active = coordinator.activeSpace {
                button.image = NSColor.dotImage(color: NSColor(hex: active.accentColorHex))
                button.imagePosition = .imageLeading
                button.title = active.displayName
            } else {
                button.image = nil
                button.title = "Nexus"
            }
        case .icon:
            let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Nexus")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        case .number:
            button.image = nil
            button.title = coordinator.activeSpace.map { "\($0.order + 1)" } ?? "–"
        case .letter:
            button.image = nil
            button.title = coordinator.activeSpace?.displayName.first.map(String.init) ?? "–"
        }

        // VoiceOver reads this regardless of display mode ; a bare "2" or "W" title on its own
        // isn't meaningful, so this always states the full current-desktop context explicitly.
        if let active = coordinator.activeSpace {
            button.setAccessibilityLabel("Nexus ; current desktop: \(active.displayName), \(active.order + 1) of \(coordinator.spaces.count)")
        } else {
            button.setAccessibilityLabel("Nexus")
        }
    }
}
