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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let experimentalBackendKey = "experimentalBackendEnabled"

    let coordinator = AppCoordinator(
        spaceManager: AppDelegate.makeSpaceManager(),
        updateManager: SparkleUpdateManager(),
        metadataStore: SpaceMetadataStore(),
        accessibilityPermission: AccessibilityPermissionManager(),
        missionControlDiagnostics: MissionControlAccessibilityService()
    )

    private var statusItemController: StatusItemController?
    private var landingZoneController: MenuBarLandingZoneController?
    private var spaceObserver: SystemSpaceObserver?
    private var onboardingWindowController: OnboardingWindowController?

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// Chosen once, at launch — swapping backends live isn't worth the added risk for a toggle
    /// this rarely flipped, so Settings → Experimental asks for a restart instead.
    private static func makeSpaceManager() -> SpaceManaging {
        if UserDefaults.standard.bool(forKey: experimentalBackendKey) {
            Log.spaceManager.info("Using Tier 3 experimental backend (private Spaces API)")
            return ExperimentalSpaceManager()
        }
        return AccessibilitySpaceManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // With no `WindowGroup` in `NexusApp`'s scene body (deliberate — a menu-bar-only app has
        // no document-style main window), SwiftUI's App lifecycle auto-opens the `Settings` scene
        // at launch instead, since it needs *something* to show — confirmed live, and neither
        // `NSQuitAlwaysKeepsWindows` nor `applicationSupportsSecureRestorableState` on their own
        // stopped it (there was no saved-state bundle involved at all). Closing whatever SwiftUI
        // opened before Nexus's own UI exists is the reliable fix: at this exact point nothing
        // legitimate has been created yet, so any window here is that unwanted auto-open.
        for window in NSApp.windows {
            window.close()
        }

        let statusItem = StatusItemController(coordinator: coordinator)
        statusItemController = statusItem
        // Manages its own visibility from Settings → Menu Bar → "Show quick switcher in menu
        // bar" (off by default) — nothing to call here.
        landingZoneController = MenuBarLandingZoneController(coordinator: coordinator)
        spaceObserver = SystemSpaceObserver()
        coordinator.hotkeyCoordinator = HotkeyCoordinator(
            appCoordinator: coordinator,
            openNexus: { [weak statusItem] in statusItem?.togglePopoverFromHotkey() }
        )
        Log.app.info("Nexus launched")

        if !UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey) {
            presentOnboarding()
        }
    }

    /// Also reachable from Settings → General's "Show Welcome Screen…" button.
    func presentOnboarding() {
        let controller = OnboardingWindowController(coordinator: coordinator) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
        }
        onboardingWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    // Without this, SwiftUI quits the whole app when its last open window (Settings, or Manage
    // Desktops) closes — the right default for a document-style app, but wrong here: the menu bar
    // status item is Nexus's real lifetime anchor, not any window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // The actual (macOS 14+) control point for window-restoration ("Resume") — the
    // `NSQuitAlwaysKeepsWindows` Info.plist key alone wasn't enough to stop Settings or Manage
    // Desktops from reopening automatically on launch, confirmed live. Returning `false` opts
    // Nexus out of state restoration entirely, which is correct for a menu-bar-only utility: its
    // windows are always opened deliberately from the popover, never something to resume into.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
