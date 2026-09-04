import SwiftUI

/// The fixed set of colors offered when customizing a desktop's accent — a curated palette
/// rather than a full color well, so every desktop's color stays legible against both the
/// popover's and Space Manager's backgrounds in light and dark mode.
enum AccentPalette {
    static let options: [String] = [
        "#5B6DF0", // indigo — app default
        "#FF6A38", // orange — app icon's accent
        "#33B27A", // green
        "#3AAEE0", // sky
        "#C24CE0", // magenta
        "#E0475C", // coral red
        "#D4A017", // amber
        "#6B7280", // neutral gray
    ]
}

extension Color {
    /// Parses a `#RRGGBB` string. Falls back to the app's accent color for anything malformed.
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7,
              let value = Int(hex.dropFirst(), radix: 16) else {
            self = .accentColor
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension DesktopSpace {
    var accentColor: Color { Color(hex: accentColorHex) }
}
