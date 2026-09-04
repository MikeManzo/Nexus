import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Tier 2 groundwork. This is **not yet** a `SpaceManaging` conformer — Apple documents nothing
/// about Mission Control's accessibility tree, so before writing real enumeration/switch logic
/// against guessed role and subrole names, this dumps the *actual* tree to a file for inspection.
/// The real `AccessibilitySpaceManager` gets built against verified structure, once captured.
///
/// Invocation uses `NSWorkspace` to launch `/System/Applications/Mission Control.app`
/// (bundle id `com.apple.exposelauncher`) rather than synthesizing the Mission Control keyboard
/// shortcut — a synthesized keystroke would silently do nothing if the user has rebound or
/// disabled that shortcut in System Settings; launching the app by bundle id does not depend on
/// what shortcut, if any, is configured.
@MainActor
final class MissionControlAccessibilityService {
    struct DumpResult {
        let fileURL: URL
        let elementCountAtRest: Int
        let elementCountWhilePresented: Int
    }

    enum ServiceError: Error, LocalizedError {
        case notTrusted
        case dockProcessNotFound
        case missionControlAppNotFound

        var errorDescription: String? {
            switch self {
            case .notTrusted: "Accessibility permission has not been granted."
            case .dockProcessNotFound: "Could not find the Dock process."
            case .missionControlAppNotFound: "Could not locate Mission Control.app via Launch Services."
            }
        }
    }

