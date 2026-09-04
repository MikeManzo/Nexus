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
import CoreGraphics
import Observation

/// Wraps `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess` — the Screen Recording
/// counterpart to `AccessibilityPermissionManager`. Only needed for `DesktopThumbnailCache`'s
/// cached desktop previews; nothing else in Nexus touches screen content. Like its Accessibility
/// counterpart, this never prompts on its own — only from an explicit user action.
@MainActor
@Observable
final class ScreenRecordingPermissionManager {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = CGPreflightScreenCaptureAccess()
    }

    func refresh() {
        let wasTrusted = isTrusted
        isTrusted = CGPreflightScreenCaptureAccess()
        if isTrusted != wasTrusted {
            Log.thumbnails.info("Screen Recording trust changed: \(self.isTrusted, privacy: .public)")
        }
    }

    /// Triggers the system's own permission prompt if not yet trusted. Call this from an explicit
    /// user action (a button), never automatically.
    func requestPermission() {
        isTrusted = CGRequestScreenCaptureAccess()
        Log.thumbnails.info("Screen Recording prompt requested, trusted=\(self.isTrusted, privacy: .public)")
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
