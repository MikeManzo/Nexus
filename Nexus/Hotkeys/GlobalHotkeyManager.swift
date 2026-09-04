//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Carbon.HIToolbox
import Foundation

/// Wraps Carbon's `RegisterEventHotKey`/`UnregisterEventHotKey`. This is still the standard
/// mechanism real macOS utilities use for true global hotkeys — confirmed present and fully
/// declared in the current SDK (`CarbonEvents.h`) — and it has two real advantages over the
/// SwiftUI-native alternative, `NSEvent.addGlobalMonitorForEvents`: it requires no Accessibility
/// or Input Monitoring permission, and it can be told to consume the keystroke (a monitor can
/// only observe, never block, so the key would also reach whatever app is frontmost).
///
/// A single `InstallEventHandler` is installed once, on the application's own Carbon event
/// target; individual registrations are looked up by `EventHotKeyID.id` when `kEventHotKeyPressed`
/// fires and dispatched back to the handler closure registered for that id.
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    /// Four-character signature Carbon requires per hot key, to disambiguate registrants sharing
    /// the same event target. Arbitrary but stable — "nxus".
    private static let signature: OSType = {
        "nxus".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private init() {
        installEventHandler()
    }

    /// Registers a global hot key. Returns `nil` (and logs) if Carbon refuses the registration —
    /// e.g. another *exclusive* registrant already owns that combination.
    @discardableResult
    func register(_ shortcut: KeyboardShortcut, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            Log.hotkeys.error("Failed to register \(shortcut.displayString, privacy: .public): OSStatus \(status, privacy: .public)")
            return nil
        }

        handlers[id] = handler
        hotKeyRefs[id] = ref
        Log.hotkeys.info("Registered \(shortcut.displayString, privacy: .public) as id \(id, privacy: .public)")
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        for id in Array(hotKeyRefs.keys) { unregister(id) }
    }

    fileprivate func invokeHandler(for id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            Log.hotkeys.error("Failed to install Carbon hot key event handler: OSStatus \(status, privacy: .public)")
        }
    }
}

/// Top-level, capture-free function so it can convert to the C function pointer
/// `InstallEventHandler` requires. Carbon guarantees this fires on the main run loop, so hopping
/// to the main actor via `Task` (rather than being able to call the manager directly, which the
/// type system can't prove is safe from a `nonisolated` C callback) is safe and immediate.
private func hotKeyEventHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    Task { @MainActor in
        GlobalHotkeyManager.shared.invokeHandler(for: id)
    }
    return noErr
}
