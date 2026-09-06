//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

/// The fixed set of actions Nexus can bind a global shortcut to. Desktop switching is by
/// numbered slot (order index), matching the ⌘1…⌘9 shown in the popover, rather than by a named
/// space ; binding a shortcut to "whatever Space is currently in slot 3" is simpler to reason
/// about than tracking a shortcut through renames and reordering, and matches how the popover
/// already presents desktops.
enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case openNexus
    case createDesktop
    case switchToDesktop1, switchToDesktop2, switchToDesktop3, switchToDesktop4, switchToDesktop5
    case switchToDesktop6, switchToDesktop7, switchToDesktop8, switchToDesktop9

    /// 0-based order index this action switches to, or `nil` for non-switching actions.
    var desktopSlot: Int? {
        guard rawValue.hasPrefix("switchToDesktop"),
              let n = Int(rawValue.dropFirst("switchToDesktop".count)) else {
            return nil
        }
        return n - 1
    }

    var label: String {
        if let slot = desktopSlot { return "Switch to Desktop \(slot + 1)" }
        switch self {
        case .openNexus: return "Open Nexus"
        case .createDesktop: return "Create Desktop"
        default: return rawValue
        }
    }

    /// Display order for the Shortcuts settings list.
    static var orderedForDisplay: [HotkeyAction] {
        [.openNexus, .createDesktop] + (1...9).compactMap { HotkeyAction(rawValue: "switchToDesktop\($0)") }
    }
}
