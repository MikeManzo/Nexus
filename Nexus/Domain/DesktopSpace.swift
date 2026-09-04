import Foundation

/// A single macOS desktop/Space, as understood by Nexus.
///
/// `systemLabel` is whatever generic label the backend observed ("Desktop 3"); macOS has no
/// concept of a user-assigned Space name at all, so `customName` is always Nexus-owned metadata
/// layered on top, never a value read from or written to the system. See
/// `docs/01-capability-research.md` for why.
struct DesktopSpace: Identifiable, Hashable, Sendable {
    var id: SpaceIdentifier { identifier }

    let identifier: SpaceIdentifier
    var order: Int
    var isActive: Bool
    var displayID: UInt32?
    var systemLabel: String?
    var customName: String?
    var symbolName: String?

    var displayName: String {
        customName ?? systemLabel ?? "Desktop \(order + 1)"
    }
}
