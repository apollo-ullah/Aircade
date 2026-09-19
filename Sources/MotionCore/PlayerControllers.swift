import Foundation
import simd

public enum PlayerSlot: Int, CaseIterable, Codable {
    case one = 0, two = 1
    public var other: PlayerSlot { self == .one ? .two : .one }
}

/// One independent controller owns one player slot. Left/Right identifies an
/// earbud within that controller; it must never be used as a multiplayer ID.
public struct PlayerControllerFrame: Codable {
    public var version = 1
    public let controllerID: UUID
    public let sessionID: UUID
    public let sequence: UInt64
    public let source: String
    public let orientation: SIMD4<Float>
    public let ready: Bool
    public let simulated: Bool
    /// Age at the sender, not its absolute uptime (peers have different clocks).
    public let sampleAge: Double

    public init(controllerID: UUID, sessionID: UUID, sequence: UInt64, source: String,
                orientation: simd_quatf, ready: Bool, simulated: Bool = false, sampleAge: Double = 0) {
        self.controllerID = controllerID; self.sessionID = sessionID; self.sequence = sequence
        self.source = source; self.orientation = orientation.vector
        self.ready = ready; self.simulated = simulated; self.sampleAge = sampleAge
    }

    public var isValid: Bool {
        version == 1 && !source.isEmpty && source.utf8.count <= 64 &&
        sampleAge.isFinite && sampleAge >= 0 &&
        (0..<4).allSatisfy { orientation[$0].isFinite } &&
        (0.5...1.5).contains(simd_length(orientation))
    }
}

/// The host explicitly assigns controllers. Old sessions, duplicate/reordered
/// packets, and a controller already owned by the other player cannot take over.
public struct PlayerControllers {
    public struct Connection {
        public let controllerID: UUID
        public let sessionID: UUID
        public fileprivate(set) var frame: PlayerControllerFrame?
        public fileprivate(set) var receivedAt: Double?
        public var orientation: simd_quatf? {
            frame.map { simd_normalize(simd_quatf(vector: $0.orientation)) }
        }
        public func isFresh(at now: Double) -> Bool {
            guard let frame, let receivedAt else { return false }
            return frame.ready && now >= receivedAt && now - receivedAt + frame.sampleAge < 0.25
        }
    }
    private var connections: [PlayerSlot: Connection] = [:]
    public init() {}
    public subscript(_ player: PlayerSlot) -> Connection? { connections[player] }

    @discardableResult
    public mutating func assign(_ player: PlayerSlot, controllerID: UUID, sessionID: UUID) -> Bool {
        guard connections[player.other]?.controllerID != controllerID else { return false }
        connections[player] = Connection(controllerID: controllerID, sessionID: sessionID)
        return true
    }
    public mutating func remove(_ player: PlayerSlot) { connections[player] = nil }

    @discardableResult
    public mutating func receive(_ frame: PlayerControllerFrame, for player: PlayerSlot, at time: Double) -> Bool {
        guard frame.isValid, time.isFinite, var connection = connections[player],
              connection.controllerID == frame.controllerID, connection.sessionID == frame.sessionID,
              connection.frame.map({ frame.sequence > $0.sequence }) ?? true,
              connection.receivedAt.map({ time >= $0 }) ?? true else { return false }
        connection.frame = frame; connection.receivedAt = time
        connections[player] = connection
        return true
    }
}
