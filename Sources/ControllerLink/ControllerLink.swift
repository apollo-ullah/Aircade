import Foundation
import Network
import MotionCore

public enum ControllerMessage: Codable {
    case hello(code: String, controller: UUID, session: UUID)
    case welcome(player: Int)
    case poll(request: UUID)
    case sample(request: UUID, frame: PlayerControllerFrame)
    case feedback(String)
    case calibrating
    case bye(String)
}

/// A small, bounded, length-prefixed protocol shared by macOS and iOS.
/// The phone only sends a sample in response to a poll, so there is never an
/// unbounded queue of 60 Hz motion packets after a slow network connection.
public final class ControllerLink {
    public static let serviceType = "_aircade._tcp"
    public static let maximumMessageSize = 8192
    public let connection: NWConnection
    public var onMessage: ((ControllerMessage) -> Void)?
    public var onReady: (() -> Void)?
    public var onClose: ((String) -> Void)?
    private let queue = DispatchQueue(label: "Aircade.ControllerLink", qos: .userInteractive)
    private var closed = false // queue-confined

    public init(connection: NWConnection) { self.connection = connection }
    public static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: DispatchQueue.main.async { self.onReady?() }
            case .failed(let error): self.finish(error.localizedDescription)
            case .cancelled: self.finish("Disconnected")
            default: break
            }
        }
        connection.start(queue: queue)
        readHeader()
    }
    public func send(_ message: ControllerMessage) {
        guard let data = try? Self.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error.localizedDescription) }
        })
    }
    public func cancel() { connection.cancel() }
    public static func encode(_ message: ControllerMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maximumMessageSize else { throw CocoaError(.coderInvalidValue) }
        var size = UInt32(payload.count).bigEndian
        var framed = withUnsafeBytes(of: &size) { Data($0) }
        framed.append(payload)
        return framed
    }
    private func readHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 4 else { self.finish("Connection closed"); return }
            let length = data.reduce(0) { ($0 << 8) | Int($1) }
            guard (1...Self.maximumMessageSize).contains(length) else { self.finish("Invalid controller packet"); return }
            self.readBody(length)
        }
    }
    private func readBody(_ length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count == length,
                  let message = try? JSONDecoder().decode(ControllerMessage.self, from: data) else {
                self.finish("Invalid controller message"); return
            }
            DispatchQueue.main.async { [weak self] in self?.onMessage?(message) }
            self.readHeader()
        }
    }
    private func finish(_ reason: String) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.closed = true; self.connection.cancel()
            DispatchQueue.main.async { self.onClose?(reason) }
        }
    }
}
