import Foundation
import Testing
@testable import Nexus

@Suite("SpaceMetadataStore")
struct SpaceMetadataStoreTests {
    private func makeStore() -> SpaceMetadataStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("space-metadata.json")
        return SpaceMetadataStore(fileURL: tempURL)
    }

    @Test("Setting a custom name round-trips through the store")
    func setAndReadCustomName() async {
        let store = makeStore()
        let key = UUID()

        await store.setCustomName("Development", for: key)
        let metadata = await store.metadata(for: key)

        #expect(metadata?.customName == "Development")
    }

    @Test("An empty or blank name clears the custom name instead of storing an empty string")
    func blankNameClearsMetadata() async {
        let store = makeStore()
        let key = UUID()

        await store.setCustomName("Work", for: key)
        await store.setCustomName("   ", for: key)
        let metadata = await store.metadata(for: key)

        #expect(metadata?.customName == nil)
    }

    @Test("Removing metadata deletes the entry entirely")
    func removeMetadata() async {
        let store = makeStore()
        let key = UUID()

        await store.setCustomName("Gaming", for: key)
        await store.removeMetadata(for: key)
        let metadata = await store.metadata(for: key)

        #expect(metadata == nil)
    }

    @Test("Metadata persists across separate store instances reading the same file")
    func persistsAcrossInstances() async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("space-metadata.json")
        let key = UUID()

        let firstStore = SpaceMetadataStore(fileURL: tempURL)
        await firstStore.setCustomName("Research", for: key)

        let secondStore = SpaceMetadataStore(fileURL: tempURL)
        let metadata = await secondStore.metadata(for: key)

        #expect(metadata?.customName == "Research")
    }
}
