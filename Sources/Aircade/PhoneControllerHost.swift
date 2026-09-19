import Foundation
import Network
import MotionCore
import ControllerLink
import simd

/// One phone connection, independent of routes and games. Call on the main thread.
final class PhoneControllerHost: ObservableObject {
    @Published private(set) var code = String(format: "%06d", Int.random(in: 0...999999))
    @Published private(set) var networkStatus = "Connect an iPhone controller"
    @Published private(set) var status = "Join from the Aircade Controller iPhone app"
    @Published private(set) var connected = false
    @Published private(set) var latency = 0.0
    @Published private(set) var role: ControllerRole = .unassigned
    var onInputChanged: (() -> Void)?
    var onInvalidation: ((String) -> Void)?
    var onConnectionChanged: (() -> Void)?
    var listeningPort: NWEndpoint.Port? { listener?.port }
    var connection: PlayerControllers.Connection? { samples[.one] }
    private let clock: () -> Double
    private var listener: NWListener?
    private var link: ControllerLink?
    private var samples = PlayerControllers()
    private var poll: (id: UUID, sentAt: Double, valid: Bool)?
    private var activeRun: UUID?

    init(clock: @escaping () -> Double) { self.clock = clock }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: ControllerLink.parameters())
            self.listener = listener
            listener.service = NWListener.Service(name: "Aircade · \(Host.current().localizedName ?? "Mac")", type: ControllerLink.serviceType)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                DispatchQueue.main.async {
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.networkStatus = "Visible to nearby iPhones"
                    case .failed(let error): self.networkStatus = "Local connection: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                DispatchQueue.main.async {
                    guard let self, let listener, self.listener === listener else { connection.cancel(); return }
                    self.accept(connection)
                }
            }
            listener.start(queue: DispatchQueue(label: "Aircade.PhoneHost"))
        } catch { networkStatus = "Could not open pairing: \(error.localizedDescription)" }
    }

    func shutdown() {
        let previous = listener; listener = nil; previous?.cancel()
        disconnect("Controller host stopped")
        networkStatus = "Controller host stopped"
    }
    func forget() {
        disconnect("iPhone removed. Pair a controller to resume.")
        code = String(format: "%06d", Int.random(in: 0...999999))
    }
    func setRole(_ value: ControllerRole) {
        guard value.isValid, role != value else { return }
        role = value
        if connected { link?.send(.assignment(value)) }
    }
    func recenter() {
        guard connected else { return }
        invalidate("iPhone recenter requested. Hold it upright.")
        link?.send(.recenter)
    }
    func setActiveRun(_ id: UUID?) {
        activeRun = id
        if connected { link?.send(.activeRun(id)) }
    }
    func feedback(run: UUID, cue: ControllerFeedback) {
        guard connected, activeRun == run else { return }
        link?.send(.feedbackEvent(run: run, cue: cue))
    }
    func tick() {
        let now = clock()
        guard now.isFinite, connected, let link else { return }
        if let poll {
            if now < poll.sentAt || now - poll.sentAt > 3 {
                disconnect("iPhone connection stalled · reconnect in the phone app")
            }
        } else {
            let request = UUID(); poll = (request, now, true)
            link.send(.poll(request: request))
        }
    }
    private func accept(_ connection: NWConnection) {
        guard link == nil, listener != nil else { connection.cancel(); return }
        let link = ControllerLink(connection: connection); self.link = link
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link, self.link === link else { return }
            self.receive(message, from: link)
        }
        link.onClose = { [weak self, weak link] _ in
            guard let self, let link, self.link === link else { return }
            self.disconnect("iPhone disconnected · reconnect in the phone app")
        }
        link.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak link] in
            guard let self, let link, self.link === link, !self.connected else { return }
            self.disconnect("Pairing timed out · check the code")
        }
    }
    private func receive(_ message: ControllerMessage, from link: ControllerLink) {
        switch message {
        case let .hello(code, controller, session):
            guard !connected, code == self.code else { disconnect("Incorrect pairing code"); return }
            samples.assign(.one, controllerID: controller, sessionID: session)
            connected = true; status = "iPhone paired · recenter on the phone"
            // The original greeting is retained. Assignment carries the complete role.
            let player: Int
            if case .player(let number) = role { player = number } else { player = role == .solo ? 1 : 0 }
            link.send(.welcome(player: player)); link.send(.assignment(role)); link.send(.activeRun(activeRun))
            onConnectionChanged?()
        case let .sample(request, frame):
            guard connected, let pending = poll, pending.id == request else { return }
            poll = nil
            let now = clock(), roundTrip = now - pending.sentAt
            // Sender uptime is never compared with Mac uptime. Include the whole RTT
            // conservatively and retain that estimated capture time until the next sample.
            guard pending.valid, now.isFinite, roundTrip >= 0, roundTrip < 0.25, frame.isValid else { return }
            let received = PlayerControllerFrame(controllerID: frame.controllerID, sessionID: frame.sessionID,
                sequence: frame.sequence, source: frame.source, orientation: simd_quatf(vector: frame.orientation),
                ready: frame.ready, simulated: frame.simulated, sampleAge: frame.sampleAge + roundTrip)
            guard samples.receive(received, for: .one, at: now) else { return }
            latency = roundTrip * 1000
            status = frame.ready ? "iPhone ready" : "Hold phone upright and tap Recenter"
            onInputChanged?()
        case .calibrating:
            guard connected else { return }
            invalidate("iPhone recentered. Hold it upright, then resume.")
        default: break
        }
    }
    private func invalidate(_ reason: String) {
        // An in-flight sample captured before recenter cannot restore readiness.
        poll?.valid = false; samples.invalidate(.one); status = reason
        onInvalidation?(reason)
    }
    private func disconnect(_ reason: String) {
        let wasConnected = connected
        let previous = link; link = nil; previous?.cancel()
        poll = nil; samples.remove(.one); connected = false; latency = 0; status = reason
        if wasConnected { onInvalidation?(reason); onConnectionChanged?() }
    }
    deinit { listener?.cancel(); link?.cancel() }
}
