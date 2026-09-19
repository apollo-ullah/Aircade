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
    @Published var playerName = "Guest"
    private(set) var playerID: String?
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

    func connect(manual: Bool = false) {
        disconnect()
        self.manual = manual; status = "Connecting arena…"
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
                self.connected = true; self.status = manual ? "Manual opponent ready" : "Astra arena ready"
            }
        }
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async {
            guard let self, self.generation == epoch else { return }
            self.connected = false; self.status = "Arena stopped. Reconnect to try again."
            self.pause("Arena disconnected")
        }}
        self.process = process; self.pipe = pipe
        do { try process.run() } catch { status = "Cannot launch arena: install Node and the arena dependencies." }
    }
    func start(playerName: String, simulated: Bool, playerID: String? = nil, rehearsalSeed: Int = 0) {
        guard connected else { return }
        self.playerName = playerName; self.playerID = playerID; self.simulated = simulated
        match.start(seed: rehearsalSeed); previous = nil; frames = [:]; lastCapture = 0
        scene.clearTennis(); scene.syncChallenge(match)
    }
    func pause(_ reason: String) {
        guard match.phase == .playing else { return }
        match.pause(); previous = nil; pauseReason = reason; frames = [:]; lastCapture = 0
    }
    func resume() { match.resume(); previous = nil; frames = [:]; lastCapture = 0 }
    func disconnect() {
        generation = UUID(); session.invalidateAndCancel(); session = URLSession(configuration: .ephemeral)
        pipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; pipe = nil; connected = false; base = nil; manualURL = nil
        match.stop(); scene.clearTennis(); frames = [:]; previous = nil; uploading = false; polling = false
        scene.endChallenge()
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
        if match.phase == .playing {
            if !inputReady { previous = nil } // A brief stale sample must not freeze the game clock.
            if let contact = match.advance(min(0.1, delta)) {
                scene.tennisImpact(at: contact.point, velocity: contact.velocity)
                GameAudio.shared.play("Pop")
            }
            scene.syncChallenge(match)
        }
        guard connected else { return }
        if now - lastCapture >= 0.5 && !uploading {
            lastCapture = now
            let began = ProcessInfo.processInfo.systemUptime
            if let jpeg = scene.challengeJPEG() {
                captureMS = (ProcessInfo.processInfo.systemUptime - began) * 1000
                frame += 1; frames[frame] = now
                frames = frames.filter { now - $0.value <= 6 }
                let meta: [String: Any] = ["run":match.run,"rally":match.rally,"frame":frame,"captured":now,"playing":match.phase == .playing]
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
                if self.status.hasPrefix("Unavailable") || self.status.hasSuffix("budget reached") { self.pause(self.status) }
                if payload.status.observationID != self.lastObservationID {
                    self.lastObservationID = payload.status.observationID
                    self.send("last-observation") { [weak self] data in if let data { self?.lastObservation = NSImage(data: data) } }
                }
                let received = ProcessInfo.processInfo.systemUptime
                for command in payload.commands {
                    guard let captured = self.frames[command.frame] else { continue }
                    self.observationAge = received - captured
                    _ = self.match.apply(command, observationAge: received - captured)
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
