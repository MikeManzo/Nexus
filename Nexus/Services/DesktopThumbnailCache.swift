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
import ScreenCaptureKit

/// Caches a "last seen" screenshot per desktop, keyed by `SpaceIdentifier.stableKey`. This is
/// deliberately not a live preview: ScreenCaptureKit only exposes content that's actually
/// on-screen right now (`SCWindow.isOnScreen` — confirmed in its own header), and an inactive
/// Space by definition isn't composited anywhere, so there is no public API that can return real
/// pixel content for a desktop you aren't currently looking at. See
/// `docs/01-capability-research.md` for the same capability-boundary pattern applied elsewhere
/// (Space rename, Space enumeration).
///
/// `AppCoordinator.activate` captures the desktop being left just before switching away from it,
/// and the destination desktop again just after arriving — so every tile's thumbnail is exactly
/// as fresh as the last time you were looking at that desktop, never fresher.
///
/// Requires Screen Recording permission (`ScreenRecordingPermissionManager`). Capturing silently
/// no-ops without it — this is a cosmetic enhancement, never a blocking requirement, and never
/// prompts on its own.
@MainActor
@Observable
final class DesktopThumbnailCache {
    /// Settings → Menu Bar → "Show last-seen previews in quick switcher" — off by default, since
    /// turning it on means asking for Screen Recording access. `AppCoordinator` checks this before
    /// ever calling `captureCurrentScreen`, so nothing here captures anything until the user opts in.
    static let enabledDefaultsKey = "desktopPreviewsEnabled"

    private static let thumbnailWidth = 240

    private(set) var thumbnails: [UUID: NSImage] = [:]

    func thumbnail(for space: DesktopSpace) -> NSImage? {
        thumbnails[space.identifier.stableKey]
    }

    func captureCurrentScreen(for space: DesktopSpace) async {
        guard CGPreflightScreenCaptureAccess() else {
            Log.thumbnails.notice("Skipping capture for \(space.displayName, privacy: .public): Screen Recording access not granted")
            return
        }

        let mainDisplayID = CGMainDisplayID()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            Log.thumbnails.error("SCShareableContent.current failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
            Log.thumbnails.error("No SCDisplay matched main display ID \(mainDisplayID, privacy: .public) among \(content.displays.count, privacy: .public) reported displays")
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Self.thumbnailWidth
        config.height = max(1, Int(CGFloat(Self.thumbnailWidth) * CGFloat(display.height) / CGFloat(display.width)))
        config.showsCursor = false

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            Log.thumbnails.error("captureImage failed for \(space.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: config.width, height: config.height))
        thumbnails[space.identifier.stableKey] = image
        Log.thumbnails.info("Cached thumbnail for \(space.displayName, privacy: .public)")
    }
}
