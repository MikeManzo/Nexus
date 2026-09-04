import SwiftUI

struct UpdatesSettingsView: View {
    @Bindable var preferences: UpdatePreferences

    var body: some View {
        Form {
            LabeledContent("Installed version", value: preferences.installedVersion)
            Toggle("Automatically check for updates", isOn: $preferences.automaticallyChecksForUpdates)
            Toggle("Automatically download updates", isOn: $preferences.automaticallyDownloadsUpdates)
                .disabled(!preferences.automaticallyChecksForUpdates)
            LabeledContent("Last checked", value: lastCheckedText)
            Button("Check for Updates…") {
                preferences.checkForUpdates()
            }
            .disabled(!preferences.canCheckForUpdates)
        }
        .padding(20)
    }

    private var lastCheckedText: String {
        guard let date = preferences.lastUpdateCheckDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
