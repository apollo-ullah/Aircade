import AppKit
import Combine
import Foundation
import MotionCore

/// Owns only experimental challenge state. It never submits a legacy Tennis score.
final class AIChallengeGame: ObservableObject {
    @Published private(set) var match = AIChallengeMatch()
    @Published var status = "Connect the arena to get started"
    @Published var lastAction = "No action yet"
    @Published var latencyMS = 0
    @Published var lastObservation: NSImage?
    @Published var captureMS = 0.0
    @Published var observationAge = 0.0
    @Published var manualURL: URL?
    @Published var connected = false
    @Published var manual = false
    @Published var provider = "astra"
    @Published var exhibition = false
    @Published var partner: AIChallengeGame?
    let scores = AIChallengeScores()
    private var interrupted = false
    private var scoreSaved = false
    private var bridgeOnly = false
    private var observationHistory: [[String: Any]] = []
    private var onCommand: ((TennisControlCommand, Double) -> Void)?
    private var onFailure: ((String) -> Void)?
    var scoreMessage: String {
        if let error = scores.error { return error }
        if exhibition { return "AI exhibition · Not ranked" }
        if simulated || manual { return "Rehearsal · Not ranked" }
        if interrupted { return "Interrupted run · Not ranked" }
        if playerID == nil { return "Guest run · Scan a badge to rank" }
        if !playerPublic { return "Saved privately · Public ranking is off for this badge" }
        return "Saved to this Mac's \(opponentName) challenge board"
    }
    var readyToStart: Bool {
        connected && !status.hasPrefix("Unavailable") && !status.hasSuffix("budget reached") && (!exhibition || partner?.readyToStart == true)
    }
    var opponentName: String { provider == "jev" ? "Jev" : "Astra" }
    var winner: String { match.humanPoints == match.aiPoints ? "Draw" : match.humanPoints > match.aiPoints ? (exhibition ? "Jev wins!" : "You win!") : "\(opponentName) wins!" }

    @Published var playerName = "Guest"
    private(set) var playerID: String?
    private var playerPublic = false
    @Published var pauseReason = "Match paused"
    @Published var simulated = false
    private let scene: SaberScene
    private var process: Process?
    private var pipe: Pipe?
    private var base: URL?
    private var token = ""
    private var session = URLSession(configuration: .ephemeral)
    private var lastObservationID = -1
    private var frame = 0
    private var frames: [Int: Double] = [:]
    private var lastCapture = 0.0
    private var lastPoll = 0.0
    private var uploading = false
    private var polling = false
    private var generation = UUID()
    private var previous: (pose: SaberPose, time: Double, ball: SIMD3<Float>, id: Int)?
    init(scene: SaberScene) { self.scene = scene }
    deinit { process?.terminate() }

