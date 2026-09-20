import Foundation
import MotionCore
import simd
import SwiftUI

enum AircadeSport: String, CaseIterable {
    case neonRush = "Neon Rush"
    case tennis = "Tennis"
}

final class TennisGame: ObservableObject {
    var displayPhase: TennisPhase { state.phase }
    @Published private(set) var state = TennisMatch()
    @Published var codexPractice = false
    @Published private(set) var tacticalProvider = "baseten"
    private(set) var playerCourtX: Float = 0
    var opponentReady: Bool { codexPractice || modelOpponent == nil || modelOpponent?.hasModelPlan == true }
    func prepareOpponent() {
        guard !codexPractice, !opponentInspectorOpen, state.phase != .paused else { return }
        if state.phase == .menu || state.phase == .results { modelOpponent?.resume() }
        modelOpponent?.refresh(playerID: activePlayerID?(), match: state)
    }
    func selectTacticalOpponent(_ provider: String) {
        guard ["baseten", "jev", "astra"].contains(provider) else { return }
        leave(); codexPractice = false; tacticalProvider = provider
        modelOpponent?.select(provider: provider)
        opponentStatus = TennisOpponentStatus(provider: provider, modelVersion: "connecting", decision: "Preparing model shot")
        prepareOpponent()
    }
    func selectCodexOpponent() {
        leave()
        codexPractice = true
        opponentStatus = TennisOpponentStatus(provider: "codex", modelVersion: "computer-use", decision: "Waiting for Codex to control the rival")
    }
    @Published var enabled = false
    @Published var inputReady = false
    @Published var feedback = ""
    @Published var feedbackPoints = 0
    @Published var feedbackGood = true
    @Published var pauseReason = "Take a breath."
    @Published var bestScore = 0
    @Published var newRecord = false
    @Published var sound = true
    @Published private(set) var isDemo = false
    @Published private(set) var recoveringInput = false
    @Published private(set) var opponentStatus = TennisOpponentStatus()

    var authorizeRun: (() -> Bool)?
    private(set) var runID: String?
    var onRunStarted: ((Bool) -> String?)?
    var onRunResumed: ((String?) -> Void)?
    var onRunFinished: ((TennisMatch, Bool, String?) -> Bool)?
    var onRunAbandoned: ((String?) -> Void)?
    var onJudgment: ((TennisEvent) -> Void)?
    var pollInput: (() -> Void)?
    var activePlayerID: (() -> String?)?

    private let scene: SaberScene
    private let opponent: any TennisOpponentStrategy
    private let codexOpponent = AutomaticReboundOpponent()
    private let modelOpponent: BasetenTennisOpponent?
    private let clock: () -> Double
    private let scoreDefaults: UserDefaults
    private var timer: Timer?
    private var lastTick: Double
    private var previousPose: SaberPose?
    private var previousUserPose: SaberPose?
    private var previousTime: Double?
    private var previousBall: (id: Int, point: SIMD3<Float>)?
    private var lastInput = 0.0
    private var feedbackUntil = 0.0
    private var resultSaved = false
    private var opponentInspectorOpen = false
    private var recoveryStartedAt = 0.0
    @Published private(set) var manualOpponentEnabled = false
    @Published private(set) var manualOpponentX: Float = 0

