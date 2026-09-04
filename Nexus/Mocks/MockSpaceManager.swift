import Foundation

/// In-memory `SpaceManaging` used until the Tier 2 Accessibility backend lands (Phase 4+), and in
/// tests/previews after that. Simulates realistic async latency so the UI's loading states are
/// exercised honestly rather than resolving instantly.
@MainActor
final class MockSpaceManager: SpaceManaging {
    private var storage: [DesktopSpace]
    private var activeIndex: Int

    init() {
        let seedLabels = ["Work", "Development", "Gaming", "Research", "Personal"]
        storage = seedLabels.enumerated().map { index, label in
            DesktopSpace(
                identifier: SpaceIdentifier(systemToken: "mock-\(index)"),
                order: index,
                isActive: index == 0,
                displayID: nil,
                systemLabel: "Desktop \(index + 1)",
                customName: label,
                symbolName: nil
            )
        }
        activeIndex = 0
    }

    func spaces() async throws -> [DesktopSpace] {
        try await Task.sleep(for: .milliseconds(120))
        return storage
    }

    func activeSpace() async throws -> DesktopSpace? {
        try await Task.sleep(for: .milliseconds(40))
        return storage.indices.contains(activeIndex) ? storage[activeIndex] : nil
    }

    func activate(_ space: DesktopSpace) async throws {
        try await Task.sleep(for: .milliseconds(150))
        guard let index = storage.firstIndex(where: { $0.identifier == space.identifier }) else {
            throw SpaceError.spaceNotFound
        }
        for i in storage.indices { storage[i].isActive = (i == index) }
        activeIndex = index
        Log.spaceManager.info("Mock activated space at index \(index, privacy: .public)")
    }

    func createSpace() async throws -> DesktopSpace {
        try await Task.sleep(for: .milliseconds(200))
        let newOrder = storage.count
        let space = DesktopSpace(
            identifier: SpaceIdentifier(systemToken: "mock-\(newOrder)"),
            order: newOrder,
            isActive: false,
            displayID: nil,
            systemLabel: "Desktop \(newOrder + 1)",
            customName: nil,
            symbolName: nil
        )
        storage.append(space)
        Log.spaceManager.info("Mock created space \(newOrder, privacy: .public)")
        return space
    }

    func delete(_ space: DesktopSpace) async throws {
        try await Task.sleep(for: .milliseconds(150))
        guard storage.count > 1 else { throw SpaceError.cannotDeleteLastSpace }
        guard let index = storage.firstIndex(where: { $0.identifier == space.identifier }) else {
            throw SpaceError.spaceNotFound
        }
        storage.remove(at: index)
        for i in storage.indices { storage[i].order = i }
        if activeIndex >= storage.count { activeIndex = storage.count - 1 }
        for i in storage.indices { storage[i].isActive = (i == activeIndex) }
        Log.spaceManager.info("Mock deleted space at index \(index, privacy: .public)")
    }
}
