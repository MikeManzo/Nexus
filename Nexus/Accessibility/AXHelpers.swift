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
    /// Mission Control elements carry stable identifiers (`mc.spaces.list`, `mc.spaces.add`) —
    /// verified via the Phase 4 diagnostic dump — so matching by identifier is used wherever
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

    /// `/System/Applications/Mission Control.app` — launching it by bundle id (rather than
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
    /// shortcut for a silent switch — see `SymbolicHotkeyLookup`.
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
