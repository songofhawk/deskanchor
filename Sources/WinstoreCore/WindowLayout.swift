import Foundation

public struct WindowSignature: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var ownerName: String
    public var titleFingerprint: String
    public var role: String
    public var subrole: String
    public var occurrence: Int

    public init(
        bundleIdentifier: String,
        ownerName: String,
        titleFingerprint: String,
        role: String,
        subrole: String,
        occurrence: Int
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.ownerName = ownerName
        self.titleFingerprint = titleFingerprint
        self.role = role
        self.subrole = subrole
        self.occurrence = occurrence
    }

    public var matchKey: String {
        [
            bundleIdentifier,
            ownerName,
            titleFingerprint,
            role,
            subrole,
            String(occurrence)
        ].joined(separator: "\u{1F}")
    }
}

public struct WindowRecord: Codable, Equatable, Sendable {
    public var signature: WindowSignature
    public var title: String
    public var frame: Rect
    public var displayHardwareKey: String?
    public var isMinimized: Bool
    public var capturedAt: Date

    public init(
        signature: WindowSignature,
        title: String,
        frame: Rect,
        displayHardwareKey: String?,
        isMinimized: Bool,
        capturedAt: Date = Date()
    ) {
        self.signature = signature
        self.title = title
        self.frame = frame
        self.displayHardwareKey = displayHardwareKey
        self.isMinimized = isMinimized
        self.capturedAt = capturedAt
    }
}

public struct LayoutSnapshot: Codable, Equatable, Sendable {
    public var topology: DisplayTopology
    public var windows: [WindowRecord]
    public var capturedAt: Date

    public init(topology: DisplayTopology, windows: [WindowRecord], capturedAt: Date = Date()) {
        self.topology = topology
        self.windows = windows
        self.capturedAt = capturedAt
    }
}

public enum WindowMatcher {
    public static func fingerprint(title: String) -> String {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()

        if normalized.isEmpty {
            return "<untitled>"
        }

        return String(normalized.unicodeScalars.map(\.value).reduce(UInt64(1469598103934665603)) { hash, scalar in
            (hash ^ UInt64(scalar)) &* 1099511628211
        }, radix: 16)
    }

    public static func assignOccurrences(_ records: [WindowRecord]) -> [WindowRecord] {
        var counts: [String: Int] = [:]
        return records.map { record in
            var copy = record
            var signature = copy.signature
            signature.occurrence = counts[signatureBaseKey(signature), default: 0]
            counts[signatureBaseKey(signature), default: 0] += 1
            copy.signature = signature
            return copy
        }
    }

    private static func signatureBaseKey(_ signature: WindowSignature) -> String {
        [
            signature.bundleIdentifier,
            signature.ownerName,
            signature.titleFingerprint,
            signature.role,
            signature.subrole
        ].joined(separator: "\u{1E}")
    }
}
