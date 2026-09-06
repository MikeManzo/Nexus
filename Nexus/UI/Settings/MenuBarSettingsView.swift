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
                // A custom radio list, not `.pickerStyle(.radioGroup)` — the built-in style only
                // lets each row show a plain label, with no way to attach the live preview beside
                // it, which was the whole point of replacing it (that empty space to the right of
                // the options was otherwise unused).
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        modeRow(mode)
                    }
                }
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

    private func modeRow(_ mode: MenuBarDisplayMode) -> some View {
        let isSelected = displayModeRaw == mode.rawValue
        return Button {
            displayModeRaw = mode.rawValue
        } label: {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(mode.label)
                Spacer()
                previewStrip(for: mode)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A small mocked-up menu bar chip showing exactly what this mode renders — matching
    /// `StatusItemController.updateAppearance()`'s own logic (same dot/accent color, same
    /// truncated name, same fallbacks) — using the real active desktop when there is one, so this
    /// isn't just a generic mockup but an actual live preview.
    private func previewStrip(for mode: MenuBarDisplayMode) -> some View {
        let name = coordinator.activeSpace?.displayName ?? "General"
        let color = coordinator.activeSpace?.accentColor ?? Color.accentColor
        let number = (coordinator.activeSpace?.order ?? 0) + 1

        return HStack(spacing: 5) {
            switch mode {
            case .name:
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.caption.weight(.semibold)).lineLimit(1)
            case .icon:
                Image(systemName: "rectangle.3.group").font(.system(size: 12))
            case .number:
                Text("\(number)").font(.caption.weight(.semibold))
            case .letter:
                Text(name.first.map(String.init) ?? "–").font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }
}
