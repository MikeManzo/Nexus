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

/// The full desktop-management window: customize (name + accent color), delete, create, and
/// (via double-click) switch.
struct SpaceManagerView: View {
    let coordinator: AppCoordinator

    @State private var renamingSpace: DesktopSpace?
    @State private var renameText = ""
    @State private var customizeColorHex: String?
    @State private var customizeSymbolName: String?
    @State private var customizeLaunchAppBundleIDs: [String] = []
    @State private var customizeShortcut: KeyboardShortcut?
    @State private var shortcutConflictMessage: String?
    @State private var pendingDeletion: DesktopSpace?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            List {
                ForEach(coordinator.spaces) { space in
                    row(for: space)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
            }
            .listStyle(.inset)
            .disabled(coordinator.isBusy)
            Divider()
            HStack {
                Button {
                    Task { await coordinator.createSpace() }
                } label: {
                    Label("Create Desktop", systemImage: "plus")
                }
                .disabled(coordinator.isBusy)
                if coordinator.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 440, minHeight: 480)
        .task { await coordinator.refresh() }
        .sheet(item: $renamingSpace) { space in
            customizeSheet(for: space)
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.displayName ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in if !isPresented { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let space = pendingDeletion {
                    Task { await coordinator.delete(space) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
        .alert(item: errorBinding) { error in
            Alert(title: Text("Nexus"), message: Text(error.errorDescription ?? "Something went wrong."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Desktops").font(.title2.bold())
            Text("\(coordinator.spaces.count) desktops")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }

    private func row(for space: DesktopSpace) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if space.isActive {
                    Circle()
                        .strokeBorder(space.accentColor, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
                if let symbolName = space.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 11))
                        .foregroundStyle(space.accentColor)
                } else {
                    Circle()
                        .fill(space.accentColor)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayName).font(.body.weight(.medium))
                Text("Desktop \(space.order + 1)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Customize…") {
                renameText = space.customName ?? ""
                customizeColorHex = space.accentColorHex
                customizeSymbolName = space.symbolName
                customizeLaunchAppBundleIDs = space.launchAppBundleIDs ?? []
                customizeShortcut = space.hotkeyShortcut
                shortcutConflictMessage = nil
                renamingSpace = space
            }
            .buttonStyle(.link)
            .accessibilityLabel("Customize \(space.displayName)")

            Button("Delete") {
                pendingDeletion = space
            }
            .buttonStyle(.link)
            .foregroundStyle(.red)
            .disabled(coordinator.spaces.count <= 1)
            .accessibilityLabel("Delete \(space.displayName)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(space.isActive ? space.accentColor.opacity(0.12) : Color.clear)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(space.isActive ? "\(space.displayName), current desktop" : space.displayName)
        .accessibilityHint("Double-click to switch to this desktop")
        .onTapGesture(count: 2) {
            guard !coordinator.isBusy else { return }
            Task { await coordinator.activate(space) }
        }
    }

    private func customizeSheet(for space: DesktopSpace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize Desktop").font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitCustomize(for: space) }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.caption).foregroundStyle(.secondary)
                IconPicker(selectedSymbolName: $customizeSymbolName)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent color").font(.caption).foregroundStyle(.secondary)
                AccentColorPicker(selectedHex: $customizeColorHex)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Launch these apps when you arrive").font(.caption).foregroundStyle(.secondary)
                LaunchAppsPicker(bundleIDs: $customizeLaunchAppBundleIDs)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Desktop shortcut").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ShortcutRecorderView(currentShortcut: customizeShortcut) { newShortcut in
                        if let conflict = coordinator.hotkeyCoordinator?.conflictDescription(for: newShortcut, excludingSpace: space) {
                            shortcutConflictMessage = "\(newShortcut.displayString) is already used by \(conflict)."
                        } else {
                            customizeShortcut = newShortcut
                            shortcutConflictMessage = nil
                        }
                    }
                    if customizeShortcut != nil {
                        Button("Clear") {
                            customizeShortcut = nil
                            shortcutConflictMessage = nil
                        }
                        .buttonStyle(.link)
                    }
                }
                if let shortcutConflictMessage {
                    Text(shortcutConflictMessage).font(.caption).foregroundStyle(.red)
                }
                Text("Switches straight to this desktop from anywhere, independent of its position — see Settings → Shortcuts for the numbered-slot shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { renamingSpace = nil }
                Button("Save") { commitCustomize(for: space) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func commitCustomize(for space: DesktopSpace) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await coordinator.rename(space, to: name)
            await coordinator.setAccentColor(customizeColorHex, for: space)
            await coordinator.setSymbol(customizeSymbolName, for: space)
            await coordinator.setLaunchAppBundleIDs(customizeLaunchAppBundleIDs, for: space)
            await coordinator.setShortcut(customizeShortcut, for: space)
        }
        renamingSpace = nil
    }

    private var errorBinding: Binding<SpaceError?> {
        Binding(get: { coordinator.lastError }, set: { coordinator.lastError = $0 })
    }
}
