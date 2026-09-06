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

/// Windows Nexus opens on purpose, ever — anything else appearing during the launch grace window
/// is the unwanted auto-opened Settings scene. Checking by content-view-controller type doesn't
/// work here: confirmed live that the actual class is a private SwiftUI wrapper
/// (`AppKitWindowHostingController<ModifiedContent<AnyView, RootModifier>>`), not
/// `NSHostingController<SettingsView>`, and the window's *title* isn't reliably "Settings" either
/// — a `TabView`-based Settings window takes its title from whichever tab is selected (it showed
/// up titled "Menu Bar" once, matching `MenuBarSettingsView`'s tab). An allowlist of titles Nexus
/// itself controls sidesteps both problems.
private let expectedLaunchWindowTitles: Set<String> = ["Welcome to Nexus", "Manage Desktops"]

/// `NSWindow.title` is itself MainActor-isolated, so this has to be too — kept as a free function
/// (rather than nested inside `AppDelegate`) purely so it reads clearly at both its call sites in
/// `suppressSettingsAutoOpenAtLaunch`, one of which is inside a `MainActor.assumeIsolated` block
/// rather than directly in `@MainActor` context.
@MainActor
private func isUnexpectedLaunchWindow(_ window: NSWindow?) -> Bool {
    guard let window else { return false }
    return !expectedLaunchWindowTitles.contains(window.title)
}

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

    /// Chosen once, at launch ; swapping backends live isn't worth the added risk for a toggle
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
        suppressSettingsAutoOpenAtLaunch()

        let statusItem = StatusItemController(coordinator: coordinator)
        statusItemController = statusItem
        // Manages its own visibility from Settings → Menu Bar → "Show quick switcher in menu
        // bar" (off by default) ; nothing to call here.
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

    /// With no `WindowGroup` in `NexusApp`'s scene body (deliberate ; a menu-bar-only app has no
    /// document-style main window), SwiftUI's App lifecycle auto-opens the `Settings` scene at
    /// launch instead, since it needs *something* to show. A single synchronous close-pass over
    /// `NSApp.windows` at the top of `applicationDidFinishLaunching` (the original fix) caught
    /// this reliably on one Mac but not another — confirmed live that the timing of exactly when
    /// SwiftUI shows it isn't consistent enough to rely on a single check. This instead closes it
    /// immediately if it already exists, and also watches for it becoming key over the next 1.5s
    /// in case SwiftUI shows it on a later run loop tick — via `isUnexpectedLaunchWindow`'s
    /// allowlist, since neither the window's title nor its content-view-controller type reliably
    /// identify it as "the Settings window" (see that function's doc comment). Stops watching
    /// after that window so a user later choosing Settings from the popover, or opening Manage
    /// Desktops, works normally.
    private func suppressSettingsAutoOpenAtLaunch() {
        for window in NSApp.windows where isUnexpectedLaunchWindow(window) {
            window.close()
        }

        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            // `queue: .main` guarantees this closure only ever runs on the main thread, but its
            // `@Sendable` type doesn't let the compiler prove that statically — `assumeIsolated`
            // is the documented escape hatch for exactly this Foundation/AppKit-era API shape.
            MainActor.assumeIsolated {
                guard isUnexpectedLaunchWindow(window) else { return }
                window?.close()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let observer { NotificationCenter.default.removeObserver(observer) }
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
    // Desktops) closes ; the right default for a document-style app, but wrong here: the menu bar
    // status item is Nexus's real lifetime anchor, not any window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // The actual (macOS 14+) control point for window-restoration ("Resume") ; the
    // `NSQuitAlwaysKeepsWindows` Info.plist key alone wasn't enough to stop Settings or Manage
    // Desktops from reopening automatically on launch, confirmed live. Returning `false` opts
    // Nexus out of state restoration entirely, which is correct for a menu-bar-only utility: its
    // windows are always opened deliberately from the popover, never something to resume into.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
