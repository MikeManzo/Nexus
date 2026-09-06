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

struct ExperimentalSettingsView: View {
    @AppStorage(AppDelegate.experimentalBackendKey) private var experimentalBackendEnabled = false
    @State private var diagnosticStatus: String?
    @State private var showsRestartHint = false
    @State private var pendingEnable = false

    var body: some View {
        Form {
            Section("Experimental Backend") {
                Text("An opt-in backend built on undocumented macOS internals (the private CGSCopyManagedDisplaySpaces / CGSManagedDisplaySetCurrentSpace API) for silent desktop switching on every desktop, not just ones with a system shortcut assigned. Creating and deleting desktops always go through the standard Accessibility path regardless of this setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Label("Confirmed broken as of this build", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                Text("Live testing surfaced a real bug, not a theoretical risk: switching between desktops through this backend caused windows from multiple desktops to consolidate onto one, confusing which app was on which desktop. Nothing was deleted, but this is not safe to use day-to-day. It's kept here, off by default, as a foundation for figuring out the correct call sequence Apple's own Mission Control performs (which this doesn't yet replicate) ; see docs/01-capability-research.md.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Enable experimental backend", isOn: Binding(
                    get: { experimentalBackendEnabled },
                    set: { newValue in
                        if newValue {
                            pendingEnable = true
                        } else {
                            experimentalBackendEnabled = false
                            showsRestartHint = true
                        }
                    }
                ))
                .confirmationDialog(
                    "Enable the experimental backend?",
                    isPresented: $pendingEnable,
                    titleVisibility: .visible
                ) {
                    Button("Enable Anyway", role: .destructive) {
                        experimentalBackendEnabled = true
                        showsRestartHint = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This has been observed to consolidate windows from multiple desktops onto one. Only enable this if you're helping investigate the underlying bug.")
                }

                if showsRestartHint {
                    HStack {
                        Text("Restart Nexus to apply this change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Quit Nexus") { NSApp.terminate(nil) }
                            .controlSize(.small)
                    }
                }
            }

            Section("Research Diagnostic") {
                Text("Read-only: dumps what the private Spaces API actually returns on this Mac. Cannot affect your desktops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Run Private API Diagnostic") {
                    runDiagnostic()
                }

                if let diagnosticStatus {
                    Text(diagnosticStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runDiagnostic() {
        do {
            let result = try PrivateSpacesDiagnostic.run()
            diagnosticStatus = "Saved to \(result.fileURL.path)"
            NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
        } catch {
            diagnosticStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
