import Foundation

/// The BLE identifiers and 12-byte control frames used by the tested
/// SOSEXY/啵啵贝 device family.
public enum BobobeiProtocol {
    public static let serviceUUID = "0000EE01-0000-1000-8000-00805F9B34FB"
    public static let notifyUUID = "0000EE02-0000-1000-8000-00805F9B34FB"
    public static let writeUUID = "0000EE03-0000-1000-8000-00805F9B34FB"

    public struct Levels: Equatable, Sendable {
        public var motion: Int
        public var vibration: Int
        public var rotation: Int

        public init(motion: Int = 0, vibration: Int = 0, rotation: Int = 0) {
            self.motion = Self.clamp(motion)
            self.vibration = Self.clamp(vibration)
            self.rotation = Self.clamp(rotation)
        }

        private static func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
        public static let stopped = Levels()
    }

    private static func packet(channel: UInt8, level: Int, responseChannel: UInt8) -> Data {
        Data([0x01, 0x01, 0x00, 0x02, 0x00, channel, 0x11,
              UInt8(min(100, max(0, level))), 0x00, responseChannel, 0x11, 0x01])
    }

    /// Write these packets serially, using GATT write-with-response.
    public static func packets(for levels: Levels) -> [Data] {
        [packet(channel: 0x07, level: levels.motion, responseChannel: 0x08),
         packet(channel: 0x01, level: levels.vibration, responseChannel: 0x02),
         packet(channel: 0x03, level: levels.rotation, responseChannel: 0x04)]
    }

    public static let stopPackets = packets(for: .stopped)

    /// Keep the link alive with one packet, rather than re-sending all three
    /// channels every tick. This matches the stable desktop relay behaviour.
    public static func keepAlivePacket(for levels: Levels) -> Data {
        if levels.motion > 0 {
            return packet(channel: 0x07, level: levels.motion, responseChannel: 0x08)
        }
        if levels.vibration > 0 {
            return packet(channel: 0x01, level: levels.vibration, responseChannel: 0x02)
        }
        if levels.rotation > 0 {
            return packet(channel: 0x03, level: levels.rotation, responseChannel: 0x04)
        }
        return packet(channel: 0x07, level: 0, responseChannel: 0x08)
    }
}
