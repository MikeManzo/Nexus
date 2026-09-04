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

/// Errors surfaced by any `SpaceManaging` backend. Kept backend-agnostic so the UI never needs to
/// know whether an operation failed because Accessibility permission is missing, the experimental
/// backend is unavailable, or Mission Control simply didn't respond in time.
enum SpaceError: Error, LocalizedError, Identifiable, Sendable {
    case accessibilityPermissionDenied
    case missionControlUnavailable
    case spaceNotFound
    case spaceChangedDuringOperation
    case cannotDeleteLastSpace
    case operationTimedOut
    case unsupportedOnThisSystem
    case experimentalBackendUnavailable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            "Nexus needs Accessibility access to manage desktops. Open Settings → Accessibility to grant it."
        case .missionControlUnavailable:
            "Mission Control isn't responding right now. Try again in a moment."
        case .spaceNotFound:
            "That desktop no longer exists."
        case .spaceChangedDuringOperation:
            "Your desktops changed while Nexus was working. Refreshing…"
        case .cannotDeleteLastSpace:
            "You can't delete your only remaining desktop."
        case .operationTimedOut:
            "That took too long and was cancelled."
        case .unsupportedOnThisSystem:
            "This action isn't supported on this version of macOS."
        case .experimentalBackendUnavailable:
            "The experimental backend isn't available. Falling back to standard mode."
        case .underlying(let message):
            message
        }
    }

    var id: String { errorDescription ?? String(describing: self) }
}
