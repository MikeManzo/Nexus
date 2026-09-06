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

/// A single at-a-glance dashboard for every system permission Nexus can use, plus the
/// Accessibility diagnostic tools that used to live on their own separate tab — merged here since
/// that tab was otherwise just duplicating this one's Accessibility status row, and the
/// diagnostics themselves are niche/developer-facing enough not to need their own top-level home.
struct PermissionsSettingsView: View {
    let coordinator: AppCoordinator

    @State private var connectionTestStatus: String?
    @State private var diagnosticStatus: String?
    @State private var isRunningDiagnostic = false

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(
                    title: "Accessibility",
                    isTrusted: coordinator.accessibilityPermission.isTrusted,
                    explanation: "Required — switching, creating, and deleting desktops all go through this. Nexus can't do much of anything without it. It does not log keystrokes, read other apps' content, or send anything over the network.",
                    onGrant: { coordinator.accessibilityPermission.requestPermission() },
                    onOpenSettings: { coordinator.accessibilityPermission.openSystemSettings() },
                    onRecheck: { coordinator.accessibilityPermission.refresh() }
                )
            } header: {
                Text("Required")
            }

            Section("Accessibility Diagnostics") {
                Button("Test Accessibility Connection") {
                    runConnectionTest()
                }
                .disabled(!coordinator.accessibilityPermission.isTrusted)
                if let connectionTestStatus {
                    Text(connectionTestStatus).font(.caption).foregroundStyle(.secondary)
                }

                Text("Briefly opens Mission Control to capture its accessibility structure — this is groundwork for building real desktop switching, not something you need to run day to day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(isRunningDiagnostic ? "Scanning…" : "Run Diagnostic Scan") {
                        runDiagnostic()
                    }
                    .disabled(!coordinator.accessibilityPermission.isTrusted || isRunningDiagnostic)

                    Button(isRunningDiagnostic ? "Scanning…" : "Run Detailed Spaces Scan") {
                        runDetailedDiagnostic()
                    }
                    .disabled(!coordinator.accessibilityPermission.isTrusted || isRunningDiagnostic)
                }

                if let diagnosticStatus {
                    Text(diagnosticStatus).font(.caption).foregroundStyle(.secondary)
                }
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

    private func runConnectionTest() {
        do {
            let ok = try coordinator.missionControlDiagnostics.testConnection()
            connectionTestStatus = ok ? "Connected — Nexus can read Dock.app's accessibility tree." : "Unexpected response from Dock.app."
        } catch {
            connectionTestStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private func runDiagnostic() {
        isRunningDiagnostic = true
        diagnosticStatus = nil
        Task {
            do {
                let result = try await coordinator.missionControlDiagnostics.dumpDockAccessibilityTree()
                diagnosticStatus = "Captured \(result.elementCountAtRest) elements at rest, \(result.elementCountWhilePresented) while presented.\nSaved to \(result.fileURL.path)"
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            } catch {
                diagnosticStatus = "Failed: \(error.localizedDescription)"
            }
            isRunningDiagnostic = false
        }
    }

    private func runDetailedDiagnostic() {
        isRunningDiagnostic = true
        diagnosticStatus = nil
        Task {
            do {
                let result = try await coordinator.missionControlDiagnostics.dumpSpacesBarDetail()
                diagnosticStatus = "Detailed scan saved to \(result.fileURL.path)"
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            } catch {
                diagnosticStatus = "Failed: \(error.localizedDescription)"
            }
            isRunningDiagnostic = false
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
