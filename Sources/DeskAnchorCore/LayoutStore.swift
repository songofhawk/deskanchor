import Foundation

public struct LayoutDatabase: Codable, Equatable, Sendable {
    public var version: Int
    public var snapshotsByTopologyKey: [String: LayoutSnapshot]

    public init(version: Int = 1, snapshotsByTopologyKey: [String: LayoutSnapshot] = [:]) {
        self.version = version
        self.snapshotsByTopologyKey = snapshotsByTopologyKey
    }
}

public final class LayoutStore: @unchecked Sendable {
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

    public func upsert(_ snapshot: LayoutSnapshot) throws {
        var database = try load()
        database.snapshotsByTopologyKey[snapshot.topology.topologyKey] = snapshot
        try save(database)
    }

    public func snapshot(for topology: DisplayTopology) throws -> LayoutSnapshot? {
        try load().snapshotsByTopologyKey[topology.topologyKey]
    }
}
