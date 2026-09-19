import Foundation
import Network
import MotionCore
import ControllerLink
import simd

final class MultiplayerModel: ObservableObject {
    @Published private(set) var match = SaberDuel()
    @Published private(set) var code = ""
    @Published private(set) var networkStatus = "Starting local lobby…"
    @Published private(set) var phoneStatus = "Join from the Aircade Controller iPhone app"
    @Published private(set) var ready = [false, false]
    @Published private(set) var latency = 0.0
    @Published private(set) var feedback = ""
    @Published private(set) var scripted = false
    let scene = DuelScene()
    private weak var motion: MotionModel?
    private var listener: NWListener?
    private var link: ControllerLink?
    private var accepted = false
    private var controllers = PlayerControllers()
    private let localID = UUID()
    private var localSession = UUID()
    private var localSequence: UInt64 = 0
    private var poll: (UUID, Double)?
    private var timer: Timer?
    private var feedbackUntil = 0.0
    private var lastSource = ""
    private var scriptStart = 0.0
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var bothReady: Bool { ready.allSatisfy { $0 } }
    var listeningPort: NWEndpoint.Port? { listener?.port }
    func orientation(_ player: PlayerSlot) -> simd_quatf? { controllers[player]?.orientation }
    var localName: String { scripted ? "Scripted blue" : motion?.controllerName ?? "AirPod" }

    init(motion: MotionModel) { self.motion = motion }

