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

struct ShortcutsSettingsView: View {
    let coordinator: AppCoordinator

    @State private var conflictMessage: String?
    @State private var flashFreeStatus: String?
    @State private var autoAssignedSlots: Set<Int> = SystemShortcutConfigurator.autoAssignedSlots()

    var body: some View {
        Group {
            if let hotkeys = coordinator.hotkeyCoordinator {
                content(hotkeys)
            } else {
                Text("Shortcuts aren't available yet.")
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
        }
    }

    private func content(_ hotkeys: HotkeyCoordinator) -> some View {
        Form {
            Section("Global Shortcuts") {
                ForEach(HotkeyAction.orderedForDisplay, id: \.self) { action in
                    if let binding = hotkeys.bindings[action] {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { binding.isEnabled },
                                set: { hotkeys.setEnabled($0, for: action) }
                            )) {
                                Text(action.label)
                            }
                            Spacer()
                            ShortcutRecorderView(currentShortcut: binding.shortcut) { newShortcut in
                                if hotkeys.setShortcut(newShortcut, for: action) {
                                    conflictMessage = nil
                                } else {
                                    let conflict = hotkeys.conflictingAction(for: newShortcut, excluding: action)
                                    conflictMessage = "\(newShortcut.displayString) is already used by \(conflict?.label ?? "another action")."
                                }
                            }
                            .disabled(!binding.isEnabled)
                        }
                    }
                }

                if let conflictMessage {
                    Text(conflictMessage).font(.caption).foregroundStyle(.red)
                }

                Text("Shortcuts work even when Nexus isn't the active app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Want a shortcut for a specific desktop by name instead of its position? Set that from Manage Desktops → Customize… — it follows the desktop even if you reorder or rename it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Flash-Free Switching") {
                Text("Assigns macOS's own built-in \"Switch to Desktop N\" shortcut (Control+1, Control+2, …) for your first \(SystemShortcutConfigurator.maxSupportedDesktops) desktops, so switching never flashes Mission Control ; the same mechanism you set up manually for Desktop 1, applied to the rest. Never overwrites a shortcut already in use for something else. Once enabled, new desktops you create get one automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Enable for All Desktops") {
                        enableForAllDesktops()
                    }
                    if !autoAssignedSlots.isEmpty {
                        Button("Remove Auto-Configured Shortcuts") {
                            SystemShortcutConfigurator.removeAutoAssignedShortcuts()
                            SystemShortcutConfigurator.isEnabled = false
                            autoAssignedSlots = SystemShortcutConfigurator.autoAssignedSlots()
                            flashFreeStatus = "Removed."
                        }
                    }
                }

                if !autoAssignedSlots.isEmpty {
                    Text("Nexus-configured: Desktop \(autoAssignedSlots.sorted().map { "\($0 + 1)" }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let flashFreeStatus {
                    Text(flashFreeStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func enableForAllDesktops() {
        var configuredCount = 0
        var failure: String?
        for slot in coordinator.spaces.indices {
            do {
                if try SystemShortcutConfigurator.ensureShortcut(forSlot: slot) {
                    configuredCount += 1
                }
            } catch {
                failure = error.localizedDescription
                break
            }
        }
        autoAssignedSlots = SystemShortcutConfigurator.autoAssignedSlots()
        if let failure {
            flashFreeStatus = "Failed: \(failure)"
        } else {
            SystemShortcutConfigurator.isEnabled = true
            if configuredCount == 0 {
                flashFreeStatus = "All desktops already had a shortcut configured. New desktops you create will get one automatically."
            } else {
                flashFreeStatus = "Configured \(configuredCount) desktop\(configuredCount == 1 ? "" : "s"). New desktops you create will get one automatically."
            }
        }
    }
}
