import AppKit
import MotionCore
import simd
import SwiftUI

final class ArcadeGame: ObservableObject {
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

    init(scene: SaberScene) {
        self.scene = scene
        bestScore = UserDefaults.standard.integer(forKey: "neonRush.best.Arcade")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    var liveReady: Bool { inputReady && now - lastInput < 0.25 }

    func refreshBest() { bestScore = UserDefaults.standard.integer(forKey: "neonRush.best.\(difficulty.rawValue)") }
    func start(demo: Bool) {
        guard enabled, liveReady else { return }
        isDemo = demo; resultSaved = false; newRecord = false
        refreshBest()
        state.start(difficulty: difficulty, seed: UInt64(Date().timeIntervalSince1970))
        previousPose = nil; previousTime = nil; feedback = ""; lastTick = now
        scene.clearRush()
        onEvent?("RUSH_START difficulty=\(difficulty.rawValue) demo=\(demo)")
    }
    func pause(_ reason: String = "Take a breath.") {
        guard state.phase == .playing || state.phase == .countdown else { return }
        pauseReason = reason; state.pause()
        previousPose = nil; previousTime = nil
        onEvent?("RUSH_PAUSE \(reason)")
    }
    func resume() {
        guard liveReady else { return }
        state.resume(); lastTick = now
        previousPose = nil; previousTime = nil
    }
    func leave() {
        state.quit(); scene.clearRush(); feedback = ""
        previousPose = nil; previousTime = nil
    }
    func invalidateInput() {
        inputReady = false; previousPose = nil; previousTime = nil
        pause("Controller tracking paused. Reconnect or recenter, then resume.")
    }
    func update(pose: SaberPose, time: Double, ready: Bool) {
        guard enabled else { return }
        guard ready else { invalidateInput(); return }
        inputReady = true; lastInput = time
        guard state.phase == .playing else { previousPose = nil; previousTime = nil; return }
        defer { previousPose = pose; previousTime = time }
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
        scene.syncRush(targets: state.targets, elapsed: state.elapsed)
    }
    private func tick() {
        let t = now; let dt = t - lastTick; lastTick = t
        guard enabled else { return }
        if feedbackUntil < t && !feedback.isEmpty { feedback = "" }
        if state.phase == .playing || state.phase == .countdown {
            guard liveReady else { invalidateInput(); return }
            guard dt < 0.3 else { pause("The game was interrupted. Resume when you're ready."); return }
            let oldRound = state.round
            let events = state.advance(dt)
            for event in events { judge(event, point: event.target.position(at: state.elapsed), velocity: .zero) }
            if state.round != oldRound && state.phase == .playing {
                feedback = state.roundName; feedbackGood = true; feedbackPoints = 0; feedbackUntil = t + 1.5
                if sound { NSSound(named: "Glass")?.play() }
            }
            scene.syncRush(targets: state.targets, elapsed: state.elapsed)
            if state.phase == .results { finish() }
        }
    }
    private func judge(_ event: RushJudgment, point: SIMD3<Float>, velocity: SIMD3<Float>) {
        feedbackPoints = event.points
        feedbackUntil = now + 0.9
        switch event.kind {
        case .cut, .perfect:
            feedbackGood = true
            feedback = event.kind == .perfect ? "PERFECT" : "CLEAN CUT"
            scene.burstRushTarget(event.target, at: point, velocity: velocity)
            scene.impact(at: point, kind: .cut, velocity: velocity)
            if sound { NSSound(named: "Pop")?.play() }
        case .wrongDirection:
            feedbackGood = false; feedback = "WRONG WAY"
            scene.impact(at: point, kind: .glance, velocity: velocity)
            if sound { NSSound(named: "Tink")?.play() }
        case .hazard:
            feedbackGood = false; feedback = "HAZARD HIT"
            scene.impact(at: point, kind: .damage, velocity: velocity)
            if sound { NSSound(named: "Basso")?.play() }
        case .miss:
            feedbackGood = false; feedback = "MISSED"
            if sound { NSSound(named: "Tink")?.play() }
        }
        onEvent?("RUSH_\(event.kind) target=\(event.target.id) points=\(event.points) combo=\(state.combo) lives=\(state.lives)")
    }
    private func finish() {
        guard !resultSaved else { return }
        resultSaved = true
        if !isDemo && state.score > bestScore {
            bestScore = state.score; newRecord = true
            UserDefaults.standard.set(bestScore, forKey: "neonRush.best.\(difficulty.rawValue)")
        }
        scene.clearRush()
        onEvent?("RUSH_FINISH score=\(state.score) completed=\(state.completed) demo=\(isDemo)")
    }
}
