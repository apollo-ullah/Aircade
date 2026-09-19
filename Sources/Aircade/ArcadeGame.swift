import AppKit
import MotionCore
import simd
import SwiftUI

final class ArcadeGame: ObservableObject {
    // Freshness gates collision; a longer timeout confirms tracking was lost.
    // A short Bluetooth interruption must not require a manual resume.
    static let freshInputAge = 0.25
    static let trackingLossDelay = 1.0
    @Published private(set) var state = NeonRush()
    @Published var difficulty: RushDifficulty = .arcade
    @Published var enabled = true
    @Published var inputReady = false
    @Published var feedback = ""
    @Published var feedbackPoints = 0
    @Published var feedbackGood = true
    @Published var pauseReason = "Take a breath."
    @Published var bestScore = 0
    @Published var newRecord = false
    @Published var isDemo = false
    @Published var sound = true
    private let scene: SaberScene
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var previousPose: SaberPose?
    private var previousTime: Double?
    private var lastInput = 0.0
    private var feedbackUntil = 0.0
    private var resultSaved = false
    var onEvent: ((String) -> Void)?
    var onJudgment: ((RushJudgment) -> Void)?
    var pollInput: (() -> Void)?
    var renderingEnabled = true
    private let clock: () -> Double
    private let scoreDefaults: UserDefaults
    @Published private(set) var maxFeedbackSeconds = 0.0
    @Published private(set) var slowFrames = 0
    @Published private(set) var maxFrameSeconds = 0.0
    @Published private(set) var recoveringInput = false
    private(set) var transientInputGaps = 0
    private var recoveryStartedAt = 0.0

