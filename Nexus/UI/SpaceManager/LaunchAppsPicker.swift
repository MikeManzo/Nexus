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
import UniformTypeIdentifiers

/// Apps to launch (if not already running) whenever you switch to this desktop — stores only
/// bundle identifiers (an app's install location can move; its bundle ID doesn't), resolving each
/// one's display name and icon fresh at render time via `NSWorkspace` rather than caching them.
struct LaunchAppsPicker: View {
    @Binding var bundleIDs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bundleIDs, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    resolvedIcon(for: bundleID)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(resolvedName(for: bundleID))
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        bundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(resolvedName(for: bundleID)) from this desktop's launch list")
                    .accessibilityLabel("Remove \(resolvedName(for: bundleID))")
                }
            }

            Button("Add App…", action: addApp)
                .buttonStyle(.link)
                .help("Choose an app to launch when you arrive at this desktop")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !bundleIDs.contains(bundleID)
        else {
            return
        }
        bundleIDs.append(bundleID)
    }

    private func resolvedName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func resolvedIcon(for bundleID: String) -> Image {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return Image(systemName: "app.dashed")
        }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }
}
