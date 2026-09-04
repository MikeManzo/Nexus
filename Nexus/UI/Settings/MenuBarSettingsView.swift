import SwiftUI

struct MenuBarSettingsView: View {
    @AppStorage("menuBarDisplayMode") private var displayModeRaw = MenuBarDisplayMode.name.rawValue

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
        }
        .formStyle(.grouped)
    }
}
