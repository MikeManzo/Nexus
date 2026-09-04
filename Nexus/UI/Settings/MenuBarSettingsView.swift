import SwiftUI

struct MenuBarSettingsView: View {
    @AppStorage("menuBarDisplayMode") private var displayModeRaw = MenuBarDisplayMode.name.rawValue
    @AppStorage(MenuBarLandingZoneController.enabledDefaultsKey) private var quickSwitcherEnabled = false

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
        }
        .formStyle(.grouped)
    }
}
