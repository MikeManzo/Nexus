//
// This file is part of Nexus.
//
// Nexus is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import SwiftUI

/// Click to record the next key combination (must include at least one modifier). Escape cancels
/// without changing anything. Uses a local event monitor scoped to exactly the recording window ;
/// it never touches global state, unlike `GlobalHotkeyManager`.
struct ShortcutRecorderView: View {
    let currentShortcut: KeyboardShortcut
    let onCapture: (KeyboardShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press keys…" : currentShortcut.displayString)
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            let modifiers = KeyboardShortcut.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return nil } // require at least one modifier
            onCapture(KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
