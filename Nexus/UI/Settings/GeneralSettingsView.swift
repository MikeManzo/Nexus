import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("Appearance") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }

            Section {
                Button("Show Welcome Screen…") {
                    (NSApp.delegate as? AppDelegate)?.presentOnboarding()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
