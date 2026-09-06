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

/// A single at-a-glance dashboard for every system permission Nexus can use — otherwise these are
/// scattered across the Accessibility tab (its diagnostics) and the Menu Bar tab (the Desktop
/// Previews toggle itself), with no one place showing "what's granted right now" for the whole
/// app. This is that place; the other tabs still own their own deeper controls.
struct PermissionsSettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(
                    title: "Accessibility",
                    isTrusted: coordinator.accessibilityPermission.isTrusted,
                    explanation: "Required — switching, creating, and deleting desktops all go through this. Nexus can't do much of anything without it.",
                    onGrant: { coordinator.accessibilityPermission.requestPermission() },
                    onOpenSettings: { coordinator.accessibilityPermission.openSystemSettings() },
                    onRecheck: { coordinator.accessibilityPermission.refresh() }
                )
            } header: {
                Text("Required")
            }

            Section {
                PermissionStatusRow(
                    title: "Screen Recording",
                    isTrusted: coordinator.screenRecordingPermission.isTrusted,
                    explanation: "Optional — only used for the last-seen desktop previews in the quick switcher (Menu Bar tab → Desktop Previews). Everything else works without it.",
                    // Unlike Accessibility, macOS reads this once per launch and caches it for the
                    // life of the process — checking the box in System Settings while Nexus is
                    // already running won't change what it sees, and neither will "Recheck" here.
                    recheckNote: "Just granted this in System Settings? Quit and relaunch Nexus — this one only takes effect on the next launch, not live.",
                    onGrant: { coordinator.screenRecordingPermission.requestPermission() },
                    onOpenSettings: { coordinator.screenRecordingPermission.openSystemSettings() },
                    onRecheck: { coordinator.screenRecordingPermission.refresh() }
                )
            } header: {
                Text("Optional")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            coordinator.accessibilityPermission.refresh()
            coordinator.screenRecordingPermission.refresh()
        }
    }
}

/// One permission's status, explanation, and recovery actions. `CGRequestScreenCaptureAccess`
/// (and its Accessibility equivalent) only ever show the system prompt once per install — after a
/// decline, "Grant Access…" does nothing visibly, which is exactly the confusing-silent-failure
/// this dashboard exists to make legible. "Open System Settings…" is the real recovery path once
/// that's happened.
private struct PermissionStatusRow: View {
    let title: String
    let isTrusted: Bool
    let explanation: String
    /// Shown under the buttons only while not trusted — for permissions (Screen Recording) where
    /// macOS caches the grant for the life of the process, so neither System Settings nor
    /// "Recheck" can reflect a just-granted change without an actual relaunch. `nil` for
    /// permissions (Accessibility) that genuinely do update live.
    var recheckNote: String?
    let onGrant: () -> Void
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isTrusted ? Color.green : Color.orange)
                Text(title).font(.headline)
                Spacer()
                Text(isTrusted ? "Granted" : "Not Granted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isTrusted ? Color.green : Color.orange)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !isTrusted {
                HStack {
                    Button("Grant Access…", action: onGrant)
                    Button("Open System Settings…", action: onOpenSettings)
                    Button("Recheck", action: onRecheck)
                }
                if let recheckNote {
                    Text(recheckNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
