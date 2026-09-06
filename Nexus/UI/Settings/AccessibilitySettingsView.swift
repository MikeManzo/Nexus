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

struct AccessibilitySettingsView: View {
    let coordinator: AppCoordinator

    @State private var connectionTestStatus: String?
    @State private var diagnosticStatus: String?
    @State private var isRunningDiagnostic = false

    var body: some View {
        Form {
            Section("Permission") {
                statusRow

                Text("Nexus uses Accessibility access to read and control Mission Control ; switching, creating, and deleting desktops. It does not log keystrokes, read other apps' content, or send anything over the network. Renaming and the rest of the app work without this permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    if !coordinator.accessibilityPermission.isTrusted {
                        Button("Grant Access…") {
                            coordinator.accessibilityPermission.requestPermission()
                        }
                    }
                    Button("Open System Settings…") {
                        coordinator.accessibilityPermission.openSystemSettings()
                    }
                    Button("Recheck Permission") {
                        coordinator.accessibilityPermission.refresh()
                    }
                }
            }

            Section("Connection") {
                Button("Test Accessibility Connection") {
                    runConnectionTest()
                }
                .disabled(!coordinator.accessibilityPermission.isTrusted)
                if let connectionTestStatus {
                    Text(connectionTestStatus).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Developer Diagnostics") {
                Text("Briefly opens Mission Control to capture its accessibility structure ; this is groundwork for building real desktop switching, not something you need to run day to day.")
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
        }
        .formStyle(.grouped)
        .onAppear { coordinator.accessibilityPermission.refresh() }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.accessibilityPermission.isTrusted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(coordinator.accessibilityPermission.isTrusted ? "Accessibility access granted" : "Accessibility access not granted")
                .font(.headline)
        }
    }

    private func runConnectionTest() {
        do {
            let ok = try coordinator.missionControlDiagnostics.testConnection()
            connectionTestStatus = ok ? "Connected ; Nexus can read Dock.app's accessibility tree." : "Unexpected response from Dock.app."
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
