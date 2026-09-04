import AppKit
import SwiftUI

/// Owns the single floating panel centered in the menu bar — the "quick switcher" the user
/// hovers to preview and switch desktops. Opt-in (Settings → Menu Bar → "Show quick switcher in
/// menu bar"), off by default. There is exactly one window here: it grows in place on hover
/// (`LandingZoneView`) rather than triggering a separate panel elsewhere, so there is no gap
/// between where the cursor is and what it needs to reach — an earlier design (hover the status
/// item on the right, a preview appears centered on screen) didn't work as an interaction:
/// verified live that crossing real screen distance with nothing under the cursor breaks a hover
/// gesture, no matter how the dismiss-debounce is tuned.
@MainActor
final class MenuBarLandingZoneController {
    static let enabledDefaultsKey = "menuBarQuickSwitcherEnabled"

    private var panel: NSPanel?
    private var hostingController: NSHostingController<LandingZoneView>?
    private let coordinator: AppCoordinator
    private var lastSize = NSSize(width: 110, height: 50)
    private var missionControlObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var isEnabledByUser = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        observeMissionControl()
        observeEnabledSetting()
        applyEnabledState()
    }

    private func observeEnabledSetting() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyEnabledState() }
        }
    }

    private func applyEnabledState() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        guard enabled != isEnabledByUser else { return }
        isEnabledByUser = enabled
        if enabled {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let panel = currentPanel()
        position(panel, size: lastSize)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    /// Hides for the brief window Mission Control is presented, and restores right after — see
    /// `Notification.Name.missionControlWillPresent`'s doc comment for why this exists at all.
    private func observeMissionControl() {
        let willPresent = NotificationCenter.default.addObserver(
            forName: .missionControlWillPresent, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.orderOut(nil) }
        }
        let didDismiss = NotificationCenter.default.addObserver(
            forName: .missionControlDidDismiss, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabledByUser else { return }
                self.panel?.orderFrontRegardless()
            }
        }
        missionControlObservers = [willPresent, didDismiss]
    }

    private func currentPanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingController(
            rootView: LandingZoneView(coordinator: coordinator, onSizeChange: { [weak self] in
                self?.refreshSize()
            })
        )
        hostingController = hosting

        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    /// Called by `LandingZoneView` whenever it expands or collapses. SwiftUI's layout pass hasn't
    /// necessarily caught up on the same run loop tick, so this re-measures twice: once almost
    /// immediately, once again after the expand/collapse animation has had time to settle.
    private func refreshSize() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.applyRefinedSize()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.applyRefinedSize()
        }
    }

    private func applyRefinedSize() {
        guard let panel, let hostingController else { return }
        let size = hostingController.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        lastSize = size
        position(panel, size: size)
    }

    /// Pins the *top* edge to the very top of the screen — flush with the menu bar's own top
    /// edge, not sitting below it — and grows downward from there, centered horizontally. The
    /// collapsed pill's height is close to the menu bar's own thickness, so it reads as occupying
    /// the menu bar row itself; the expanded grid then hangs below it like a real dropdown would.
    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.screens.first else { return }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