    func open() {
        guard timer == nil else { return }
        controllers.assign(.one, controllerID: localID, sessionID: localSession)
        code = String(format: "%06d", Int.random(in: 0...999999))
        startListener()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func close() {
        timer?.invalidate(); timer = nil
        listener?.cancel(); listener = nil
        link?.cancel(); link = nil; accepted = false; poll = nil
        controllers.remove(.two); ready = [false, false]
        match = SaberDuel(); scripted = false
    }
    func start() {
        guard bothReady else { return }
        feedback = ""; match.start(); scriptStart = clock() + 3.1
    }
    func pause(_ reason: String = "Match paused.") { match.pause(reason) }
    func resume() { if bothReady { match.resume(); scriptStart = clock() + 3.1 } }
    func lobby() { match = SaberDuel(); feedback = "" }
    func setScripted(_ value: Bool) {
        // Only affects this arena; never replaces or recalibrates the real AirPod stream.
        match = SaberDuel(); scripted = value; ready = [false, false]
        scriptStart = clock()
    }
    func forgetPhone() {
        pause("Phone removed. Pair a controller to resume.")
        let previous = link; link = nil; previous?.cancel()
        accepted = false; poll = nil; controllers.remove(.two)
        phoneStatus = "Join from the Aircade Controller iPhone app"
        code = String(format: "%06d", Int.random(in: 0...999999))
    }
    private func startListener() {
        do {
            let listener = try NWListener(using: ControllerLink.parameters())
            listener.service = NWListener.Service(name: "Aircade · \(Host.current().localizedName ?? "Mac")", type: ControllerLink.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready: self.networkStatus = "Lobby visible to nearby iPhones"
                    case .failed(let error): self.networkStatus = "Local connection: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async { self?.accept(connection) }
            }
            listener.start(queue: DispatchQueue(label: "Aircade.Lobby")); self.listener = listener
        } catch { networkStatus = "Could not open lobby: \(error.localizedDescription)" }
    }
    private func accept(_ connection: NWConnection) {
        guard link == nil, timer != nil else { connection.cancel(); return }
        let link = ControllerLink(connection: connection); self.link = link
        accepted = false
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link, self.link === link else { return }
            self.receive(message, from: link)
        }
        link.onClose = { [weak self, weak link] reason in
            guard let self, let link, self.link === link else { return }
            self.link = nil; self.accepted = false; self.poll = nil
            self.controllers.remove(.two); self.phoneStatus = "iPhone disconnected · reconnect in the phone app"
        }
        link.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak link] in
            guard let self, let link, self.link === link, !self.accepted else { return }
            link.cancel()
        }
    }
    private func receive(_ message: ControllerMessage, from link: ControllerLink) {
        switch message {
        case let .hello(code, controller, session):
            guard !accepted, code == self.code,
                  controllers.assign(.two, controllerID: controller, sessionID: session) else { link.cancel(); return }
            accepted = true; phoneStatus = "iPhone paired · recenter on the phone"
            link.send(.welcome(player: 2))
        case let .sample(request, frame):
            guard accepted, let pending = poll, pending.0 == request else { return }
            poll = nil
            let age = clock() - pending.1
            // Reject late responses. Counting the entire round trip is deliberately
            // conservative; it requires no clock synchronization between devices.
            guard age >= 0, age < 0.25 else { return }
            let fresh = PlayerControllerFrame(controllerID: frame.controllerID, sessionID: frame.sessionID,
                sequence: frame.sequence, source: frame.source, orientation: simd_quatf(vector: frame.orientation),
                ready: frame.ready, simulated: frame.simulated, sampleAge: frame.sampleAge + age)
            guard frame.isValid, controllers.receive(fresh, for: .two, at: clock()) else { return }
            latency = age * 1000
            phoneStatus = frame.ready ? "iPhone ready" : "Hold phone upright and tap Recenter"
        case .calibrating:
            guard accepted else { return }
            pause("iPhone recentered. Hold both controllers upright, then resume.")
        default: break
        }
    }
    func tick() {
        let now = clock()
        if accepted, poll == nil, let link {
            let request = UUID(); poll = (request, now); link.send(.poll(request: request))
        } else if let poll, now - poll.1 > 3 {
            // A stuck TCP exchange must reconnect, not accumulate more polls.
            link?.cancel()
        }
        var poses: [SaberPose?] = [nil, nil]
        if scripted {
            ready = [true, true]
            // Player 1 makes broad swings; player 2 holds their blade out of the way.
            let t = max(0, now - scriptStart).truncatingRemainder(dividingBy: 1.6)
            let angle: Float = t < 0.30 ? Float(t / 0.30) * -1.15 : t < 0.5 ? -1.15 : t < 0.9 ? -1.15 * Float(1 - (t - 0.5) / 0.4) : 0
            poses = [SaberDuel.pose(.one, simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))),
                     SaberDuel.pose(.two, simd_quatf(angle: -1.2, axis: SIMD3(1, 0, 0)))]
        } else if let motion {
            if !lastSource.isEmpty, lastSource != motion.source { pause("AirPod source changed. Check player 1, then resume.") }
            lastSource = motion.source
            localSequence += 1
            let localReady = motion.hasFreshMotion && motion.calibrated && motion.calibrationStep == 0 && !motion.simulated
            let frame = PlayerControllerFrame(controllerID: localID, sessionID: localSession, sequence: localSequence,
                source: motion.controllerName, orientation: motion.saber, ready: localReady,
                sampleAge: min(60, motion.controllerSampleAge))
            controllers.receive(frame, for: .one, at: now)
            for player in PlayerSlot.allCases {
                let connection = controllers[player]
                ready[player.rawValue] = connection?.isFresh(at: now) == true
                if ready[player.rawValue], let orientation = connection?.orientation {
                    poses[player.rawValue] = SaberDuel.pose(player, orientation)
                }
            }
        }
        for player in PlayerSlot.allCases {
            scene.update(player, pose: poses[player.rawValue], ready: ready[player.rawValue])
        }
        let oldPhase = match.phase
        let events = match.step(at: now, poses: poses)
        for event in events {
            scene.impact(event)
            if event.kind == .clash {
                feedback = "CLASH!"; GameAudio.shared.play("Tink")
                if !scripted { link?.send(.feedback("block")) }
            } else {
                feedback = "\(event.player == .one ? "BLUE" : "ORANGE") SCORES!"
                GameAudio.shared.play("Pop")
                if !scripted { link?.send(.feedback(event.player == .two ? "hit" : "damage")) }
            }
            feedbackUntil = now + 0.8
        }
        if oldPhase != .results, match.phase == .results, !scripted {
            link?.send(.feedback(match.winner == .two ? "victory" : match.winner == nil ? "draw" : "defeat"))
        }
        if now > feedbackUntil { feedback = "" }
        scene.setHealth(match.health)
    }
}
