//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

/// A row of preset SF Symbol swatches, plus a leading "None" option that clears the selection —
/// mirrors `AccentColorPicker`'s layout and selection-ring treatment so the two read as one
/// consistent customization control, not two different widgets bolted together.
struct IconPicker: View {
    @Binding var selectedSymbolName: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                swatch(symbolName: nil, accessibilityLabel: "No icon")

                ForEach(IconPalette.options, id: \.self) { symbolName in
                    swatch(symbolName: symbolName, accessibilityLabel: symbolName)
                }
            }
        }
    }

    private func swatch(symbolName: String?, accessibilityLabel: String) -> some View {
        let isSelected = selectedSymbolName == symbolName
        return Button {
            selectedSymbolName = symbolName
        } label: {
            Group {
                if let symbolName {
                    Image(systemName: symbolName)
                } else {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .background(Color.primary.opacity(0.06), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                    .padding(-3)
            )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
