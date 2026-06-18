import Foundation

public struct DisplayDescriptor: Codable, Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var bounds: Rect
    public var scale: Double
    public var isMain: Bool

    public init(
        id: UInt32,
        name: String,
        vendor: UInt32,
        model: UInt32,
        serial: UInt32,
        bounds: Rect,
        scale: Double,
        isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.bounds = bounds
        self.scale = scale
        self.isMain = isMain
    }

    public var hardwareKey: String {
        "\(vendor):\(model):\(serial):\(Int(scale * 100))"
    }
}

public struct DisplayTopology: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var displays: [DisplayDescriptor]

    public init(capturedAt: Date = Date(), displays: [DisplayDescriptor]) {
        self.capturedAt = capturedAt
        self.displays = displays.sortedForStableTopology()
    }

    public var topologyKey: String {
        displays
            .map { display in
                let rect = display.bounds.rounded()
                return [
                    display.hardwareKey,
                    String(Int(rect.x)),
                    String(Int(rect.y)),
                    String(Int(rect.width)),
                    String(Int(rect.height)),
                    display.isMain ? "main" : "secondary"
                ].joined(separator: "@")
            }
            .joined(separator: "|")
    }

    public var humanSummary: String {
        if displays.isEmpty {
            return "未检测到显示器"
        }

        return displays
            .map { display in
                let rect = display.bounds.rounded()
                let role = display.isMain ? "主屏" : "副屏"
                return "\(display.name) \(Int(rect.width))x\(Int(rect.height)) @(\(Int(rect.x)),\(Int(rect.y))) \(role)"
            }
            .joined(separator: "\n")
    }
}

extension Array where Element == DisplayDescriptor {
    public func sortedForStableTopology() -> [DisplayDescriptor] {
        sorted { lhs, rhs in
            if lhs.bounds.x != rhs.bounds.x {
                return lhs.bounds.x < rhs.bounds.x
            }
            if lhs.bounds.y != rhs.bounds.y {
                return lhs.bounds.y < rhs.bounds.y
            }
            if lhs.hardwareKey != rhs.hardwareKey {
                return lhs.hardwareKey < rhs.hardwareKey
            }
            return lhs.id < rhs.id
        }
    }
}
