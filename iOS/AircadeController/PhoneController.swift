import SwiftUI
import CoreMotion
import simd
import Network
import MotionCore
import ControllerLink

private struct PhoneReading { let orientation: simd_quatf; let time: Double }

final class PhoneController: ObservableObject {
    struct Lobby: Identifiable {
        let endpoint: NWEndpoint
        let name: String
        var id: String { String(describing: endpoint) }
    }
    @Published private(set) var lobbies: [Lobby] = []
    @Published var code = ""
    @Published private(set) var status = "Looking for your Mac…"
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var ready = false
    @Published private(set) var live = false
    @Published private(set) var feedback = ""
    @Published private(set) var tilt = 0.0
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive; return queue
    }()
    private let latest = LatestInputBuffer<PhoneReading>()
    private var reading: PhoneReading?
    private var calibration = PhoneOrientation()
    private var browser: NWBrowser?
    private var link: ControllerLink?
    private var session = UUID()
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var feedbackUntil = 0.0
    private let controllerID: UUID = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "aircade.controllerID"), let id = UUID(uuidString: value) { return id }
        let id = UUID(); defaults.set(id.uuidString, forKey: "aircade.controllerID"); return id
    }()
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func activate() {
        guard timer == nil else { return }
        if motion.isDeviceMotionAvailable {
            let token = latest.begin()
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] sample, error in
                guard let self, let sample else { return }
                let q = sample.attitude.quaternion
                self.latest.submit(PhoneReading(orientation: simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)), time: sample.timestamp), session: token)
            }
        } else { status = "This device has no motion sensor. Use a physical iPhone." }
        discover()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func deactivate() {
        disconnect(); browser?.cancel(); browser = nil
        motion.stopDeviceMotionUpdates(); timer?.invalidate(); timer = nil
        latest.stop()
        reading = nil; live = false; UIApplication.shared.isIdleTimerDisabled = false
    }
    private func discover() {
        let browser = NWBrowser(for: .bonjour(type: ControllerLink.serviceType, domain: nil), using: ControllerLink.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.lobbies = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return Lobby(endpoint: result.endpoint, name: name)
                }.sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting = state {
                DispatchQueue.main.async { self?.status = "Allow Local Network access in Settings, then reopen this app." }
            }
        }
        browser.start(queue: DispatchQueue(label: "Aircade.Discovery")); self.browser = browser
    }
    func connect(_ lobby: Lobby) {
        disconnect()
        session = UUID(); sequence = 0; connecting = true; status = "Connecting to \(lobby.name)…"
        let link = ControllerLink(connection: NWConnection(to: lobby.endpoint, using: ControllerLink.parameters()))
        self.link = link
        link.onReady = { [weak self, weak link] in
            guard let self, let link, self.link === link else { return }
            link.send(.hello(code: self.code, controller: self.controllerID, session: self.session))
        }
        link.onMessage = { [weak self, weak link] message in
            guard let self, let link, self.link === link else { return }
            switch message {
            case .welcome(let player):
                guard player == 2 else { self.disconnect(); return }
                self.connected = true; self.connecting = false
                self.status = "Player 2 · Orange"; UIApplication.shared.isIdleTimerDisabled = true
            case .poll(let request): self.sendSample(request)
            case .feedback(let cue): self.playFeedback(cue)
            case .bye(let reason): self.disconnect(); self.status = reason
            default: break
            }
        }
        link.onClose = { [weak self, weak link] reason in
            guard let self, let link, self.link === link else { return }
            self.disconnect(); self.status = "Disconnected. Check the lobby code and join again."
        }
        link.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak link] in
            guard let self, let link, self.link === link, !self.connected else { return }
            self.disconnect(); self.status = "Could not connect. Check Local Network access and use the same Wi-Fi or a personal hotspot."
        }
    }
    func disconnect() {
        let previous = link; link = nil; previous?.cancel()
        connected = false; connecting = false; ready = false; calibration = PhoneOrientation()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func recenter() {
        consume()
        guard let reading, now - reading.time < 0.25 else { return }
        calibration.recenter(reading.orientation); ready = true
        link?.send(.calibrating)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func consume() {
        if let value = latest.take() { reading = value }
    }
    private func refresh() {
        consume()
        live = reading.map { now >= $0.time && now - $0.time < 0.25 } ?? false
        if let reading, let q = calibration.calibrated(reading.orientation) {
            // SwiftUI's positive angle is clockwise on screen; a left tilt is negative.
            tilt = Double(atan2(q.act(SIMD3<Float>(0, 1, 0)).x, q.act(SIMD3<Float>(0, 1, 0)).y)) * 180 / .pi
        }
        if now > feedbackUntil { feedback = "" }
    }
    private func sendSample(_ request: UUID) {
        consume(); sequence += 1
        let age = reading.map { max(0, now - $0.time) } ?? 60
        let q = reading.flatMap { calibration.calibrated($0.orientation) }
        let frame = PlayerControllerFrame(controllerID: controllerID, sessionID: session, sequence: sequence,
            source: "iPhone", orientation: q ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), ready: q != nil && age < 0.25, sampleAge: age)
        link?.send(.sample(request: request, frame: frame))
    }
    private func playFeedback(_ cue: String) {
        feedbackUntil = now + 0.7
        switch cue {
        case "hit": feedback = "NICE HIT!"; UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "block": feedback = "CLASH!"; UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case "damage": feedback = "OUCH!"; UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "victory": feedback = "YOU WIN!"; UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "defeat": feedback = "REMATCH?"; UINotificationFeedbackGenerator().notificationOccurred(.error)
        default: feedback = "DRAW!"
        }
    }
}
