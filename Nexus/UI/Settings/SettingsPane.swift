//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

/// One row in Settings' sidebar — see `SettingsView`'s doc comment for why this replaced the
/// classic toolbar-tab-row layout. `iconColor` mirrors System Settings' own convention of a
/// distinct badge color per section purely for visual variety and memorability at a glance;
/// there's no semantic meaning behind any particular choice here, the same way there isn't in
/// System Settings itself.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, permissions, menuBar, shortcuts, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .menuBar: "Menu Bar"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .permissions: "lock.shield.fill"
        case .menuBar: "menubar.rectangle"
        case .shortcuts: "command.square.fill"
        case .updates: "arrow.down.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .gray
        case .permissions: .green
        case .menuBar: .indigo
        case .shortcuts: .purple
        case .updates: .blue
        }
    }
}
