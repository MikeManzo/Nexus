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
