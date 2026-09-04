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
import SwiftUI

/// Owns the single floating panel centered in the menu bar — the "quick switcher" the user
/// hovers to preview and switch desktops. Opt-in (Settings → Menu Bar → "Show quick switcher in
/// menu bar"), off by default. There is exactly one window here: it grows in place on hover
/// (`LandingZoneView`) rather than triggering a separate panel elsewhere, so there is no gap
/// between where the cursor is and what it needs to reach — an earlier design (hover the status
/// item on the right, a preview appears centered on screen) didn't work as an interaction:
/// verified live that crossing real screen distance with nothing under the cursor breaks a hover
/// gesture, no matter how the dismiss-debounce is tuned.
@MainActor
final class MenuBarLandingZoneController {
    static let enabledDefaultsKey = "menuBarQuickSwitcherEnabled"

    private var panel: NSPanel?
    private var hostingController: NSHostingController<LandingZoneView>?
    private let coordinator: AppCoordinator
    private var lastSize = NSSize(width: 110, height: 50)
    private var missionControlObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var isEnabledByUser = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        observeMissionControl()
        observeEnabledSetting()
        applyEnabledState()
    }

    private func observeEnabledSetting() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyEnabledState() }
        }
    }

    private func applyEnabledState() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        guard enabled != isEnabledByUser else { return }
        isEnabledByUser = enabled
        if enabled {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let panel = currentPanel()
        position(panel, size: lastSize)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    /// Hides for the brief window Mission Control is presented, and restores right after — see
    /// `Notification.Name.missionControlWillPresent`'s doc comment for why this exists at all.
    private func observeMissionControl() {
        let willPresent = NotificationCenter.default.addObserver(
            forName: .missionControlWillPresent, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.orderOut(nil) }
        }
        let didDismiss = NotificationCenter.default.addObserver(
            forName: .missionControlDidDismiss, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabledByUser else { return }
                self.panel?.orderFrontRegardless()
            }
        }
        missionControlObservers = [willPresent, didDismiss]
    }

    private func currentPanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingController(
            rootView: LandingZoneView(coordinator: coordinator, onSizeChange: { [weak self] in
                self?.refreshSize()
            })
        )
        hostingController = hosting

        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    /// Called by `LandingZoneView` whenever it expands or collapses. SwiftUI's layout pass hasn't
    /// necessarily caught up on the same run loop tick, so this re-measures twice: once almost
    /// immediately, once again after the expand/collapse animation has had time to settle.
    private func refreshSize() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.applyRefinedSize()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.applyRefinedSize()
        }
    }

    private func applyRefinedSize() {
        guard let panel, let hostingController else { return }
        let size = hostingController.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        lastSize = size
        position(panel, size: size)
    }

    /// Pins the *top* edge to the very top of the screen — flush with the menu bar's own top
    /// edge, not sitting below it — and grows downward from there. The collapsed pill's height is
    /// exactly the menu bar's own thickness (`LandingZoneView.menuBarHeight`), so its content
    /// lands vertically centered against the native menu bar's own items rather than pinned to
    /// the top of the row; the expanded grid then hangs below it like a real dropdown would,
    /// starting right where the real menu bar ends.
    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.screens.first else { return }
        let x = horizontalOrigin(on: screen, panelWidth: size.width)
        let y = screen.frame.maxY - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// `screen.frame.midX` is the screen's true horizontal center — on a notched MacBook that's
    /// exactly where the camera housing is, so a panel centered there would sit partly behind it.
    /// `NSScreen.safeAreaInsets.top > 0` is how AppKit signals a notch is present; when it is,
    /// this centers instead within whichever of `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`
    /// (the unobscured strips macOS itself defines to the notch's left and right) is wide enough
    /// to hold the panel, clamped into that strip if the panel doesn't fit.
    ///
    /// Verified against the notch-free 2560×1440 external display this was built and tested on
    /// (`safeAreaInsets == .zero` there, so this always takes the plain-midpoint path); not yet
    /// tested on real notched hardware.
    private func horizontalOrigin(on screen: NSScreen, panelWidth: CGFloat) -> CGFloat {
        guard screen.safeAreaInsets.top > 0 else {
            return screen.frame.midX - panelWidth / 2
        }
        let sides = [screen.auxiliaryTopRightArea, screen.auxiliaryTopLeftArea].compactMap { $0 }.filter { !$0.isEmpty }
        guard let side = sides.first(where: { $0.width >= panelWidth }) ?? sides.max(by: { $0.width < $1.width }) else {
            return screen.frame.midX - panelWidth / 2
        }
        return panelWidth >= side.width ? side.minX : side.midX - panelWidth / 2
    }
}
