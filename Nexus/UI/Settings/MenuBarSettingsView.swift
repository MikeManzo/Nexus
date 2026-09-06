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

struct MenuBarSettingsView: View {
    let coordinator: AppCoordinator

    @AppStorage("menuBarDisplayMode") private var displayModeRaw = MenuBarDisplayMode.name.rawValue
    @AppStorage(MenuBarLandingZoneController.enabledDefaultsKey) private var quickSwitcherEnabled = false
    @AppStorage(DesktopThumbnailCache.enabledDefaultsKey) private var previewsEnabled = false

    var body: some View {
        Form {
            Section("Display") {
                Picker("Menu bar style", selection: $displayModeRaw) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Quick Switcher") {
                Toggle("Show quick switcher in menu bar", isOn: $quickSwitcherEnabled)
                Text("A small pill centered in the menu bar showing your current desktop. Hover over it to see and switch between all your desktops without opening the full menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Desktop Previews") {
                Toggle("Show last-seen previews in quick switcher", isOn: $previewsEnabled)
                    .onChange(of: previewsEnabled) { _, enabled in
                        if enabled { coordinator.screenRecordingPermission.requestPermission() }
                    }

                Text("Each tile shows a screenshot from the last time you were on that desktop ; not a live view, since macOS doesn't render desktops you aren't currently looking at. The screenshot updates every time you switch to or away from a desktop, and never leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if previewsEnabled && !coordinator.screenRecordingPermission.isTrusted {
                    Text("Screen Recording access is required for previews.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Grant Access…") {
                            coordinator.screenRecordingPermission.requestPermission()
                        }
                        Button("Open System Settings…") {
                            coordinator.screenRecordingPermission.openSystemSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { coordinator.screenRecordingPermission.refresh() }
    }
}
