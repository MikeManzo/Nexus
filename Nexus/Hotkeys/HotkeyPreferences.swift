//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Carbon.HIToolbox
import Foundation

struct HotkeyBinding: Codable, Sendable, Equatable {
    var shortcut: KeyboardShortcut
    var isEnabled: Bool
}

enum HotkeyDefaults {
    /// ⌃⌥⌘S open, ⌃⌥⌘N create, ⌃⌥⌘1…9 switch ; matching the examples in the product spec.
    static func makeDefaults() -> [HotkeyAction: HotkeyBinding] {
        var result: [HotkeyAction: HotkeyBinding] = [
            .openNexus: HotkeyBinding(shortcut: KeyboardShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: defaultModifiers), isEnabled: true),
            .createDesktop: HotkeyBinding(shortcut: KeyboardShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: defaultModifiers), isEnabled: true),
        ]
        let digitCodes: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, action) in HotkeyAction.orderedForDisplay.filter({ $0.desktopSlot != nil }).enumerated() {
            result[action] = HotkeyBinding(shortcut: KeyboardShortcut(keyCode: UInt32(digitCodes[index]), modifiers: defaultModifiers), isEnabled: true)
        }
        return result
    }

    private static var defaultModifiers: UInt32 {
        UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
    }
}

protocol HotkeyPreferencesStoring: Sendable {
    func loadBindings() -> [HotkeyAction: HotkeyBinding]
    func saveBindings(_ bindings: [HotkeyAction: HotkeyBinding])
}

struct UserDefaultsHotkeyPreferencesStore: HotkeyPreferencesStoring {
    private let storageKey = "hotkeyBindings"
    // UserDefaults is documented as thread-safe but isn't annotated Sendable in this SDK.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadBindings() -> [HotkeyAction: HotkeyBinding] {
        var result = HotkeyDefaults.makeDefaults()
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else {
            return result
        }
        // Defaults are the fallback for anything missing from a stale saved dictionary (e.g.
        // after an app update added a new action), so start from them and overlay saved values.
        for (rawValue, binding) in decoded {
            guard let action = HotkeyAction(rawValue: rawValue) else { continue }
            result[action] = binding
        }
        return result
    }

    func saveBindings(_ bindings: [HotkeyAction: HotkeyBinding]) {
        let encodable = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
