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

struct UpdatesSettingsView: View {
    @Bindable var preferences: UpdatePreferences

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("Installed version", value: preferences.installedVersion)
                LabeledContent("Last checked", value: lastCheckedText)
            }

            Section("Automatic Updates") {
                Toggle("Automatically check for updates", isOn: $preferences.automaticallyChecksForUpdates)
                Toggle("Automatically download updates", isOn: $preferences.automaticallyDownloadsUpdates)
                    .disabled(!preferences.automaticallyChecksForUpdates)
            }

            Section {
                Button("Check for Updates…") {
                    preferences.checkForUpdates()
                }
                .disabled(!preferences.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedText: String {
        guard let date = preferences.lastUpdateCheckDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
