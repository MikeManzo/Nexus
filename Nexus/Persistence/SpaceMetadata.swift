import Foundation

/// Nexus-owned metadata for a Space, keyed by `SpaceIdentifier.stableKey`. Deliberately separate
/// from `DesktopSpace` (system-derived) so persistence code never accidentally treats a
/// system-observed value as something Nexus is free to overwrite, or vice versa.
struct SpaceMetadata: Codable, Sendable, Equatable {
    var stableKey: UUID
    var customName: String?
    var symbolName: String?
    var accentColorHex: String?
    var createdAt: Date
}