    init(scene: SaberScene, opponent: any TennisOpponentStrategy = BasetenTennisOpponent(), automaticTimer: Bool = true,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, scoreDefaults: UserDefaults = .standard) {
        self.scene = scene
        self.opponent = opponent
        self.modelOpponent = opponent as? BasetenTennisOpponent
        self.clock = clock
        self.scoreDefaults = scoreDefaults
        self.lastTick = clock()
        self.bestScore = scoreDefaults.integer(forKey: "tennis.best")
        self.modelOpponent?.onStatus = { [weak self] status in self?.opponentStatus = status }
        if automaticTimer {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private var now: Double { clock() }
    var liveReady: Bool { inputReady && now - lastInput < ArcadeGame.freshInputAge }

    func start(demo: Bool = false) {
        guard enabled, !opponentInspectorOpen else { return }
        if let authorizeRun, !authorizeRun() { return }
        guard liveReady else { return }
        guard demo || opponentReady else { prepareOpponent(); return }
        if !resultSaved { onRunAbandoned?(runID) }
        runID = onRunStarted?(demo || codexPractice)
        isDemo = demo || codexPractice
        if !codexPractice { modelOpponent?.beginRun() }
        state.start()
        state.assistedOpponent = codexPractice
        resultSaved = false
        newRecord = false
        feedback = ""
        previousPose = nil
        previousBall = nil
        previousTime = nil
        recoveringInput = false
        manualOpponentEnabled = codexPractice
        manualOpponentX = 0
        state.updateOpponentControl(positionX: codexPractice ? 0 : nil, didSwing: false)
        lastTick = now
        playerCourtX = 0
        scene.clearTennis()
        if !codexPractice { modelOpponent?.refresh(playerID: activePlayerID?(), match: state) }
    }

    func pause(_ reason: String = "Take a breath.") {
        modelOpponent?.suspend()
        guard state.phase == .playing || state.phase == .countdown else { return }
        pauseReason = reason
        state.pause()
        recoveringInput = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
    }

    func resume() {
        guard state.phase == .paused, liveReady, !opponentInspectorOpen else { return }
        state.resume()
        lastTick = now
        recoveringInput = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
        onRunResumed?(runID)
        if !codexPractice {
            modelOpponent?.resume()
            prepareOpponent()
        }
    }

    func suspendOpponentForInspector() {
        opponentInspectorOpen = true
        pause("Sensor explanation is open. Check your controller, then resume.")
    }

    func dismissOpponentInspector() {
        opponentInspectorOpen = false
        // Active matches remain explicitly paused; lobby/results can prepare
        // their next decision without advancing physics or changing the run.
        if state.phase == .menu || state.phase == .results { prepareOpponent() }
    }

    func leave() {
        modelOpponent?.endRun()
        if !resultSaved, runID != nil { onRunAbandoned?(runID) }
        runID = nil
        state.quit()
        scene.clearTennis()
        feedback = ""
        recoveringInput = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
    }

    func observeSimulatedInput(_ simulated: Bool) {
        if simulated && (state.phase == .playing || state.phase == .countdown || state.phase == .paused) {
            isDemo = true
        }
    }

    func invalidateInput(_ reason: String = "Controller tracking paused. Reconnect or recenter, then resume.") {
        inputReady = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
        recoveringInput = false
        // Model preparation is independent of controller readiness in the lobby
        // and results. Only a running match needs its model work suspended for
        // tracking loss; explicit pause/inspector/end-run still cancel any phase.
        if state.phase == .playing || state.phase == .countdown { pause(reason) }
    }

    func waitForFreshInput() {
        inputReady = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
        guard state.phase == .playing || state.phase == .countdown else { return }
        let age = now - lastInput
        if age >= ArcadeGame.trackingLossDelay {
            invalidateInput("No controller motion for 1 second. Reconnect or recenter, then resume.")
        } else if !recoveringInput {
            recoveringInput = true
            recoveryStartedAt = lastInput
        }
    }

    func update(pose: SaberPose, time: Double, ready: Bool) {
        guard enabled else { return }
        guard ready else { invalidateInput(); return }
        guard time.isFinite, time >= lastInput else { return }
        inputReady = true
        lastInput = time
        let rawPose = pose
        let pose = SaberPose(position: pose.position + SIMD3<Float>(playerCourtX, 0, 0), orientation: pose.orientation)
        guard state.phase == .playing else { previousPose = nil; previousTime = nil; previousBall = nil; return }
        if let previousTime, time <= previousTime { return }
        defer {
            previousUserPose = rawPose
            previousPose = pose; previousTime = time
            previousBall = state.ball.flatMap { $0.direction == .towardPlayer ? ($0.id, $0.position(at: state.elapsed)) : nil }
        }
        guard !recoveringInput, let previousPose, let previousTime, let previousBall,
              let ball = state.ball, ball.direction == .towardPlayer, ball.id == previousBall.id else { return }
        // Automatic running must not count as a user swing.
        let rotation = (pose.orientation * previousPose.orientation.inverse).angle
        let userTranslation = previousUserPose.map { simd_distance(rawPose.position, $0.position) / Float(time - previousTime) } ?? 0
        guard min(rotation, 2 * .pi - rotation) / Float(time - previousTime) > 0.5 || userTranslation > 0.75 else { return }
        let centre = ball.position(at: state.elapsed)
        guard let contact = RacketGeometry.sweep(from: previousPose, to: pose, dt: time - previousTime,
                                                  ballFrom: previousBall.point, ballTo: centre),
              let shot = TennisShotResponse.make(contact: contact),
              let event = state.playerHit(speed: shot.swingSpeed, targetX: shot.targetX,
                                         flightDuration: shot.flightDuration, contactPoint: contact.point) else { return }
        handle(event, point: contact.point, velocity: contact.velocity)
        scene.syncTennis(ball: state.ball, elapsed: state.elapsed, manualOpponent: manualOpponentEnabled)
    }

    func tick() {
        guard enabled else { return }
        pollInput?()
        let time = now
        let delta = time - lastTick
        lastTick = time
        if feedbackUntil < time { feedback = "" }
        guard state.phase == .playing || state.phase == .countdown else { return }
        guard liveReady else { waitForFreshInput(); return }
        if recoveringInput {
            recoveringInput = false
            _ = recoveryStartedAt
            return
        }
        guard delta.isFinite, delta > 0 else { return }
        if delta > 0.1 { previousPose = nil; previousTime = nil; previousBall = nil }
        // Codex gets a continuous, readable six-ish second flight. Its swing is
        // buffered by TennisMatch, so computer-control latency does not require
        // stopping the ball at the far baseline.
        let pace = state.assistedOpponent && state.ball?.direction == .towardOpponent ? 0.45 : 1.0
        for event in state.advance(min(delta, 0.1) * pace, opponent: codexPractice ? codexOpponent : opponent) {
            handle(event, point: state.ball?.position(at: state.elapsed) ?? SIMD3<Float>(0, 0, 0), velocity: .zero)
        }
        let target = state.ball.flatMap { $0.direction == .towardPlayer ? $0.to.x : nil } ?? 0
        let step = Float(min(delta, 0.1)) * 6
        playerCourtX += min(step, max(-step, target - playerCourtX))
        scene.setTennisPlayerX(playerCourtX)
        scene.syncTennis(ball: state.ball, elapsed: state.elapsed, manualOpponent: manualOpponentEnabled)
        if state.phase == .results { finish() }
    }

    /// Direct mouse control from the live court. The AirPod continues to drive
    /// the near player's racket while the pointer drives the far opponent.
    func moveOpponent(to positionX: Float) {
        guard state.phase == .playing || state.phase == .countdown else { return }
        manualOpponentEnabled = true
        manualOpponentX = max(-4.6, min(4.6, positionX))
        state.updateOpponentControl(positionX: manualOpponentX, didSwing: false)
        scene.setTennisOpponentManual(positionX: manualOpponentX,
                                      targetX: state.ball?.direction == .towardOpponent ? state.ball?.to.x : nil,
                                      swing: false,
                                      enabled: true)
    }

    func swingOpponent() {
        guard state.phase == .playing else { return }
        if !manualOpponentEnabled { moveOpponent(to: 0) }
        state.updateOpponentControl(positionX: manualOpponentX, didSwing: true)
        scene.setTennisOpponentManual(positionX: manualOpponentX,
                                      targetX: state.ball?.direction == .towardOpponent ? state.ball?.to.x : nil,
                                      swing: true,
                                      enabled: true)
    }

    func restoreAutomaticOpponent() {
        manualOpponentEnabled = false
        state.updateOpponentControl(positionX: nil, didSwing: false)
    }

    private func handle(_ event: TennisEvent, point: SIMD3<Float>, velocity: SIMD3<Float>) {
        onJudgment?(event)
        feedbackUntil = now + 0.9
        switch event {
        case .opponentPreparing(let contactX, let stroke, let delay):
            if !manualOpponentEnabled { scene.prepareTennisOpponent(contactX: contactX, stroke: stroke, delay: delay) }
        case .opponentReturn(let contactX, let stroke):
            if !codexPractice { modelOpponent?.markReturnApplied() }
            feedbackGood = true
            feedbackPoints = 0
            feedback = state.rally == 0 ? "SERVE" : "RETURNING"
            if manualOpponentEnabled { scene.tennisImpact(at: SIMD3<Float>(contactX, 0.05, -18), velocity: .zero) }
            else { scene.tennisOpponentHit(contactX: contactX, stroke: stroke) }
        case .playerReturn(let points):
            feedbackGood = true
            feedbackPoints = points
            feedback = state.rally >= 8 ? "HOT RALLY" : state.rally >= 4 ? "NICE RETURN" : "GOOD SHOT"
            scene.tennisImpact(at: point, velocity: velocity)
            if sound { GameAudio.shared.play("Pop") }
            if !codexPractice { prepareOpponent() }
        case .opponentMiss(let ballX, let attemptedX, let points):
            feedbackGood = true
            feedbackPoints = points
            feedback = "WINNER"
            scene.tennisOpponentMiss(ballX: ballX, attemptedX: attemptedX)
            if sound { GameAudio.shared.play("Pop") }
        case .miss:
            feedbackGood = false
            feedbackPoints = 0
            feedback = "OUT OF REACH"
            if sound { GameAudio.shared.play("Tink") }
            if !codexPractice { prepareOpponent() }
        case .finished:
            break
        }
    }

    private func finish() {
        guard !resultSaved else { return }
        resultSaved = true
        modelOpponent?.suspend()
        let eligible = onRunFinished?(state, isDemo, runID) ?? !isDemo
        if eligible && !isDemo && state.score > bestScore {
            bestScore = state.score
            newRecord = true
            scoreDefaults.set(bestScore, forKey: "tennis.best")
        }
        scene.clearTennis()
    }
}
