//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import SwiftUI

/// The menu bar dropdown. Matches the product spec's conceptual layout: current-Space header,
/// desktop list with quick-switch shortcuts, quick actions, then app-level footer actions.
struct PopoverView: View {
    let coordinator: AppCoordinator
    var dismiss: () -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    // Right-click a tile → "Rename & Color…" swaps the grid for this inline form, right there in
    // the popover, rather than a `.sheet`: a modal sheet presented from inside a `.transient`
    // `NSPopover` is a known fragile combination (the popover can lose key status to the sheet's
    // own window and auto-dismiss out from under it). Everything here stays in the popover's own
    // content view, so there's no second window for it to fight with.
    @State private var editingSpace: DesktopSpace?
    @State private var editName = ""
    @State private var editColorHex: String?
    @FocusState private var editNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentSpaceHeader
            if let error = coordinator.lastError {
                errorBanner(error)
            }
            Divider()
            desktopList
            Divider()
            quickActions
            Divider()
            footerActions
        }
        .frame(width: 300)
    }

    private func errorBanner(_ error: SpaceError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.caption)
            Spacer(minLength: 0)
            Button {
                coordinator.lastError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var currentSpaceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("CURRENT SPACE")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if coordinator.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
            }

            if let active = coordinator.activeSpace {
                HStack(spacing: 8) {
                    Circle().fill(active.accentColor).frame(width: 9, height: 9)
                    Text(active.displayName).font(.headline)
                }
                Text("Desktop \(active.order + 1) of \(coordinator.spaces.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active desktop detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerTint)
    }

    private var headerTint: some View {
        (coordinator.activeSpace?.accentColor ?? Color.accentColor)
            .opacity(0.08)
    }

    private var desktopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESKTOPS")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let editingSpace {
                editPanel(for: editingSpace)
            } else if coordinator.spaces.isEmpty {
                Text(coordinator.accessibilityPermission.isTrusted ? "No desktops found yet." : "Grant Accessibility access in Settings to see your desktops.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 66), spacing: 10)], spacing: 12) {
                        ForEach(coordinator.spaces) { space in
                            DesktopTile(
                                space: space,
                                isBusy: coordinator.isBusy,
                                thumbnail: coordinator.thumbnailCache.thumbnail(for: space)
                            ) {
                                Task { await coordinator.activate(space) }
                            }
                            .contextMenu {
                                Button("Rename & Color…") {
                                    beginEditing(space)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
    }

    private func beginEditing(_ space: DesktopSpace) {
        editName = space.customName ?? ""
        editColorHex = space.accentColorHex
        editingSpace = space
    }

    private func editPanel(for space: DesktopSpace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .focused($editNameFieldFocused)
                .onSubmit { commitEdit(for: space) }

            AccentColorPicker(selectedHex: $editColorHex)

            HStack {
                Spacer()
                Button("Cancel") { editingSpace = nil }
                Button("Save") { commitEdit(for: space) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear { editNameFieldFocused = true }
    }

    private func commitEdit(for space: DesktopSpace) {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await coordinator.rename(space, to: name)
            await coordinator.setAccentColor(editColorHex, for: space)
        }
        editingSpace = nil
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await coordinator.createSpace() }
            } label: {
                Label("New Desktop", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isBusy)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityHint("Creates a new desktop")

            Button {
                openWindow(id: "space-manager")
                NSApp.activate(ignoringOtherApps: true)
                dismiss()
            } label: {
                Text("Manage Desktops…")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityHint("Opens the desktop management window")
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("Check for Updates…") {
                coordinator.updateManager.checkForUpdates()
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.updateManager.canCheckForUpdates)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("Settings") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("Quit Nexus") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 6)
    }
}

/// One tile in the desktop grid — a colored swatch (the desktop's own accent, as a plain fill;
/// see the body's comment on why not `Glass.tint(_:)`) wrapped in a real Liquid Glass backing for
/// its translucent depth and interactive press feedback, showing a cached last-seen screenshot on
/// top when `DesktopThumbnailCache` has one, with a number badge, name below, and a ring around
/// the active one. The number always sits in a small scrimmed badge (rather than centered) so it
/// stays legible over a photo, not just a flat color — kept that way even when there's no
/// thumbnail yet, so tiles don't jump around as previews fill in one by one. Its own view so hover
/// state can be tracked locally without re-rendering the whole popover on every mouse move. Shared
/// with `LandingZoneView`'s grid; both wrap their grid of tiles in a `GlassEffectContainer` so the
/// tiles' glass panels composite together the way Apple's Liquid Glass guidance recommends for
/// co-located glass elements, rather than each rendering as an isolated glass layer.
struct DesktopTile: View {
    let space: DesktopSpace
    let isBusy: Bool
    var thumbnail: NSImage?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    // The desktop's accent color as a plain fill, not `Glass.tint(_:)` — verified
                    // live that tint doesn't render visibly in this context (an active tile tinted
                    // at 0.9 opacity showed no color at all), so color identity goes through the
                    // one rendering path guaranteed to actually show it. `.glassEffect` below still
                    // wraps this content for the glass backing and interactive press feedback.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(space.accentColor.opacity(space.isActive ? 0.95 : (isHovering ? 0.55 : 0.28)))

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(space.isActive ? 1 : (isHovering ? 0.7 : 0.4))
                    }

                    Text("\(space.order + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(3)
                }
                .frame(width: 52, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .glassEffect(Glass.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(space.isActive ? 0.85 : 0), lineWidth: 2)
                )
                Text(space.displayName)
                    .font(.caption2)
                    .fontWeight(space.isActive ? .bold : .regular)
                    .foregroundStyle(space.isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
        .accessibilityLabel(space.isActive ? "\(space.displayName), current desktop" : space.displayName)
        .accessibilityHint("Switches to this desktop")
        .accessibilityAddTraits(space.isActive ? [.isSelected] : [])
    }
}
