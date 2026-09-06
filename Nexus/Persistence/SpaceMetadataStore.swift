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

protocol SpaceMetadataStoring: Sendable {
    func metadata(for key: UUID) async -> SpaceMetadata?
    func allMetadata() async -> [UUID: SpaceMetadata]
    func setCustomName(_ name: String?, for key: UUID) async
    func setAccentColor(_ hex: String?, for key: UUID) async
    func setSymbolName(_ symbolName: String?, for key: UUID) async
    func setLaunchAppBundleIDs(_ bundleIDs: [String], for key: UUID) async
    func setShortcut(_ shortcut: KeyboardShortcut?, for key: UUID) async
    func removeMetadata(for key: UUID) async
}

/// JSON-file-backed metadata store, isolated as an actor so concurrent reads/writes from the
/// popover and the Space Manager window can never race. Not tied to any particular
/// `SpaceManaging` backend ; it only ever sees `stableKey`, which is generated locally.
actor SpaceMetadataStore: SpaceMetadataStoring {
    private var storage: [UUID: SpaceMetadata]
    private let fileURL: URL

    init(fileURL: URL = SpaceMetadataStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.storage = Self.loadFromDisk(fileURL)
    }

    func metadata(for key: UUID) -> SpaceMetadata? {
        storage[key]
    }

    func allMetadata() -> [UUID: SpaceMetadata] {
        storage
    }

    func setCustomName(_ name: String?, for key: UUID) {
        var entry = blankEntry(for: key)
        entry.customName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : name
        storage[key] = entry
        persist()
        Log.persistence.info("Updated metadata for space \(key.uuidString, privacy: .public)")
    }

    func setAccentColor(_ hex: String?, for key: UUID) {
        var entry = blankEntry(for: key)
        entry.accentColorHex = hex
        storage[key] = entry
        persist()
        Log.persistence.info("Updated accent color for space \(key.uuidString, privacy: .public)")
    }

    func setSymbolName(_ symbolName: String?, for key: UUID) {
        var entry = blankEntry(for: key)
        entry.symbolName = symbolName
        storage[key] = entry
        persist()
        Log.persistence.info("Updated icon for space \(key.uuidString, privacy: .public)")
    }

    func setLaunchAppBundleIDs(_ bundleIDs: [String], for key: UUID) {
        var entry = blankEntry(for: key)
        entry.launchAppBundleIDs = bundleIDs.isEmpty ? nil : bundleIDs
        storage[key] = entry
        persist()
        Log.persistence.info("Updated launch apps for space \(key.uuidString, privacy: .public)")
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for key: UUID) {
        var entry = blankEntry(for: key)
        entry.shortcut = shortcut
        storage[key] = entry
        persist()
        Log.persistence.info("Updated shortcut for space \(key.uuidString, privacy: .public)")
    }

    private func blankEntry(for key: UUID) -> SpaceMetadata {
        storage[key] ?? SpaceMetadata(stableKey: key, customName: nil, symbolName: nil, accentColorHex: nil, createdAt: Date(), launchAppBundleIDs: nil, shortcut: nil)
    }

    func removeMetadata(for key: UUID) {
        storage[key] = nil
        persist()
        Log.persistence.info("Removed metadata for space \(key.uuidString, privacy: .public)")
    }

    private func persist() {
        let values = Array(storage.values)
        guard let data = try? JSONEncoder().encode(values) else {
            Log.persistence.error("Failed to encode space metadata")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.persistence.error("Failed to write space metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadFromDisk(_ url: URL) -> [UUID: SpaceMetadata] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SpaceMetadata].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.stableKey, $0) })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Nexus", isDirectory: true)
            .appendingPathComponent("space-metadata.json")
    }
}