    func connect(manual: Bool = false, provider: String = "astra", exhibition: Bool = false) {
        disconnect()
        self.manual = manual; self.provider = provider; self.exhibition = exhibition
        if exhibition && !bridgeOnly {
            let partner = AIChallengeGame(scene: scene); partner.bridgeOnly = true
            partner.onCommand = { [weak self] command, age in _ = self?.match.apply(command, observationAge: age, near: true) }
            partner.onFailure = { [weak self] reason in self?.pause(reason) }
            self.partner = partner; partner.connect(provider: "jev")
        }
        status = "Connecting arena…"
        let process = Process(), pipe = Pipe()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", root.appendingPathComponent("tools/astra-arena/server.mjs").path]
        process.currentDirectoryURL = root
        lastObservation = nil; lastObservationID = -1; lastAction = "No action yet"; latencyMS = 0
        token = UUID().uuidString
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        environment["AIRCADE_ARENA_TOKEN"] = token
        environment["AIRCADE_ARENA_PROVIDER"] = provider
        environment["AIRCADE_ARENA_MANUAL"] = manual ? "1" : "0"
        process.environment = environment; process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let epoch = generation
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = object["url"] as? String, let manualURL = object["manualURL"] as? String else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == epoch else { return }
                self.base = URL(string: url); self.manualURL = URL(string: manualURL)
                self.connected = true; self.status = manual ? "Manual opponent ready" : "\(self.opponentName) arena ready"
            }
        }
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async {
            guard let self, self.generation == epoch else { return }
            self.connected = false; self.status = "Arena stopped. Reconnect to try again."
            self.onFailure?("Arena disconnected"); self.pause("Arena disconnected")
        }}
        self.process = process; self.pipe = pipe
        do { try process.run() } catch { status = "Cannot launch arena: install Node and the arena dependencies." }
    }
    func start(playerName: String, simulated: Bool, playerID: String? = nil, publicProfile: Bool = false, rehearsalSeed: Int = 0) {
        guard readyToStart else { return }
        self.playerName = playerName; self.playerID = playerID; self.playerPublic = publicProfile; self.simulated = simulated
        interrupted = false; scoreSaved = false
        match.start(seed: rehearsalSeed, exhibition: exhibition); observationHistory = []; previous = nil; frames = [:]; lastCapture = 0
        scene.clearTennis(); scene.syncChallenge(match)
    }
    func pause(_ reason: String) {
        guard match.phase == .playing else { return }
        interrupted = true
        match.pause(); partner?.frames = [:]; partner?.lastCapture = 0; previous = nil; pauseReason = reason; frames = [:]; lastCapture = 0
    }
    func resume() { match.resume(); partner?.frames = [:]; partner?.lastCapture = 0; previous = nil; frames = [:]; lastCapture = 0 }
    func disconnect() {
        partner?.disconnect(); partner = nil
        generation = UUID(); session.invalidateAndCancel(); session = URLSession(configuration: .ephemeral)
        pipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; pipe = nil; connected = false; base = nil; manualURL = nil
        match.stop(); if !bridgeOnly { scene.clearTennis() }; frames = [:]; previous = nil; uploading = false; polling = false
        if !bridgeOnly { scene.endChallenge() }
    }
    func input(pose: SaberPose, time: Double) {
        guard match.phase == .playing, let ball = match.ball, ball.direction == .towardPlayer else { previous = nil; return }
        if let previous, time <= previous.time { return }
        defer { previous = (pose, time, ball.position(at: match.elapsed), ball.id) }
        if let old = previous, let contact = match.humanContact(from: old.pose, to: pose, dt: time - old.time, ballFrom: old.ball, flightID: old.id) {
            scene.tennisImpact(at: contact.point, velocity: contact.velocity)
            GameAudio.shared.play("Pop")
        }
    }
    func tick(delta: Double, now: Double, inputReady: Bool) {
        if match.phase == .playing && !bridgeOnly {
            if !inputReady { previous = nil } // A brief stale sample must not freeze the game clock.
            if let contact = match.advance(min(0.1, delta)) {
                scene.tennisImpact(at: contact.point, velocity: contact.velocity)
                GameAudio.shared.play("Pop")
            }
            scene.syncChallenge(match)
        }
        if match.phase == .results && !scoreSaved && !bridgeOnly {
            scoreSaved = true
            scores.record(AIChallengeScore(id: match.run, playerID: playerID, nickname: playerName,
                provider: provider, model: provider == "jev" ? "typesafe-ai/jev" : "gpt-6-astra",
                controlMode: provider == "jev" ? "state" : "screen", rules: "controlled-v1", flightSeconds: 8,
                human: match.humanPoints, opponent: match.aiPoints, simulated: simulated, exhibition: exhibition,
                assisted: manual, interrupted: interrupted, completed: true, createdAt: Date(), isPublic: playerPublic))
        }
        if let partner {
            if partner.match.run != match.run || partner.match.rally != match.rally || partner.match.phase != match.phase {
                partner.frames = [:]; partner.lastCapture = 0; partner.observationHistory = []
            }
            partner.match = match; partner.tick(delta: delta, now: now, inputReady: true) }
        guard connected else { return }
        if now - lastCapture >= (provider == "jev" ? 0.2 : 0.5) && !uploading {
            lastCapture = now
            let began = ProcessInfo.processInfo.systemUptime
            if let jpeg = provider == "jev" ? Data() : scene.challengeJPEG(near: bridgeOnly) {
                captureMS = (ProcessInfo.processInfo.systemUptime - began) * 1000
                frame += 1; frames[frame] = now
                frames = frames.filter { now - $0.value <= 6 }
                var meta: [String: Any] = ["run":match.run,"rally":match.rally,"frame":frame,"captured":now,"playing":match.phase == .playing]
                if provider == "jev" {
                    var observed: [String: Any] = ["time":match.elapsed,"racketX":bridgeOnly ? match.nearController.x : match.controller.x,
                        "swinging":bridgeOnly ? match.nearController.swinging : match.controller.swinging]
                    if let ball = match.ball {
                        let p = ball.position(at: match.elapsed)
                        observed["ball"] = ["x":bridgeOnly ? -p.x : p.x,"y":p.y,"z":bridgeOnly ? -18 - p.z : p.z]
                        observed["incoming"] = bridgeOnly ? ball.direction == .towardPlayer : ball.direction == .towardOpponent
                    } else { observed["incoming"] = false }
                    observationHistory.append(observed); observationHistory = Array(observationHistory.suffix(4))
                    meta["observation"] = ["recentObservations":observationHistory,"racketSpeedLimit":3,"strokeSeconds":3]
                }
                uploading = true
                send("frame", data: jpeg, meta: meta) { [weak self] _ in self?.uploading = false }
            }
        }
        if now - lastPoll >= 0.1 && !polling {
            polling = true; lastPoll = now
            send("poll") { [weak self] data in
                guard let self else { return }; self.polling = false
                guard let data, let payload = try? JSONDecoder().decode(Poll.self, from: data) else { return }
                self.status = payload.status.state; self.latencyMS = payload.status.latencyMS; self.lastAction = payload.status.lastAction
                if self.status.hasPrefix("Unavailable") || self.status.hasSuffix("budget reached") { self.onFailure?(self.status); self.pause(self.status) }
                if payload.status.observationID != self.lastObservationID {
                    self.lastObservationID = payload.status.observationID
                    self.send("last-observation") { [weak self] data in if let data { self?.lastObservation = NSImage(data: data) } }
                }
                let received = ProcessInfo.processInfo.systemUptime
                for command in payload.commands {
                    guard let captured = self.frames[command.frame] else { continue }
                    self.observationAge = received - captured
                    if let onCommand = self.onCommand { onCommand(command, received - captured) }
                    else { _ = self.match.apply(command, observationAge: received - captured) }
                }
            }
        }
    }
    private struct Poll: Decodable {
        var commands: [TennisControlCommand]
        var status: Status
        struct Status: Decodable { var state: String; var latencyMS: Int; var lastAction: String; var observationID: Int }
    }
    private func send(_ path: String, data: Data? = nil, meta: [String: Any]? = nil, completion: @escaping (Data?) -> Void) {
        guard let base else { completion(nil); return }
        var request = URLRequest(url: base.appendingPathComponent(path)); request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let data { request.httpMethod = "POST"; request.httpBody = data; request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type") }
        if let meta, let encoded = try? JSONSerialization.data(withJSONObject: meta), let text = String(data: encoded, encoding: .utf8) { request.setValue(text, forHTTPHeaderField: "X-Aircade-Meta") }
        let epoch = generation
        session.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == epoch else { return }
                completion((response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
            }
        }.resume()
    }
}
