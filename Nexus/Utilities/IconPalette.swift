//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

/// The fixed set of SF Symbols offered when customizing a desktop's icon — a curated palette
/// rather than a full symbol picker, matching `AccentPalette`'s own reasoning: a bounded, legible
/// set beats an overwhelming searchable one for something this glanceable. `nil` (no selection)
/// means "show the desktop's number instead," the existing default look.
enum IconPalette {
    static let options: [String] = [
        "briefcase.fill",
        "terminal.fill",
        "chevron.left.forwardslash.chevron.right",
        "paintbrush.pointed.fill",
        "gamecontroller.fill",
        "message.fill",
        "music.note",
        "film.fill",
        "book.fill",
        "chart.bar.fill",
        "cart.fill",
        "graduationcap.fill",
    ]
}
