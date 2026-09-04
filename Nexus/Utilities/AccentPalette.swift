import AppKit
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

extension NSColor {
    /// Parses a `#RRGGBB` string. Falls back to the app's accent color for anything malformed.
    /// `StatusItemController` needs this AppKit-side twin of `Color(hex:)` since a status item's
    /// image is an `NSImage`, not SwiftUI.
    convenience init(hex: String?) {
        // Falls back to the app's default accent (AccentPalette's own first entry, "#5B6DF0")
        // rather than chaining through a second failable initializer.
        let fallback = "5B6DF0"
        let digits = (hex?.hasPrefix("#") == true && hex?.count == 7) ? String(hex!.dropFirst()) : fallback
        let value = Int(digits, radix: 16) ?? Int(fallback, radix: 16)!
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// A small filled circle, for the menu bar status item's "Space Name" display mode — not a
    /// template image, since it needs to keep its literal color rather than being tinted
    /// monochrome the way SF Symbol status item icons are.
    static func dotImage(color: NSColor, diameter: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
