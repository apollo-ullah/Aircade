import Foundation
import Combine
import Network
import MotionCore
import ControllerLink
import simd

/// Duel presentation and match only; the app's ControllerSession owns connectivity.
final class MultiplayerModel: ObservableObject {
    @Published private(set) var match = SaberDuel()
    @Published private(set) var ready = [false, false]
    @Published private(set) var feedback = ""
    @Published private(set) var scripted = false
    let scene = DuelScene()
    let controllers: ControllerSession
    private weak var legacyMotion: MotionModel?
    private var observations: Set<AnyCancellable> = []
    private var timer: Timer?
    private var feedbackRun: UUID?
    private var runAssignments: [PlayerSlot: ControllerDevice] = [:]
    private var feedbackUntil = 0.0
    private var scriptStart = 0.0
    var clock: () -> Double
    var code: String { controllers.phoneHost.code }
    var networkStatus: String { controllers.phoneHost.networkStatus }
    var phoneStatus: String { controllers.phoneHost.status }
    var latency: Double { controllers.phoneHost.latency }
    var bothReady: Bool { ready.allSatisfy { $0 } }
    var listeningPort: NWEndpoint.Port? { controllers.phoneHost.listeningPort }
    func orientation(_ player: PlayerSlot) -> simd_quatf? { controllers.snapshot(for: player)?.orientation }
    func name(_ player: PlayerSlot) -> String {
        if scripted { return player == .one ? "Scripted blue" : "Scripted orange" }
        return controllers.device(for: player).map { controllers.name(for: $0) } ?? "Unassigned"
    }
    var localName: String { name(.one) }

    init(controllers: ControllerSession) {
        self.controllers = controllers; clock = controllers.clock
        controllers.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        controllers.invalidations.sink { [weak self] device, reason in
            guard let self, !self.scripted, self.controllers.duelAssignments.values.contains(device) else { return }
            self.pause(reason)
        }.store(in: &observations)
        controllers.assignmentChanges.sink { [weak self] in
            self?.pause("Controller assignment changed. Hold both controllers upright, then resume.")
        }.store(in: &observations)
    }
    // Compatibility while the root adapter migrates. Production uses init(controllers:).
    convenience init(motion: MotionModel) {
        self.init(controllers: ControllerSession()); legacyMotion = motion
    }
    func open() {
        guard timer == nil else { return }
        controllers.start(); controllers.setDuelActive(true)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    /// Leaving a game must never destroy its physical controller connection.
    func close() {
        timer?.invalidate(); timer = nil
        endFeedback(); controllers.setDuelActive(false)
        ready = [false, false]; match = SaberDuel(); scripted = false
    }
    func start() {
        guard bothReady else { return }
        endFeedback()
        if !scripted { feedbackRun = controllers.beginRun(); runAssignments = controllers.duelAssignments }
        feedback = ""; match.start(); scriptStart = clock() + 3.1
    }
    func pause(_ reason: String = "Match paused.") { match.pause(reason) }
    func resume() {
        if bothReady {
            if !scripted { endFeedback(); feedbackRun = controllers.beginRun(); runAssignments = controllers.duelAssignments }
            match.resume(); scriptStart = clock() + 3.1
        }
    }
    func lobby() { endFeedback(); match = SaberDuel(); feedback = "" }
    func setScripted(_ value: Bool) {
        endFeedback(); match = SaberDuel(); scripted = value; ready = [false, false]; scriptStart = clock()
    }
    func forgetPhone() { controllers.forgetPhone() }
    private func endFeedback() {
        if let feedbackRun { controllers.endRun(feedbackRun) }
        feedbackRun = nil; runAssignments = [:]
    }
    private func send(_ cue: ControllerFeedback, to player: PlayerSlot) {
        guard let feedbackRun, let device = runAssignments[player] else { return }
        controllers.sendFeedback(run: feedbackRun, to: device, cue: cue)
    }
    func tick() {
        if let motion = legacyMotion {
            controllers.submitAirPod(orientation: motion.saber, source: motion.controllerName,
                ready: motion.hasFreshMotion && motion.calibrated && motion.calibrationStep == 0 && !motion.simulated,
                sampleTime: clock() - motion.controllerSampleAge)
        }
        let now = clock()
        var poses: [SaberPose?] = [nil, nil]
        if scripted {
            ready = [true, true]
            // Player 1 makes broad swings; player 2 holds their blade out of the way.
            let t = max(0, now - scriptStart).truncatingRemainder(dividingBy: 1.6)
            let angle: Float = t < 0.30 ? Float(t / 0.30) * -1.15 : t < 0.5 ? -1.15 : t < 0.9 ? -1.15 * Float(1 - (t - 0.5) / 0.4) : 0
            poses = [SaberDuel.pose(.one, simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))),
                     SaberDuel.pose(.two, simd_quatf(angle: -1.2, axis: SIMD3(1, 0, 0)))]
        } else {
            for player in PlayerSlot.allCases {
                let sample = controllers.snapshot(for: player)
                ready[player.rawValue] = sample?.isFresh(at: now) == true && sample?.simulated == false
                if ready[player.rawValue], let orientation = sample?.orientation {
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
                if !scripted { send(.block, to: .one); send(.block, to: .two) }
            } else {
                feedback = "\(event.player == .one ? "BLUE" : "ORANGE") SCORES!"
                GameAudio.shared.play("Pop")
                if !scripted { send(.hit, to: event.player); send(.damage, to: event.player.other) }
            }
            feedbackUntil = now + 0.8
        }
        if oldPhase != .results, match.phase == .results, !scripted {
            for player in PlayerSlot.allCases { send(match.winner == player ? .victory : match.winner == nil ? .draw : .defeat, to: player) }
        }
        if now > feedbackUntil { feedback = "" }
        scene.setHealth(match.health)
    }
}
