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
import CoreGraphics
import Foundation

/// Reads macOS's own `com.apple.symbolichotkeys` preferences to check whether the user has
/// assigned a built-in "Switch to Desktop N" shortcut (System Settings → Keyboard → Keyboard
/// Shortcuts… → Mission Control). Verified empirically, not guessed: diffing that preferences
/// file before/after assigning "Switch to Desktop 1" showed it lands at id 118, with "Switch to
/// Desktop 2"/"3" pre-populated (disabled) at 119/120 — a sequential `118 + (N - 1)` scheme.
///
/// When one of these is assigned and enabled, triggering it is a genuine system-level space
/// switch with **no UI presented at all** — the OS does it, not us — because it isn't Nexus
/// driving Mission Control, it's the same mechanism as the user pressing that key combo
/// themselves. That's a strictly better path than `AccessibilitySpaceManager`'s default
/// Mission-Control-flashing switch, so `activate(_:)` tries this first and only falls back to
/// the AX-driven approach when a given desktop has no such shortcut configured. These shortcuts
/// ship *unassigned* by default, so this is opportunistic, not a universal replacement — see
/// `docs/01-capability-research.md` §11.
enum SymbolicHotkeyLookup {
    struct Binding {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    /// `slot` is the 0-based desktop order index ("Switch to Desktop 1" == slot 0).
    static func desktopSwitchBinding(forSlot slot: Int) -> Binding? {
        let hotkeyID = 118 + slot
        guard let allHotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys"),
            let entry = allHotkeys["\(hotkeyID)"] as? [String: Any],
            (entry["enabled"] as? NSNumber)?.boolValue == true,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Int],
            parameters.count >= 3
        else {
            return nil
        }

        let keyCode = CGKeyCode(parameters[1])
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))
        var cgFlags: CGEventFlags = []
        if nsFlags.contains(.control) { cgFlags.insert(.maskControl) }
        if nsFlags.contains(.option) { cgFlags.insert(.maskAlternate) }
        if nsFlags.contains(.shift) { cgFlags.insert(.maskShift) }
        if nsFlags.contains(.command) { cgFlags.insert(.maskCommand) }
        return Binding(keyCode: keyCode, flags: cgFlags)
    }
}
