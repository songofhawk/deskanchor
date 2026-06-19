import CoreGraphics
import Foundation
import Testing
@testable import DeskAnchorCore

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

@Test func displaySetKeyIgnoresRelativeDisplayArrangement() {
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
    let rearrangedLeft = DisplayDescriptor(
        id: 2,
        name: "Left",
        vendor: 1,
        model: 2,
        serial: 3,
        bounds: Rect(x: 2560, y: 0, width: 1920, height: 1080),
        scale: 1,
        isMain: false
    )

    let original = DisplayTopology(displays: [main, left])
    let rearranged = DisplayTopology(displays: [main, rearrangedLeft])

    #expect(original.displaySetKey == rearranged.displaySetKey)
    #expect(original.topologyKey != rearranged.topologyKey)
}

@Test func displayCoordinateSpaceConvertsAppKitBoundsToAccessibilityBounds() {
    let main = Rect(x: 0, y: 0, width: 1800, height: 1169)
    let upperExternal = Rect(x: -1262, y: 1169, width: 3840, height: 2160)

    let converted = DisplayCoordinateSpace.accessibilityBounds(
        fromAppKitBounds: upperExternal,
        mainAppKitBounds: main
    )

    #expect(converted == Rect(x: -1262, y: -2160, width: 3840, height: 2160))
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

@Test func layoutStoreNormalizesLegacyAppKitDisplayBoundsAndWindowDisplays() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LayoutStore(fileURL: directory.appendingPathComponent("layouts.json"))
    let fixedDate = Date(timeIntervalSince1970: 0)
    let external = DisplayDescriptor(
        id: 2,
        name: "External",
        vendor: 10,
        model: 20,
        serial: 30,
        bounds: Rect(x: -1262, y: 1169, width: 3840, height: 2160),
        scale: 1,
        isMain: false
    )
    let main = DisplayDescriptor(
        id: 1,
        name: "Built-in",
        vendor: 40,
        model: 50,
        serial: 60,
        bounds: Rect(x: 0, y: 0, width: 1800, height: 1169),
        scale: 2,
        isMain: true
    )
    let legacyTopology = DisplayTopology(capturedAt: fixedDate, displays: [external, main])
    let signature = WindowSignature(
        bundleIdentifier: "com.example.editor",
        ownerName: "Editor",
        titleFingerprint: WindowMatcher.fingerprint(title: "Project"),
        role: "AXWindow",
        subrole: "AXStandardWindow",
        occurrence: 0
    )
    let snapshot = LayoutSnapshot(
        topology: legacyTopology,
        windows: [
            WindowRecord(
                signature: signature,
                title: "Project",
                frame: Rect(x: 522, y: -2135, width: 2056, height: 1703),
                displayHardwareKey: main.hardwareKey,
                isMinimized: false,
                capturedAt: fixedDate
            )
        ],
        capturedAt: fixedDate
    )

    try store.save(LayoutDatabase(snapshotsByDisplaySetKey: [
        legacyTopology.displaySetKey: [snapshot]
    ]))
    try store.normalizeStorage()

    let normalized = try #require(try store.snapshot(for: legacyTopology))
    let normalizedExternal = try #require(normalized.topology.displays.first { $0.hardwareKey == external.hardwareKey })
    let normalizedWindow = try #require(normalized.windows.first)

    #expect(normalizedExternal.bounds == Rect(x: -1262, y: -2160, width: 3840, height: 2160))
    #expect(normalizedWindow.displayHardwareKey == external.hardwareKey)
}

@Test func windowFingerprintIsStableAcrossWhitespaceAndCase() {
    let a = WindowMatcher.fingerprint(title: "  Project   Notes ")
    let b = WindowMatcher.fingerprint(title: "project notes")

    #expect(a == b)
}

@Test func layoutStoreKeepsHistoryAndReturnsLatestSnapshotForDisplaySet() throws {
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
    let olderSnapshot = LayoutSnapshot(
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
    let newerSnapshot = LayoutSnapshot(
        topology: topology,
        windows: [
            WindowRecord(
                signature: signature,
                title: "Doc",
                frame: Rect(x: 40, y: 50, width: 600, height: 700),
                displayHardwareKey: topology.displays.first?.hardwareKey,
                isMinimized: false,
                capturedAt: fixedDate.addingTimeInterval(10)
            )
        ],
        capturedAt: fixedDate.addingTimeInterval(10)
    )

    try store.upsert(olderSnapshot)
    try store.upsert(newerSnapshot)

    #expect(try store.snapshot(for: topology) == newerSnapshot)
    #expect(try store.history(for: topology) == [newerSnapshot, olderSnapshot])
    #expect(try store.snapshots() == [newerSnapshot, olderSnapshot])
}

@Test func layoutStoreReadsLegacyTopologySnapshotFormat() throws {
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
    let legacy = LegacyLayoutDatabase(
        version: 1,
        snapshotsByTopologyKey: [topology.topologyKey: snapshot]
    )
    let data = try JSONEncoder().encode(legacy)

    let decoded = try JSONDecoder().decode(LayoutDatabase.self, from: data)

    #expect(decoded.version == 2)
    #expect(decoded.snapshotsByDisplaySetKey[topology.displaySetKey] == [snapshot])
}

@Test func windowSignatureApplicationMatchKeyPrefersBundleIdentifier() {
    let withBundle = WindowSignature(
        bundleIdentifier: "com.example.app",
        ownerName: "Renamed App",
        titleFingerprint: "a",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        occurrence: 0
    )
    let withoutBundle = WindowSignature(
        bundleIdentifier: "",
        ownerName: "Example",
        titleFingerprint: "b",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        occurrence: 0
    )

    #expect(withBundle.applicationMatchKey == "bundle:com.example.app")
    #expect(withoutBundle.applicationMatchKey == "owner:Example")
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

private struct LegacyLayoutDatabase: Encodable {
    var version: Int
    var snapshotsByTopologyKey: [String: LayoutSnapshot]
}
