import SwiftUI

struct MenuBarSettingsView: View {
    @AppStorage("menuBarDisplayMode") private var displayModeRaw = MenuBarDisplayMode.icon.rawValue

    var body: some View {
        Form {
            Picker("Menu bar style", selection: $displayModeRaw) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
    }
}
