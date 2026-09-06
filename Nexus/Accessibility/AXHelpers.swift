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
import ApplicationServices

/// Small shared primitives used by both the Phase 4 diagnostic tooling
/// (`MissionControlAccessibilityService`) and the production `AccessibilitySpaceManager`.
enum AXHelpers {
    static func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }

    /// Depth-first search for a descendant whose `AXIdentifier` equals `target`. Dock.app's
    /// Mission Control elements carry stable identifiers (`mc.spaces.list`, `mc.spaces.add`) ;
    /// verified via the Phase 4 diagnostic dump ; so matching by identifier is used wherever
    /// possible instead of guessing at tree position.
    static func findElement(_ root: AXUIElement, matchingIdentifier target: String, depth: Int = 0, maxDepth: Int = 12) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }
        if let id = copyAttribute(root, kAXIdentifierAttribute as CFString) as? String, id == target {
            return root
        }
        guard let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findElement(child, matchingIdentifier: target, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    static func dockAXApplication() -> AXUIElement? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        return AXUIElementCreateApplication(dockApp.processIdentifier)
    }

    /// Processes observed to host Mission Control's real Spaces Bar (`mc.spaces.list`), checked
    /// in this order every poll. `com.apple.dock` is the original, documented location this app
    /// was built against ; but a real diagnostic dump from a Mac running a newer macOS build
    /// showed Dock's own `mc` group as a permanently empty placeholder there, with the actual
    /// Spaces Bar living entirely under the separate `com.apple.WindowManager` process instead.
    private static let missionControlSpacesHostBundleIdentifiers = ["com.apple.dock", "com.apple.WindowManager"]

    /// Polls across every candidate host process for `mc.spaces.list` to appear, rather than
    /// assuming a single fixed process (`com.apple.dock`) is always the right one to ask, or that
    /// a single fixed delay is always enough to wait. Checking both live, on every poll tick,
    /// means whichever one actually has it is picked up promptly regardless of which Mac this
    /// runs on ; see `missionControlSpacesHostBundleIdentifiers`'s doc comment for why there's
    /// more than one candidate at all.
    @MainActor
    static func resolveMissionControlSpacesHost(
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(150)
    ) async -> AXUIElement? {
        let deadline = ContinuousClock.now + timeout
        while true {
            for bundleID in missionControlSpacesHostBundleIdentifiers {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    let axApp = AXUIElementCreateApplication(app.processIdentifier)
                    if findElement(axApp, matchingIdentifier: "mc.spaces.list") != nil {
                        return axApp
                    }
                }
            }
            if ContinuousClock.now >= deadline { return nil }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// `/System/Applications/Mission Control.app` ; launching it by bundle id (rather than
    /// synthesizing the Mission Control keyboard shortcut) works regardless of whether the user
    /// has rebound or disabled that shortcut.
    static func missionControlAppURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher")
    }

    /// Escape reliably dismisses a presented Mission Control. Posting a synthetic key event this
    /// way requires the same Accessibility trust already gated on by callers.
    static func dismissMissionControl() {
        postKeystroke(keyCode: 53, flags: [])
    }

    /// Posts a synthetic key-down/key-up pair. Used both to dismiss Mission Control and, in
    /// `AccessibilitySpaceManager`, to trigger a user-assigned "Switch to Desktop N" system
    /// shortcut for a silent switch ; see `SymbolicHotkeyLookup`.
    static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
