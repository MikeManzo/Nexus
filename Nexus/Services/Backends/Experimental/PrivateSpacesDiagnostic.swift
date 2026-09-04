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

/// Read-only inspection of what `CGSCopyManagedDisplaySpaces` actually returns on this machine —
/// no mutation, cannot affect any real desktop. Its dictionary structure isn't declared in any
/// header (it's a runtime value), so this dumps the real thing via `CFCopyDescription` instead of
/// writing parsing logic against assumed key names.
enum PrivateSpacesDiagnostic {
    struct Result {
        let fileURL: URL
        let text: String
    }

    enum DiagnosticError: Error, LocalizedError {
        case apiUnavailable

        var errorDescription: String? {
            "Private Spaces API symbols could not be resolved (dlopen/dlsym failed)."
        }
    }

    @MainActor
    static func run() throws -> Result {
        guard PrivateSpacesAPI.isAvailable, let cid = PrivateSpacesAPI.connectionID() else {
            throw DiagnosticError.apiUnavailable
        }

        var output = "Nexus private Spaces API diagnostic\nCaptured: \(Date().formatted(.iso8601))\n\n"
        output += "CGSMainConnectionID() = \(cid)\n\n"

        if let activeID = PrivateSpacesAPI.activeSpaceID(cid: cid) {
            output += "CGSGetActiveSpace(cid) = \(activeID)\n\n"
        } else {
            output += "CGSGetActiveSpace(cid) = <symbol unavailable>\n\n"
        }

        if let spaces = PrivateSpacesAPI.managedDisplaySpaces(cid: cid) {
            output += "CGSCopyManagedDisplaySpaces(cid) full structure:\n"
            output += CFCopyDescription(spaces) as String
        } else {
            output += "CGSCopyManagedDisplaySpaces(cid) = nil\n"
        }

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nexus", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("private-spaces-dump-\(Int(Date().timeIntervalSince1970)).txt")
        try output.write(to: fileURL, atomically: true, encoding: .utf8)

        Log.spaceManager.info("Wrote private Spaces API diagnostic to \(fileURL.path, privacy: .public)")
        return Result(fileURL: fileURL, text: output)
    }
}
