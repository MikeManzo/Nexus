import SwiftUI

/// A row of preset color swatches — not a full color well, so every desktop's accent stays
/// legible against both the popover's and Space Manager's backgrounds in light and dark mode.
struct AccentColorPicker: View {
    @Binding var selectedHex: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentPalette.options, id: \.self) { hex in
                Button {
                    selectedHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(selectedHex == hex ? 0.8 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accent color \(hex)")
                .accessibilityAddTraits(selectedHex == hex ? [.isSelected] : [])
            }
        }
    }
}
