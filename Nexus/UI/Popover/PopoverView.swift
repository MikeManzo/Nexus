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
        VStack(alignment: .leading, spacing: 2) {
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
            }

            ForEach(coordinator.spaces) { space in
                DesktopRow(space: space, isBusy: coordinator.isBusy) {
                    Task { await coordinator.activate(space) }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 6)
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

/// One row in the desktop list — its own view so hover state can be tracked locally without
/// re-rendering the whole popover on every mouse move.
private struct DesktopRow: View {
    let space: DesktopSpace
    let isBusy: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(space.accentColor)
                    .frame(width: 8, height: 8)
                Text(space.displayName)
                    .fontWeight(space.isActive ? .semibold : .regular)
                Spacer()
                if space.order < 9 {
                    Text("⌘\(space.order + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(rowBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
        .accessibilityLabel(space.isActive ? "\(space.displayName), current desktop" : space.displayName)
        .accessibilityHint("Switches to this desktop")
        .accessibilityAddTraits(space.isActive ? [.isSelected] : [])
    }

    private var rowBackground: Color {
        if space.isActive { return space.accentColor.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}
