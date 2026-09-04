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