    init(scene: SaberScene, automaticTimer: Bool = true,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, scoreDefaults: UserDefaults = .standard) {
        self.scene = scene; self.clock = clock; self.scoreDefaults = scoreDefaults
        lastTick = clock()
        bestScore = scoreDefaults.integer(forKey: "neonRush.best.Arcade")
        if automaticTimer {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    private var now: Double { clock() }
    var liveReady: Bool { inputReady && now - lastInput < Self.freshInputAge }

    func refreshBest() { bestScore = scoreDefaults.integer(forKey: "neonRush.best.\(difficulty.rawValue)") }
    func start(demo: Bool, seed: UInt64? = nil) {
        guard enabled, liveReady else { return }
        maxFeedbackSeconds = 0; slowFrames = 0; maxFrameSeconds = 0
        recoveringInput = false; transientInputGaps = 0
        isDemo = demo; resultSaved = false; newRecord = false
        refreshBest()
        state.start(difficulty: difficulty, seed: seed ?? UInt64(Date().timeIntervalSince1970))
        previousPose = nil; previousTime = nil; feedback = ""; lastTick = now
        scene.clearRush()
        onEvent?("RUSH_START difficulty=\(difficulty.rawValue) demo=\(demo)")
    }
    func pause(_ reason: String = "Take a breath.") {
        guard state.phase == .playing || state.phase == .countdown else { return }
        pauseReason = reason; state.pause(); recoveringInput = false
        previousPose = nil; previousTime = nil
        onEvent?("RUSH_PAUSE \(reason)")
    }
    func resume() {
        guard liveReady else { return }
        state.resume(); lastTick = now
        recoveringInput = false
        previousPose = nil; previousTime = nil
    }
    func leave() {
        state.quit(); scene.clearRush(); feedback = ""
        recoveringInput = false
        previousPose = nil; previousTime = nil
    }
    func invalidateInput(_ reason: String = "Controller tracking paused. Reconnect or recenter, then resume.") {
        inputReady = false; previousPose = nil; previousTime = nil
        recoveringInput = false
        pause(reason)
    }
    /// Hold game time and discard collision history during a brief missing-packet
    /// interval. This never pretends an old pose is a fresh controller reading.
    func waitForFreshInput() {
        inputReady = false; previousPose = nil; previousTime = nil
        guard state.phase == .playing || state.phase == .countdown else { return }
        let age = now - lastInput
        if age >= Self.trackingLossDelay {
            invalidateInput("No controller motion for 1 second. Reconnect or recenter, then resume.")
            return
        }
        if !recoveringInput {
            recoveringInput = true; transientInputGaps += 1
            recoveryStartedAt = lastInput
            onEvent?("RUSH_INPUT_WAIT age=\(age)")
        }
    }
    func update(pose: SaberPose, time: Double, ready: Bool) {
        guard enabled else { return }
        guard ready else { invalidateInput(); return }
        inputReady = true; lastInput = time
        guard state.phase == .playing else { previousPose = nil; previousTime = nil; return }
        defer { previousPose = pose; previousTime = time }
        // The first returning pose is a new baseline, never a slash across the gap.
        guard !recoveringInput else { return }
        guard let previousPose, let previousTime else { return }
        for target in state.targets {
            let centre = target.position(at: state.elapsed)
            guard let contact = CombatGeometry.sweep(from: previousPose, to: pose, dt: time - previousTime,
                                                      center: centre, half: SIMD3<Float>(repeating: 0.31)) else { continue }
            if let event = state.contact(id: target.id, velocity: contact.velocity, speed: contact.speed, alignment: contact.cuttingAlignment) {
                judge(event, point: contact.point, velocity: contact.velocity)
                if state.phase == .results { finish(); break }
            }
        }
        if renderingEnabled { scene.syncRush(targets: state.targets, elapsed: state.elapsed) }
    }
    func tick() {
        pollInput?()
        let t = now; let dt = t - lastTick; lastTick = t
        guard enabled else { return }
        maxFrameSeconds = max(maxFrameSeconds, dt)
        if feedbackUntil < t && !feedback.isEmpty { feedback = "" }
        if state.phase == .playing || state.phase == .countdown {
            guard liveReady else { waitForFreshInput(); return }
            if recoveringInput {
                recoveringInput = false
                onEvent?("RUSH_INPUT_RECOVERED gap=\(t - recoveryStartedAt)")
                return // Don't advance through the time spent waiting for input.
            }
            guard dt.isFinite, dt > 0 else { return }
            if dt > 0.1 {
                slowFrames += 1
                previousPose = nil; previousTime = nil
                onEvent?("RUSH_SLOW_FRAME seconds=\(dt) recovered_with_fresh_input=true")
            }
            // Don't turn a one-off sound/Metal startup hitch into a modal pause or
            // fast-forward through targets. Explicit app/background and input loss
            // already have their own pause paths.
            let gameDelta = min(dt, 0.1)
            let oldRound = state.round
            let events = state.advance(gameDelta)
            for event in events { judge(event, point: event.target.position(at: state.elapsed), velocity: .zero) }
            if state.round != oldRound && state.phase == .playing {
                feedback = state.roundName; feedbackGood = true; feedbackPoints = 0; feedbackUntil = t + 1.5
                if sound { GameAudio.shared.play("Glass") }
            }
            if renderingEnabled { scene.syncRush(targets: state.targets, elapsed: state.elapsed) }
            if state.phase == .results { finish() }
        }
    }
    private func judge(_ event: RushJudgment, point: SIMD3<Float>, velocity: SIMD3<Float>) {
        let began = ProcessInfo.processInfo.systemUptime
        defer {
            let duration = ProcessInfo.processInfo.systemUptime - began
            maxFeedbackSeconds = max(maxFeedbackSeconds, duration)
            if duration > 0.05 { onEvent?("RUSH_FEEDBACK_STALL seconds=\(duration) kind=\(event.kind)") }
        }
        onJudgment?(event)
        feedbackPoints = event.points
        feedbackUntil = now + 0.9
        switch event.kind {
        case .cut, .perfect:
            feedbackGood = true
            feedback = event.kind == .perfect ? "PERFECT" : "CLEAN CUT"
            if renderingEnabled {
                scene.burstRushTarget(event.target, at: point, velocity: velocity)
                scene.impact(at: point, kind: .cut, velocity: velocity)
            }
            if sound { GameAudio.shared.play("Pop") }
        case .wrongDirection:
            feedbackGood = false; feedback = "WRONG WAY"
            if renderingEnabled { scene.impact(at: point, kind: .glance, velocity: velocity) }
            if sound { GameAudio.shared.play("Tink") }
        case .hazard:
            feedbackGood = false; feedback = "HAZARD HIT"
            if renderingEnabled { scene.impact(at: point, kind: .damage, velocity: velocity) }
            if sound { GameAudio.shared.play("Basso") }
        case .miss:
            feedbackGood = false; feedback = "MISSED"
            if sound { GameAudio.shared.play("Tink") }
        }
        onEvent?("RUSH_\(event.kind) target=\(event.target.id) points=\(event.points) combo=\(state.combo) lives=\(state.lives)")
    }
    private func finish() {
        guard !resultSaved else { return }
        resultSaved = true
        if !isDemo && state.score > bestScore {
            bestScore = state.score; newRecord = true
            scoreDefaults.set(bestScore, forKey: "neonRush.best.\(difficulty.rawValue)")
        }
        scene.clearRush()
        onEvent?("RUSH_FINISH score=\(state.score) completed=\(state.completed) demo=\(isDemo)")
    }
}