    /// Harmless, read-only: confirms Nexus can read Dock.app's accessibility tree at all. Does
    /// not invoke Mission Control and has no visible side effects — safe to run as a routine
    /// "Test Accessibility Connection" check, unlike the diagnostic dump below.
    func testConnection() throws -> Bool {
        guard AXIsProcessTrusted() else { throw ServiceError.notTrusted }
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw ServiceError.dockProcessNotFound
        }
        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)
        let role = copyAttribute(axApp, kAXRoleAttribute as CFString) as? String
        return role == (kAXApplicationRole as String)
    }

    /// Dumps Dock.app's accessibility tree both before and while Mission Control is presented, to
    /// a timestamped file under `~/Library/Application Support/Nexus/diagnostics/`. Intentionally
    /// visible and disruptive — a one-shot developer diagnostic triggered from Settings →
    /// Accessibility, not something end users run routinely.
    func dumpDockAccessibilityTree() async throws -> DumpResult {
        guard AXIsProcessTrusted() else { throw ServiceError.notTrusted }

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw ServiceError.dockProcessNotFound
        }
        guard let missionControlURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") else {
            throw ServiceError.missionControlAppNotFound
        }

        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)

        var restCount = 0
        let restDump = describeElement(axApp, depth: 0, maxDepth: 6, count: &restCount)

        Log.accessibility.info("Diagnostic: invoking Mission Control via com.apple.exposelauncher")
        try await NSWorkspace.shared.openApplication(at: missionControlURL, configuration: NSWorkspace.OpenConfiguration())
        try await Task.sleep(for: .milliseconds(700))

        var presentedCount = 0
        let presentedDump = describeElement(axApp, depth: 0, maxDepth: 8, count: &presentedCount)

        dismissMissionControl()

        let output = """
        Nexus Mission Control accessibility diagnostic
        Captured: \(Date().formatted(.iso8601))

        === Dock.app AX tree AT REST (Mission Control not invoked) — \(restCount) elements ===
        \(restDump)

        === Dock.app AX tree WHILE Mission Control is presented — \(presentedCount) elements ===
        \(presentedDump)
        """

        let directory = Self.diagnosticsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("dock-ax-dump-\(Int(Date().timeIntervalSince1970)).txt")
        try output.write(to: fileURL, atomically: true, encoding: .utf8)

        Log.accessibility.info("Wrote AX diagnostic dump to \(fileURL.path, privacy: .public)")
        return DumpResult(fileURL: fileURL, elementCountAtRest: restCount, elementCountWhilePresented: presentedCount)
    }

    /// Read-only: drills straight to the Spaces Bar (found in the first diagnostic pass to carry
    /// stable `AXIdentifier`s `mc.spaces.list` / `mc.spaces.add`) and dumps *every* attribute and
    /// available action on it and its children — not just the fixed handful the general dump
    /// checks — specifically to find whichever attribute marks the currently active desktop.
    /// Performs no `AXPress` or other mutating action.
    func dumpSpacesBarDetail() async throws -> DumpResult {
        guard AXIsProcessTrusted() else { throw ServiceError.notTrusted }
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            throw ServiceError.dockProcessNotFound
        }
        guard let missionControlURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") else {
            throw ServiceError.missionControlAppNotFound
        }

        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)

        Log.accessibility.info("Detailed diagnostic: invoking Mission Control")
        try await NSWorkspace.shared.openApplication(at: missionControlURL, configuration: NSWorkspace.OpenConfiguration())
        try await Task.sleep(for: .milliseconds(700))

        var output = "Nexus Mission Control detailed Spaces Bar diagnostic\nCaptured: \(Date().formatted(.iso8601))\n\n"

        if let spacesList = findElement(axApp, matchingIdentifier: "mc.spaces.list", depth: 0) {
            output += describeElementFully(spacesList, label: "mc.spaces.list")
            if let children = copyAttribute(spacesList, kAXChildrenAttribute as CFString) as? [AXUIElement] {
                for (index, child) in children.enumerated() {
                    output += "\n--- child[\(index)] ---\n"
                    output += describeElementFully(child, label: "child[\(index)]")
                }
            }
        } else {
            output += "mc.spaces.list not found\n"
        }

        if let addButton = findElement(axApp, matchingIdentifier: "mc.spaces.add", depth: 0) {
            output += "\n--- add button ---\n"
            output += describeElementFully(addButton, label: "mc.spaces.add")
        }

        dismissMissionControl()

        let directory = Self.diagnosticsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("dock-ax-detail-\(Int(Date().timeIntervalSince1970)).txt")
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        Log.accessibility.info("Wrote detailed AX dump to \(fileURL.path, privacy: .public)")

        return DumpResult(fileURL: fileURL, elementCountAtRest: 0, elementCountWhilePresented: 0)
    }

    private func findElement(_ root: AXUIElement, matchingIdentifier target: String, depth: Int) -> AXUIElement? {
        guard depth <= 12 else { return nil }
        if let id = copyAttribute(root, "AXIdentifier" as CFString) as? String, id == target {
            return root
        }
        guard let children = copyAttribute(root, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findElement(child, matchingIdentifier: target, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func describeElementFully(_ element: AXUIElement, label: String) -> String {
        var names: CFArray?
        let namesResult = AXUIElementCopyAttributeNames(element, &names)
        var text = "[\(label)] attributes:\n"
        guard namesResult == .success, let attributeNames = names as? [String] else {
            text += "  (failed to list attributes)\n"
            return text
        }
        for name in attributeNames {
            let value = copyAttribute(element, name as CFString)
            text += "  \(name) = \(describeValue(value))\n"
        }

        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success, let actions = actionNames as? [String] {
            text += "  [actions] = \(actions.joined(separator: ", "))\n"
        }
        return text
    }

    private func describeValue(_ value: AnyObject?) -> String {
        guard let value else { return "nil" }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return "<AXUIElement>"
        }
        if let array = value as? [AXUIElement] {
            return "<AXUIElement array, count=\(array.count)>"
        }
        return "\(value)"
    }

    private func describeElement(_ element: AXUIElement, depth: Int, maxDepth: Int, count: inout Int) -> String {
        guard depth <= maxDepth else { return "" }
        count += 1
        let indent = String(repeating: "  ", count: depth)

        let role = copyAttribute(element, kAXRoleAttribute as CFString) as? String ?? "?"
        let subrole = copyAttribute(element, kAXSubroleAttribute as CFString) as? String
        let title = copyAttribute(element, kAXTitleAttribute as CFString) as? String
        let description = copyAttribute(element, kAXDescriptionAttribute as CFString) as? String
        let identifier = copyAttribute(element, "AXIdentifier" as CFString) as? String

        var line = "\(indent)- role=\(role)"
        if let subrole, !subrole.isEmpty { line += " subrole=\(subrole)" }
        if let title, !title.isEmpty { line += " title=\"\(title)\"" }
        if let description, !description.isEmpty { line += " desc=\"\(description)\"" }
        if let identifier, !identifier.isEmpty { line += " id=\(identifier)" }
        line += "\n"

        guard let children = copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return line
        }
        for child in children {
            line += describeElement(child, depth: depth + 1, maxDepth: maxDepth, count: &count)
        }
        return line
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }

    /// Escape reliably dismisses a presented Mission Control. Posting a synthetic key event this
    /// way requires the same Accessibility trust already gated on above.
    private func dismissMissionControl() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func diagnosticsDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nexus", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
    }
}
