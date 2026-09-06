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

/// A sidebar of colored icon badges + a detail pane, matching System Settings' own current
/// layout — not the classic toolbar-tab-row style most third-party Mac apps' preferences windows
/// still use, per explicit request to match the real System Settings look and feel. Deliberately
/// doesn't copy System Settings' own account/profile row at the top of its sidebar: Nexus has no
/// concept of a signed-in account, so there'd be nothing real to show there.
struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var selectedPane: SettingsPane? = .general
    @State private var searchText = ""

    // Back/forward pane history, like System Settings' own toolbar arrows — a plain
    // `List(selection:)` only tracks the *current* selection, so this is hand-rolled: every
    // sidebar click appends to `paneHistory` and moves `historyIndex` to the end; the arrows just
    // move `historyIndex` without appending. `isNavigatingHistory` is what tells those two cases
    // apart inside the single `onChange` both paths funnel through.
    @State private var paneHistory: [SettingsPane] = [.general]
    @State private var historyIndex = 0
    @State private var isNavigatingHistory = false

    private var filteredPanes: [SettingsPane] {
        guard !searchText.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredPanes, selection: $selectedPane) { pane in
                sidebarRow(pane)
                    .tag(pane)
            }
            .searchable(text: $searchText, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            detail(for: selectedPane ?? .general)
                .navigationSplitViewColumnWidth(min: 420, ideal: 460)
        }
        .frame(width: 660, height: 480)
        // The sidebar-collapse button NavigationSplitView adds to the toolbar by default — System
        // Settings' own sidebar is always visible, with no such toggle.
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                    .help("Back")
                Button { goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                    .help("Forward")
            }
        }
        .onChange(of: selectedPane) { _, newValue in
            guard let newValue else { return }
            if isNavigatingHistory {
                isNavigatingHistory = false
            } else {
                recordHistory(newValue)
            }
        }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < paneHistory.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        isNavigatingHistory = true
        selectedPane = paneHistory[historyIndex]
    }

    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        isNavigatingHistory = true
        selectedPane = paneHistory[historyIndex]
    }

    private func recordHistory(_ pane: SettingsPane) {
        guard paneHistory[historyIndex] != pane else { return }
        paneHistory.removeSubrange((historyIndex + 1)...)
        paneHistory.append(pane)
        historyIndex = paneHistory.count - 1
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(pane.iconColor.gradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: pane.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                )
            Text(pane.title)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        Group {
            switch pane {
            case .general: GeneralSettingsView()
            case .permissions: PermissionsSettingsView(coordinator: coordinator)
            case .menuBar: MenuBarSettingsView(coordinator: coordinator)
            case .shortcuts: ShortcutsSettingsView(coordinator: coordinator)
            case .updates: UpdatesSettingsView(preferences: coordinator.updatePreferences)
            }
        }
        .navigationTitle(pane.title)
    }
}
