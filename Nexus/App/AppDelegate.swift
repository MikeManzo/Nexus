import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let experimentalBackendKey = "experimentalBackendEnabled"

    let coordinator = AppCoordinator(
        spaceManager: AppDelegate.makeSpaceManager(),
        updateManager: SparkleUpdateManager(),
        metadataStore: SpaceMetadataStore(),
        accessibilityPermission: AccessibilityPermissionManager(),
        missionControlDiagnostics: MissionControlAccessibilityService()
    )

    private var statusItemController: StatusItemController?
    private var spaceObserver: SystemSpaceObserver?
    private var onboardingWindowController: OnboardingWindowController?

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// Chosen once, at launch — swapping backends live isn't worth the added risk for a toggle
    /// this rarely flipped, so Settings → Experimental asks for a restart instead.
    private static func makeSpaceManager() -> SpaceManaging {
        if UserDefaults.standard.bool(forKey: experimentalBackendKey) {
            Log.spaceManager.info("Using Tier 3 experimental backend (private Spaces API)")
            return ExperimentalSpaceManager()
        }
        return AccessibilitySpaceManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = StatusItemController(coordinator: coordinator)
        statusItemController = statusItem
        spaceObserver = SystemSpaceObserver()
        coordinator.hotkeyCoordinator = HotkeyCoordinator(
            appCoordinator: coordinator,
            openNexus: { [weak statusItem] in statusItem?.togglePopoverFromHotkey() }
        )
        Log.app.info("Nexus launched")

        if !UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey) {
            presentOnboarding()
        }
    }

    /// Also reachable from Settings → General's "Show Welcome Screen…" button.
    func presentOnboarding() {
        let controller = OnboardingWindowController(coordinator: coordinator) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
        }
        onboardingWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    // Without this, SwiftUI quits the whole app when its last open window (Settings, or Manage
    // Desktops) closes — the right default for a document-style app, but wrong here: the menu bar
    // status item is Nexus's real lifetime anchor, not any window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
