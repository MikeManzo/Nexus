//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import OSLog

/// Central OSLog categories. Use the matching category for whatever subsystem you're touching —
/// see `docs/01-capability-research.md` §"Logging" for what belongs where.
enum Log {
    private static let subsystem = "com.nexusapp.Nexus"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let spaceManager = Logger(subsystem: subsystem, category: "SpaceManager")
    static let accessibility = Logger(subsystem: subsystem, category: "Accessibility")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let hotkeys = Logger(subsystem: subsystem, category: "Hotkeys")
    static let updates = Logger(subsystem: subsystem, category: "Updates")
    static let sparkle = Logger(subsystem: subsystem, category: "Sparkle")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let thumbnails = Logger(subsystem: subsystem, category: "Thumbnails")
}
