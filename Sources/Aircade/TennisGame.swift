import Foundation
import MotionCore
import simd
import SwiftUI

enum AircadeSport: String, CaseIterable {
    case neonRush = "Neon Rush"
    case tennis = "Tennis"
}

final class TennisGame: ObservableObject {
    @Published private(set) var state = TennisMatch()
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

    var authorizeRun: (() -> Bool)?
    private(set) var runID: String?
    var onRunStarted: ((Bool) -> String?)?
    var onRunResumed: ((String?) -> Void)?
    var onRunFinished: ((TennisMatch, Bool, String?) -> Bool)?
    var onRunAbandoned: ((String?) -> Void)?
    var onJudgment: ((TennisEvent) -> Void)?
    var pollInput: (() -> Void)?

    private let scene: SaberScene
    private let opponent: any TennisOpponentStrategy
    private let clock: () -> Double
    private let scoreDefaults: UserDefaults
    private var timer: Timer?
    private var lastTick: Double
    private var previousPose: SaberPose?
    private var previousTime: Double?
    private var previousBall: (id: Int, point: SIMD3<Float>)?
    private var lastInput = 0.0
    private var feedbackUntil = 0.0
    private var resultSaved = false
    private var recoveryStartedAt = 0.0

    init(scene: SaberScene, opponent: any TennisOpponentStrategy = AutomaticReboundOpponent(), automaticTimer: Bool = true,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, scoreDefaults: UserDefaults = .standard) {
        self.scene = scene
        self.opponent = opponent
        self.clock = clock
        self.scoreDefaults = scoreDefaults
        self.lastTick = clock()
        self.bestScore = scoreDefaults.integer(forKey: "tennis.best")
        if automaticTimer {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private var now: Double { clock() }
    var liveReady: Bool { inputReady && now - lastInput < ArcadeGame.freshInputAge }

    func start(demo: Bool = false) {
        guard enabled else { return }
        if let authorizeRun, !authorizeRun() { return }
        guard liveReady else { return }
        if !resultSaved { onRunAbandoned?(runID) }
        runID = onRunStarted?(demo)
        isDemo = demo
        state.start()
        resultSaved = false
        newRecord = false
        feedback = ""
        previousPose = nil
        previousBall = nil
        previousTime = nil
        recoveringInput = false
        lastTick = now
        scene.clearTennis()
    }

    func pause(_ reason: String = "Take a breath.") {
        guard state.phase == .playing || state.phase == .countdown else { return }
        pauseReason = reason
        state.pause()
        recoveringInput = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
    }

    func resume() {
        guard state.phase == .paused, liveReady else { return }
        state.resume()
        lastTick = now
        recoveringInput = false
        previousPose = nil
        previousBall = nil
        previousTime = nil
        onRunResumed?(runID)
    }

    func leave() {
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
        pause(reason)
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
        guard state.phase == .playing else { previousPose = nil; previousTime = nil; previousBall = nil; return }
        if let previousTime, time <= previousTime { return }
        defer {
            previousPose = pose; previousTime = time
            previousBall = state.ball.flatMap { $0.direction == .towardPlayer ? ($0.id, $0.position(at: state.elapsed)) : nil }
        }
        guard !recoveringInput, let previousPose, let previousTime, let previousBall,
              let ball = state.ball, ball.direction == .towardPlayer, ball.id == previousBall.id else { return }
        let centre = ball.position(at: state.elapsed)
        guard let contact = RacketGeometry.sweep(from: previousPose, to: pose, dt: time - previousTime,
                                                  ballFrom: previousBall.point, ballTo: centre),
              let shot = TennisShotResponse.make(contact: contact),
              let event = state.playerHit(speed: shot.swingSpeed, targetX: shot.targetX,
                                         flightDuration: shot.flightDuration, contactPoint: contact.point) else { return }
        handle(event, point: contact.point, velocity: contact.velocity)
        scene.syncTennis(ball: state.ball, elapsed: state.elapsed)
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
        for event in state.advance(min(delta, 0.1), opponent: opponent) {
            handle(event, point: state.ball?.position(at: state.elapsed) ?? SIMD3<Float>(0, 0, 0), velocity: .zero)
        }
        scene.syncTennis(ball: state.ball, elapsed: state.elapsed)
        if state.phase == .results { finish() }
    }

    private func handle(_ event: TennisEvent, point: SIMD3<Float>, velocity: SIMD3<Float>) {
        onJudgment?(event)
        feedbackUntil = now + 0.9
        switch event {
        case .opponentReturn:
            feedbackGood = true
            feedbackPoints = 0
            feedback = state.rally == 0 ? "SERVE" : "RETURNING"
        case .playerReturn(let points):
            feedbackGood = true
            feedbackPoints = points
            feedback = state.rally >= 8 ? "HOT RALLY" : state.rally >= 4 ? "NICE RETURN" : "GOOD SHOT"
            scene.tennisImpact(at: point, velocity: velocity)
            if sound { GameAudio.shared.play("Pop") }
        case .miss:
            feedbackGood = false
            feedbackPoints = 0
            feedback = "OUT OF REACH"
            if sound { GameAudio.shared.play("Tink") }
        case .finished:
            break
        }
    }

    private func finish() {
        guard !resultSaved else { return }
        resultSaved = true
        let eligible = onRunFinished?(state, isDemo, runID) ?? !isDemo
        if eligible && !isDemo && state.score > bestScore {
            bestScore = state.score
            newRecord = true
            scoreDefaults.set(bestScore, forKey: "tennis.best")
        }
        scene.clearTennis()
    }
}
