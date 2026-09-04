import Foundation
import Testing
@testable import Nexus

@Suite("SpaceReconciler")
struct SpaceReconcilerTests {
    @Test("With no prior history, every observation gets a fresh stable key")
    func firstObservation() {
        let observed = [
            SpaceReconciler.Observation(order: 0, systemLabel: "Desktop 1", isActive: true, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Desktop 2", isActive: false, displayID: nil),
        ]

        let result = SpaceReconciler.reconcile(previous: [], observed: observed)

        #expect(result.count == 2)
        #expect(Set(result.map(\.identifier.stableKey)).count == 2)
        #expect(result[0].isActive == true)
        #expect(result[1].isActive == false)
    }

    @Test("An unchanged arrangement keeps the same stable keys across calls")
    func stableAcrossIdenticalObservations() {
        let first = SpaceReconciler.reconcile(previous: [], observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Desktop 1", isActive: true, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Desktop 2", isActive: false, displayID: nil),
        ])

        let second = SpaceReconciler.reconcile(previous: first, observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Desktop 1", isActive: false, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Desktop 2", isActive: true, displayID: nil),
        ])

        #expect(second[0].identifier.stableKey == first[0].identifier.stableKey)
        #expect(second[1].identifier.stableKey == first[1].identifier.stableKey)
        #expect(second[0].isActive == false)
        #expect(second[1].isActive == true)
    }

    @Test("A full-screen space's identity survives a plain desktop being deleted ahead of it, via its distinguishing name")
    func fullScreenSpaceSurvivesReordering() {
        // Realistic labels: plain desktops are always the generic "Desktop N" (N shifts for
        // everything after a deletion); a full-screen space carries the app's actual name, which
        // doesn't change — so it's the one case label-matching is unambiguous.
        let first = SpaceReconciler.reconcile(previous: [], observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Desktop 1", isActive: true, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Desktop 2", isActive: false, displayID: nil),
            SpaceReconciler.Observation(order: 2, systemLabel: "Windows App", isActive: false, displayID: nil),
        ])

        // "Desktop 1" was deleted; "Desktop 2" renumbers to "Desktop 1", "Windows App" shifts
        // from order 2 to order 1 but keeps its name.
        let second = SpaceReconciler.reconcile(previous: first, observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Desktop 1", isActive: true, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Windows App", isActive: false, displayID: nil),
        ])

        let fullScreenBefore = first.first { $0.systemLabel == "Windows App" }
        let fullScreenAfter = second.first { $0.systemLabel == "Windows App" }
        #expect(fullScreenBefore?.identifier.stableKey == fullScreenAfter?.identifier.stableKey)
        #expect(second.count == 2)
    }

    @Test("A newly created space with no prior match gets a brand-new identity")
    func newSpaceGetsFreshKey() {
        let first = SpaceReconciler.reconcile(previous: [], observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Work", isActive: true, displayID: nil),
        ])

        let second = SpaceReconciler.reconcile(previous: first, observed: [
            SpaceReconciler.Observation(order: 0, systemLabel: "Work", isActive: true, displayID: nil),
            SpaceReconciler.Observation(order: 1, systemLabel: "Desktop 2", isActive: false, displayID: nil),
        ])

        #expect(second.count == 2)
        #expect(second[0].identifier.stableKey == first[0].identifier.stableKey)
        #expect(!first.map(\.identifier.stableKey).contains(second[1].identifier.stableKey))
    }
}
