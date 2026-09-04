//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import CoreGraphics
import Foundation

/// Resolves private SkyLight/CoreGraphics Spaces symbols via `dlopen`/`dlsym` at runtime — never
/// linked at build time, so a failed lookup degrades to "unavailable" rather than blocking a
/// build or crashing. These are undocumented, unsupported by Apple, and have broken across macOS
/// updates before (`docs/01-capability-research.md` §2, §11 — yabai's space-switching broke on
/// both the Sonoma 14.0 and Sequoia 15.1.1/15.4 updates). This is the foundation of the opt-in
/// Tier 3 `ExperimentalSpaceManager`; nothing here is used unless the user explicitly enables it.
///
/// Signatures verified against the community-maintained, MIT-licensed `NUIKit/CGSInternal`
/// headers (`CGSConnectionID` = `int`, `CGSSpaceID` = `size_t`) — not guessed. The *dictionary
/// structure* `CGSCopyManagedDisplaySpaces` returns is not declared anywhere (it's a runtime
/// value, not a C type), so it is not assumed here; `PrivateSpacesDiagnostic` dumps it for
/// inspection before any parsing logic gets written against it.
enum PrivateSpacesAPI {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt
    private typealias ManagedDisplaySetCurrentSpaceFn = @convention(c) (Int32, CFString, UInt) -> Void
    private typealias SpaceCreateFn = @convention(c) (Int32, UnsafeRawPointer?, CFDictionary?) -> UInt
    private typealias SpaceDestroyFn = @convention(c) (Int32, UInt) -> Void

    // Immutable after first access; dlopen/dlsym results are plain C pointers with no
    // Sendable annotation in this SDK, but are safe to share once resolved.
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }()

    static var isAvailable: Bool { handle != nil && mainConnectionID != nil && copyManagedDisplaySpaces != nil }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else {
            Log.spaceManager.error("Private Spaces API: symbol \(name, privacy: .public) not found")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let mainConnectionID = symbol("CGSMainConnectionID", as: MainConnectionIDFn.self)
    private static let copyManagedDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self)
    private static let getActiveSpace = symbol("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let managedDisplaySetCurrentSpace = symbol("CGSManagedDisplaySetCurrentSpace", as: ManagedDisplaySetCurrentSpaceFn.self)
    private static let spaceCreateFn = symbol("CGSSpaceCreate", as: SpaceCreateFn.self)
    private static let spaceDestroyFn = symbol("CGSSpaceDestroy", as: SpaceDestroyFn.self)

    static func connectionID() -> Int32? {
        mainConnectionID?()
    }

    /// Array of per-display dictionaries; structure not yet parsed here — see
    /// `PrivateSpacesDiagnostic`.
    static func managedDisplaySpaces(cid: Int32) -> CFArray? {
        copyManagedDisplaySpaces?(cid)?.takeRetainedValue()
    }

    static func activeSpaceID(cid: Int32) -> UInt? {
        getActiveSpace?(cid)
    }

    static func setCurrentSpace(cid: Int32, display: CFString, spaceID: UInt) {
        managedDisplaySetCurrentSpace?(cid, display, spaceID)
    }

    static func createSpace(cid: Int32, options: CFDictionary) -> UInt? {
        spaceCreateFn?(cid, nil, options)
    }

    static func destroySpace(cid: Int32, spaceID: UInt) {
        spaceDestroyFn?(cid, spaceID)
    }
}
