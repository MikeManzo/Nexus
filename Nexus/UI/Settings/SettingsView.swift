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

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            PermissionsSettingsView(coordinator: coordinator)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            MenuBarSettingsView(coordinator: coordinator)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            ShortcutsSettingsView(coordinator: coordinator)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            UpdatesSettingsView(preferences: coordinator.updatePreferences)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }

            AccessibilitySettingsView(coordinator: coordinator)
                .tabItem { Label("Accessibility", systemImage: "accessibility") }

            ExperimentalSettingsView()
                .tabItem { Label("Experimental", systemImage: "flask") }
        }
        .frame(width: 480, height: 480)
    }
}
