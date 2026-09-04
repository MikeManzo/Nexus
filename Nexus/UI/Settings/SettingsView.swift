import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            MenuBarSettingsView()
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
