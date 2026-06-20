import Foundation

public struct LayoutDatabase: Codable, Equatable, Sendable {
    public var version: Int
    public var snapshotsByDisplaySetKey: [String: [LayoutSnapshot]]

    public init(version: Int = 2, snapshotsByDisplaySetKey: [String: [LayoutSnapshot]] = [:]) {
        self.version = version
        self.snapshotsByDisplaySetKey = snapshotsByDisplaySetKey
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case snapshotsByDisplaySetKey
        case snapshotsByTopologyKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        if let histories = try container.decodeIfPresent([String: [LayoutSnapshot]].self, forKey: .snapshotsByDisplaySetKey) {
            snapshotsByDisplaySetKey = histories.mapValues(Self.sortedHistory)
            return
        }

        let legacySnapshots = try container.decodeIfPresent([String: LayoutSnapshot].self, forKey: .snapshotsByTopologyKey) ?? [:]
        snapshotsByDisplaySetKey = Dictionary(grouping: legacySnapshots.values) { snapshot in
            snapshot.topology.displaySetKey
        }.mapValues(Self.sortedHistory)
        version = 2
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(snapshotsByDisplaySetKey, forKey: .snapshotsByDisplaySetKey)
    }

    public mutating func normalizeLegacyCoordinateSpace() {
        let snapshots = snapshotsByDisplaySetKey.values
            .flatMap { $0 }
            .map(Self.normalizedLegacyCoordinateSpace)

        snapshotsByDisplaySetKey = Dictionary(grouping: snapshots) { snapshot in
            snapshot.topology.displaySetKey
        }.mapValues(Self.sortedHistory)
        version = 2
    }

    private static func sortedHistory(_ snapshots: [LayoutSnapshot]) -> [LayoutSnapshot] {
        snapshots.sorted { lhs, rhs in
            lhs.capturedAt > rhs.capturedAt
        }
    }

    private static func normalizedLegacyCoordinateSpace(_ snapshot: LayoutSnapshot) -> LayoutSnapshot {
        let convertedTopology = DisplayCoordinateSpace.accessibilityTopology(fromAppKitTopology: snapshot.topology)
        guard convertedTopology != snapshot.topology,
              containedWindowCount(in: convertedTopology, windows: snapshot.windows) > containedWindowCount(in: snapshot.topology, windows: snapshot.windows) else {
            return snapshot
        }

        return LayoutSnapshot(
            topology: convertedTopology,
            windows: snapshot.windows.map { record in
                var copy = record
                copy.displayHardwareKey = DisplayLocator.displayHardwareKey(for: record.frame, in: convertedTopology)
                return copy
            },
            capturedAt: snapshot.capturedAt
        )
    }

    private static func containedWindowCount(in topology: DisplayTopology, windows: [WindowRecord]) -> Int {
        windows.reduce(0) { count, record in
            topology.displays.contains { display in
                display.bounds.containsCenter(of: record.frame)
            } ? count + 1 : count
        }
    }
}

public final class LayoutStore: @unchecked Sendable {
    private static let maxHistoryPerDisplaySet = 20

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultStore() throws -> LayoutStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DeskAnchor", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LayoutStore(fileURL: directory.appendingPathComponent("layouts.json"))
    }

    public func load() throws -> LayoutDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LayoutDatabase()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(LayoutDatabase.self, from: data)
    }

    public func save(_ database: LayoutDatabase) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func normalizeStorage() throws {
        var database = try load()
        database.normalizeLegacyCoordinateSpace()
        try save(database)
    }

    public func upsert(_ snapshot: LayoutSnapshot) throws {
        var database = try load()
        let key = snapshot.topology.displaySetKey
        var history = database.snapshotsByDisplaySetKey[key, default: []]
        history.insert(snapshot, at: 0)
        history.sort { lhs, rhs in
            lhs.capturedAt > rhs.capturedAt
        }
        if history.count > Self.maxHistoryPerDisplaySet {
            history.removeLast(history.count - Self.maxHistoryPerDisplaySet)
        }
        database.snapshotsByDisplaySetKey[key] = history
        try save(database)
    }

    public func rename(_ snapshot: LayoutSnapshot, to title: String?) throws -> LayoutSnapshot? {
        var database = try load()
        let key = snapshot.topology.displaySetKey
        guard var history = database.snapshotsByDisplaySetKey[key],
              let index = history.firstIndex(where: { candidate in
                  candidate.capturedAt == snapshot.capturedAt
                      && candidate.topology.topologyKey == snapshot.topology.topologyKey
              }) else {
            return nil
        }

        let normalizedTitle = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        history[index].customTitle = normalizedTitle?.isEmpty == false ? normalizedTitle : nil
        database.snapshotsByDisplaySetKey[key] = history
        try save(database)
        return history[index]
    }

    @discardableResult
    public func delete(_ snapshot: LayoutSnapshot) throws -> Bool {
        var database = try load()
        let key = snapshot.topology.displaySetKey
        guard var history = database.snapshotsByDisplaySetKey[key] else {
            return false
        }

        let originalCount = history.count
        history.removeAll { candidate in
            candidate.capturedAt == snapshot.capturedAt
                && candidate.topology.topologyKey == snapshot.topology.topologyKey
        }
        guard history.count != originalCount else {
            return false
        }

        if history.isEmpty {
            database.snapshotsByDisplaySetKey.removeValue(forKey: key)
        } else {
            database.snapshotsByDisplaySetKey[key] = history
        }
        try save(database)
        return true
    }

    public func snapshot(for topology: DisplayTopology) throws -> LayoutSnapshot? {
        try history(for: topology).first
    }

    public func history(for topology: DisplayTopology) throws -> [LayoutSnapshot] {
        try load().snapshotsByDisplaySetKey[topology.displaySetKey] ?? []
    }

    public func snapshots() throws -> [LayoutSnapshot] {
        try load().snapshotsByDisplaySetKey.values
            .flatMap { $0 }
            .sorted { lhs, rhs in
                lhs.capturedAt > rhs.capturedAt
            }
    }
}
