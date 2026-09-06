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
import Carbon.HIToolbox
import Foundation

/// Writes and applies macOS's own "Switch to Desktop N" shortcuts (`com.apple.symbolichotkeys`,
/// ids 118+, per-slot ; see `SymbolicHotkeyLookup`) on the user's behalf, so every desktop gets
/// the same flash-free switch path `AccessibilitySpaceManager.activate(_:)` already knows how to
/// use ; without touching the private WindowServer Spaces API that corrupted window assignments
/// during Tier 3 testing.
///
/// Verified live on this machine, not assumed: writing the plist entry via `CFPreferences` and
/// then running Apple's own `activateSettings -u` utility (from
/// `SystemAdministration.framework`, itself private/undocumented but far lower-risk ; it only
/// asks the system to re-read a standard preferences file, the same thing System Settings itself
/// does when you check a shortcut's box) applies the change instantly, confirmed by successfully
/// switching via the newly-enabled shortcut immediately after.
///
/// Never overwrites a shortcut already enabled for something else; only fills in slots that are
/// currently unassigned, using the same Control+N combination Apple pre-populates as each
/// entry's own disabled default template. Every slot this configures is recorded so
/// `removeAutoAssignedShortcuts()` can undo exactly what Nexus added and nothing the user
/// configured themselves (through Nexus or directly in System Settings).
enum SystemShortcutConfigurator {
    // Immutable constants; CFString isn't Sendable-annotated in this SDK.
    nonisolated(unsafe) private static let domain = "com.apple.symbolichotkeys" as CFString
    nonisolated(unsafe) private static let hotkeysKey = "AppleSymbolicHotKeys" as CFString
    private static let activateSettingsURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
    private static let autoAssignedSlotsKey = "nexusAutoAssignedShortcutSlots"
    private static let isEnabledKey = "flashFreeSwitchingEnabled"

    /// macOS caps Mission Control at 16 desktop spaces total, but "Switch to Desktop N" only has
    /// an obvious single-key default (Control+1…9, matching System Settings' own disabled
    /// template) for the first 9 ; beyond that there's no natural one-key binding to assign
    /// without inventing a scheme Apple's own UI doesn't use, so this stops there rather than
    /// guess. Desktops 10+ still work fine, just via the standard Accessibility flash.
    static let maxSupportedDesktops = 9

    /// Whether the user has opted into flash-free switching via "Enable for All Desktops" (and
    /// hasn't since turned it off) ; checked by `AppCoordinator.createSpace()` to decide whether
    /// newly created desktops should get a shortcut automatically, without the user having to
    /// revisit Settings each time.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isEnabledKey) }
    }

    enum ConfiguratorError: Error, LocalizedError {
        case toolNotFound
        case synchronizeFailed

        var errorDescription: String? {
            switch self {
            case .toolNotFound: "The system settings-activation tool isn't present on this Mac."
            case .synchronizeFailed: "Failed to save the shortcut preference."
            }
        }
    }

    /// Assigns "Switch to Desktop N" for `slot` (0-based) if nothing is already enabled for it.
    /// Returns whether a change was made.
    @discardableResult
    static func ensureShortcut(forSlot slot: Int) throws -> Bool {
        guard slot < maxSupportedDesktops else { return false }
        guard FileManager.default.fileExists(atPath: activateSettingsURL.path) else {
            throw ConfiguratorError.toolNotFound
        }

        var hotkeys = (CFPreferencesCopyAppValue(hotkeysKey, domain) as? [String: Any]) ?? [:]
        let hotkeyID = "\(118 + slot)"

        if let existing = hotkeys[hotkeyID] as? [String: Any], (existing["enabled"] as? NSNumber)?.boolValue == true {
            return false // already configured, by the user or by us ; leave it alone
        }

        hotkeys[hotkeyID] = [
            "enabled": true,
            "value": [
                "type": "standard",
                "parameters": [65535, keyCode(forDigit: slot + 1), Int(NSEvent.ModifierFlags.control.rawValue)],
            ],
        ]

        CFPreferencesSetAppValue(hotkeysKey, hotkeys as CFDictionary, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw ConfiguratorError.synchronizeFailed
        }

        applyImmediately()
        markAutoAssigned(slot: slot)
        Log.hotkeys.info("Auto-assigned Control+\(slot + 1, privacy: .public) as Switch to Desktop \(slot + 1, privacy: .public)")
        return true
    }

    /// Slots Nexus has auto-assigned so far, for UI display.
    static func autoAssignedSlots() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: autoAssignedSlotsKey) as? [Int] ?? [])
    }

    /// Disables only the shortcuts Nexus itself assigned, leaving anything the user configured
    /// (through Nexus's own initial Desktop-1 setup or directly in System Settings) untouched.
    static func removeAutoAssignedShortcuts() {
        let slots = autoAssignedSlots()
        guard !slots.isEmpty else { return }
        var hotkeys = (CFPreferencesCopyAppValue(hotkeysKey, domain) as? [String: Any]) ?? [:]
        for slot in slots {
            hotkeys["\(118 + slot)"] = ["enabled": false]
        }
        CFPreferencesSetAppValue(hotkeysKey, hotkeys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        applyImmediately()
        UserDefaults.standard.removeObject(forKey: autoAssignedSlotsKey)
        Log.hotkeys.info("Removed \(slots.count, privacy: .public) auto-assigned system shortcuts")
    }

    private static func markAutoAssigned(slot: Int) {
        var slots = autoAssignedSlots()
        slots.insert(slot)
        UserDefaults.standard.set(Array(slots), forKey: autoAssignedSlotsKey)
    }

    private static func applyImmediately() {
        let process = Process()
        process.executableURL = activateSettingsURL
        process.arguments = ["-u"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.hotkeys.error("Failed to run activateSettings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// kVK_ANSI_1…9, matching the physical digit keys System Settings itself uses as the
    /// disabled default template for these entries.
    private static func keyCode(forDigit digit: Int) -> Int {
        switch digit {
        case 1: return Int(kVK_ANSI_1)
        case 2: return Int(kVK_ANSI_2)
        case 3: return Int(kVK_ANSI_3)
        case 4: return Int(kVK_ANSI_4)
        case 5: return Int(kVK_ANSI_5)
        case 6: return Int(kVK_ANSI_6)
        case 7: return Int(kVK_ANSI_7)
        case 8: return Int(kVK_ANSI_8)
        case 9: return Int(kVK_ANSI_9)
        default: return Int(kVK_ANSI_1)
        }
    }
}
