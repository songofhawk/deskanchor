import CoreGraphics
import Foundation
import Testing
@testable import WinstoreCore

@Test func topologyKeyIncludesRelativeDisplayArrangement() {
    let left = DisplayDescriptor(
        id: 2,
        name: "Left",
        vendor: 1,
        model: 2,
        serial: 3,
        bounds: Rect(x: -1920, y: 0, width: 1920, height: 1080),
        scale: 1,
        isMain: false
    )
    let main = DisplayDescriptor(
        id: 1,
        name: "Main",
        vendor: 4,
        model: 5,
        serial: 6,
        bounds: Rect(x: 0, y: 0, width: 2560, height: 1440),
        scale: 2,
        isMain: true
    )

    let topology = DisplayTopology(displays: [main, left])

    #expect(topology.displays.map(\.name) == ["Left", "Main"])
    #expect(topology.topologyKey.contains("-1920@0@1920@1080"))
    #expect(topology.topologyKey.contains("0@0@2560@1440@main"))
}

@Test func displayLocatorUsesWindowCenter() {
    let topology = DisplayTopology(displays: [
        DisplayDescriptor(
            id: 1,
            name: "Main",
            vendor: 1,
            model: 1,
            serial: 1,
            bounds: Rect(x: 0, y: 0, width: 1000, height: 1000),
            scale: 2,
            isMain: true
        ),
        DisplayDescriptor(
            id: 2,
            name: "Right",
            vendor: 2,
            model: 2,
            serial: 2,
            bounds: Rect(x: 1000, y: 0, width: 1000, height: 1000),
            scale: 1,
            isMain: false
        )
    ])

    let key = DisplayLocator.displayHardwareKey(
        for: Rect(x: 1200, y: 100, width: 500, height: 500),
        in: topology
    )

    #expect(key == topology.displays[1].hardwareKey)
}

@Test func windowFingerprintIsStableAcrossWhitespaceAndCase() {
    let a = WindowMatcher.fingerprint(title: "  Project   Notes ")
    let b = WindowMatcher.fingerprint(title: "project notes")

    #expect(a == b)
}

@Test func layoutStoreRoundTripsSnapshot() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LayoutStore(fileURL: directory.appendingPathComponent("layouts.json"))
    let fixedDate = Date(timeIntervalSince1970: 0)
    let topology = DisplayTopology(capturedAt: fixedDate, displays: [
        DisplayDescriptor(
            id: 1,
            name: "Main",
            vendor: 1,
            model: 2,
            serial: 3,
            bounds: Rect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isMain: true
        )
    ])
    let signature = WindowSignature(
        bundleIdentifier: "com.example.app",
        ownerName: "Example",
        titleFingerprint: WindowMatcher.fingerprint(title: "Doc"),
        role: "AXWindow",
        subrole: "AXStandardWindow",
        occurrence: 0
    )
    let snapshot = LayoutSnapshot(
        topology: topology,
        windows: [
            WindowRecord(
                signature: signature,
                title: "Doc",
                frame: Rect(x: 10, y: 20, width: 300, height: 400),
                displayHardwareKey: topology.displays.first?.hardwareKey,
                isMinimized: false,
                capturedAt: fixedDate
            )
        ],
        capturedAt: fixedDate
    )

    try store.upsert(snapshot)

    #expect(try store.snapshot(for: topology) == snapshot)
}

@Test func restorePlannerProjectsFrameAcrossResolutionChanges() {
    let saved = DisplayDescriptor(
        id: 1,
        name: "Old",
        vendor: 1,
        model: 1,
        serial: 1,
        bounds: Rect(x: 0, y: 0, width: 1000, height: 1000),
        scale: 1,
        isMain: true
    )
    let current = DisplayDescriptor(
        id: 2,
        name: "New",
        vendor: 1,
        model: 1,
        serial: 1,
        bounds: Rect(x: 0, y: 0, width: 2000, height: 1000),
        scale: 1,
        isMain: true
    )

    let target = RestorePlanner.targetFrame(
        savedFrame: Rect(x: 250, y: 100, width: 500, height: 200),
        savedDisplay: saved,
        currentDisplay: current
    )

    #expect(target == Rect(x: 500, y: 100, width: 1000, height: 200))
}

@Test func restorePlannerKeepsWindowsInsideCurrentDisplay() {
    let clamped = RestorePlanner.clamped(
        Rect(x: -500, y: -500, width: 4000, height: 3000),
        to: Rect(x: 0, y: 0, width: 1440, height: 900)
    )

    #expect(clamped == Rect(x: 0, y: 0, width: 1440, height: 900))
}
