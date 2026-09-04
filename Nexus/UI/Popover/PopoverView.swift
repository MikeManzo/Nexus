import AppKit
import SwiftUI

/// The menu bar dropdown. Matches the product spec's conceptual layout: current-Space header,
/// desktop list with quick-switch shortcuts, quick actions, then app-level footer actions.
struct PopoverView: View {
    let coordinator: AppCoordinator
    var dismiss: () -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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

            if coordinator.spaces.isEmpty {
                Text(coordinator.accessibilityPermission.isTrusted ? "No desktops found yet." : "Grant Accessibility access in Settings to see your desktops.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 66), spacing: 10)], spacing: 12) {
                    ForEach(coordinator.spaces) { space in
                        DesktopTile(space: space, isBusy: coordinator.isBusy) {
                            Task { await coordinator.activate(space) }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
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

/// One tile in the desktop grid — a colored swatch (the desktop's own accent) with its number,
/// its name below, and a ring around the active one. Its own view so hover state can be tracked
/// locally without re-rendering the whole popover on every mouse move.
private struct DesktopTile: View {
    let space: DesktopSpace
    let isBusy: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(space.accentColor.opacity(space.isActive ? 0.95 : (isHovering ? 0.75 : 0.55)))
                    .frame(width: 52, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(space.isActive ? 0.85 : 0), lineWidth: 2)
                    )
                    .overlay(
                        Text("\(space.order + 1)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
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
