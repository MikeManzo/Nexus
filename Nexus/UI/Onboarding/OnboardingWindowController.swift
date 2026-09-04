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

/// A plain `NSWindow` rather than a SwiftUI `Window` scene: it needs to be shown from
/// `AppDelegate` at launch, before any SwiftUI view exists to supply an `openWindow` environment
/// action — the same reason `StatusItemController` hosts the popover's SwiftUI content in an
/// `NSHostingController` instead.
@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init(coordinator: AppCoordinator, onFinish: @escaping () -> Void) {
        let hosting = NSHostingController(rootView: OnboardingView(coordinator: coordinator, onFinish: onFinish))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Nexus"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
