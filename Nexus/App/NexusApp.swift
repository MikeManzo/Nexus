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

@main
struct NexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(coordinator: appDelegate.coordinator)
        }

        Window("Manage Desktops", id: "space-manager") {
            SpaceManagerView(coordinator: appDelegate.coordinator)
        }
        .defaultSize(width: 480, height: 520)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.coordinator.updatePreferences.checkForUpdates()
                }
                .disabled(!appDelegate.coordinator.updatePreferences.canCheckForUpdates)
            }
        }
    }
}
