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

/// How the menu bar status item represents the active Space. Persisted via
/// `UserDefaults` key `"menuBarDisplayMode"`.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case name
    case icon
    case number
    case letter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Space Name"
        case .icon: "Icon"
        case .number: "Space Number"
        case .letter: "Space Initial"
        }
    }
}
