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

/// The landing zone's content: a small pill showing the active desktop, which grows in place —
/// same window, same view, no travel distance — to reveal the tile grid on hover. Collapses back
/// after a short debounce once the cursor truly leaves (the *current*, possibly-expanded) bounds.
struct LandingZoneView: View {
    let coordinator: AppCoordinator
    var onSizeChange: () -> Void

    @State private var isExpanded = false
    @State private var collapseWorkItem: DispatchWorkItem?

    /// The real, current system menu bar height for the primary screen — not a guessed constant.
    /// `NSStatusBar.system.thickness` (the nominal status-item content height) is *not* this: on
    /// this very Mac it reports 22pt while the actual menu bar band is 31pt, which is exactly
    /// enough to make a pill sized to `.thickness` look pinned to the top of the row instead of
    /// centered in it — confirmed by directly comparing the two live. The gap between a screen's
    /// full frame and its `visibleFrame` (which macOS itself carves the menu bar out of) is the
    /// real number.
    private static var menuBarHeight: CGFloat {
        guard let screen = NSScreen.screens.first else { return NSStatusBar.system.thickness }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    var body: some View {
        // `.center`, not `.leading` — the pill is narrower than the grid, so once expanded widens
        // the panel to the grid's 260pt width, a leading alignment pins the desktop name to the
        // left edge instead of centering it in the now-wider window.
        VStack(alignment: .center, spacing: 0) {
            pill
                .padding(.horizontal, 12)
            if isExpanded {
                grid
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
            }
        }
        // Collapsed height is exactly the menu bar's own thickness (see `menuBarHeight`), so it
        // reads as occupying the menu bar row itself rather than floating below or above it.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: isExpanded ? 16 : 10))
        .onHover { hovering in
            if hovering {
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                isExpanded = true
            } else {
                let item = DispatchWorkItem { isExpanded = false }
                collapseWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
            }
        }
        .onChange(of: isExpanded) { _, _ in onSizeChange() }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if let active = coordinator.activeSpace {
                Circle().fill(active.accentColor).frame(width: 7, height: 7)
                Text(active.displayName).font(.subheadline.weight(.semibold))
            } else {
                Text("Nexus").font(.subheadline.weight(.semibold))
            }
        }
        .frame(minWidth: 90)
        .frame(height: Self.menuBarHeight)
    }

    private var grid: some View {
        Group {
            if coordinator.spaces.isEmpty {
                Text(coordinator.accessibilityPermission.isTrusted ? "No desktops found yet." : "Grant Accessibility access in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 66), spacing: 10)], spacing: 12) {
                        ForEach(coordinator.spaces) { space in
                            DesktopTile(
                                space: space,
                                isBusy: coordinator.isBusy,
                                thumbnail: coordinator.thumbnailCache.thumbnail(for: space)
                            ) {
                                Task { await coordinator.activate(space) }
                            }
                        }
                    }
                }
                .frame(width: 260)
            }
        }
    }
}
