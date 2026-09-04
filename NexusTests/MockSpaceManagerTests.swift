import Foundation
import Testing
@testable import Nexus

@Suite("MockSpaceManager", .tags(.mocks))
@MainActor
struct MockSpaceManagerTests {
    @Test("Starts with a seeded, ordered set of spaces with the first one active")
    func initialState() async throws {
        let manager = MockSpaceManager()
        let spaces = try await manager.spaces()

        #expect(spaces.count == 5)
        #expect(spaces.map(\.order) == Array(0..<5))
        #expect(spaces.filter(\.isActive).count == 1)
        #expect(try await manager.activeSpace()?.order == 0)
    }

    @Test("Activating a space updates isActive across the set")
    func activate() async throws {
        let manager = MockSpaceManager()
        let spaces = try await manager.spaces()
        let target = spaces[2]

        try await manager.activate(target)

        let active = try await manager.activeSpace()
        #expect(active?.identifier == target.identifier)
        let all = try await manager.spaces()
        #expect(all.filter(\.isActive).count == 1)
    }

    @Test("Creating a space appends it with the next order")
    func createSpace() async throws {
        let manager = MockSpaceManager()
        let created = try await manager.createSpace()

        #expect(created.order == 5)
        let all = try await manager.spaces()
        #expect(all.count == 6)
    }

    @Test("Deleting a space renumbers the remaining spaces contiguously")
    func deleteRenumbers() async throws {
        let manager = MockSpaceManager()
        let spaces = try await manager.spaces()
        try await manager.delete(spaces[1])

        let remaining = try await manager.spaces()
        #expect(remaining.count == 4)
        #expect(remaining.map(\.order) == Array(0..<4))
    }

    @Test("Deleting the last remaining space throws cannotDeleteLastSpace")
    func cannotDeleteLastSpace() async throws {
        let manager = MockSpaceManager()
        var spaces = try await manager.spaces()
        while spaces.count > 1 {
            try await manager.delete(spaces[0])
            spaces = try await manager.spaces()
        }

        await #expect(throws: SpaceError.self) {
            try await manager.delete(spaces[0])
        }
    }
}

extension Tag {
    @Tag static var mocks: Self
}
