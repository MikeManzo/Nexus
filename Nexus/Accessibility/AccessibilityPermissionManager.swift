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
import ApplicationServices
import Observation

/// Wraps `AXIsProcessTrusted`/`AXIsProcessTrustedWithOptions`. Nothing here polls ; permission is
/// re-checked on `refresh()`, called when the app becomes active again (the plausible moment a
/// user returns from System Settings), never on a timer.
@MainActor
@Observable
final class AccessibilityPermissionManager {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        let wasTrusted = isTrusted
        isTrusted = AXIsProcessTrusted()
        if isTrusted != wasTrusted {
            Log.accessibility.info("Accessibility trust changed: \(self.isTrusted, privacy: .public)")
        }
    }

    /// Triggers the system's own permission prompt if not yet trusted. Does not loop or re-prompt
    /// on its own ; call this from an explicit user action (a button), never automatically.
    func requestPermission() {
        // Using the raw key name rather than the `kAXTrustedCheckOptionPrompt` C global sidesteps
        // a Swift 6 strict-concurrency diagnostic on that global's `Unmanaged<CFString>` type;
        // the key name itself is a stable, documented part of the ApplicationServices API.
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        Log.accessibility.info("Accessibility prompt requested, trusted=\(self.isTrusted, privacy: .public)")
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
