import AppKit
import CoreMotion
import MotionCore
import simd
import SwiftUI

private struct HeadphoneReading {
    let q: simd_quatf
    let euler: SIMD3<Double>
    let rate: SIMD3<Double>
    let acceleration: SIMD3<Double>
    let timestamp: Double
    let source: String
    let receivedAt: Double
}
private enum HeadphoneDelivery {
    case sample(HeadphoneReading)
    case error(String)
}

final class MotionModel: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published var running = false
    @Published var simulated = false
    @Published var scriptedScenario: SaberScript?
    @Published var selectedScript: SaberScript = .perfectRun
    private var scriptController = ScriptedSaber(.perfectRun)
    @Published var status = "Connect AirPods, then start tracking"
    @Published var authorization = "Not requested"
    @Published var available = false
    @Published var motionServiceActive = false
    @Published var waitingForMotion = false
    @Published var motionError = ""
    @Published var source = "None"
    @Published var incomingSource = "None"
    @Published var attitude = SIMD3<Double>.zero
    @Published var rotation = SIMD3<Double>.zero
    @Published var acceleration = SIMD3<Double>.zero
    @Published var quaternion = SIMD4<Float>(0, 0, 0, 1)
    @Published var saber = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    @Published var sampleAge = Double.infinity
    @Published var frequency = 0.0
    @Published var samples = 0
    @Published var gaps = 0
    @Published var switches = 0
    @Published var swings = 0
    @Published var speed = 0.0
    @Published var speedHistory: [Double] = []
    @Published var smoothing = 0.045
    @Published var swingThreshold = 3.0
    @Published var grip = 0 { didSet { if !loadingGrip { recenter() } } }
    private var loadingGrip = false
    @Published var calibrated = false
    @Published var condition = "Handheld — left"
    @Published var testing = false
    @Published var testProgress = 0.0
    @Published var testMessage = "No hardware test completed"
    @Published var testAngle = 0.0
    @Published var logPath = ""
    @Published var logError = ""
    @Published var events: [String] = []

    @Published var useCamera = false {
        didSet {
            arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
            handAnchor = nil; handPosition = SIMD3<Float>(0, -0.5, 0)
            if !useCamera { camera.stop() }
            updateScene(at: now)
        }
    }
    @Published var cameraGain = 5.0
    @Published var calibrationStep = 0
    @Published var calibrationMessage = "Calibrate your grip so left really means left."
    @Published var hasGripCalibration = false
    @Published var calibrationError = ""
    @Published var calibrationAttempt = 0
    @Published var calibrationSource = ""
    @Published var showingLab = false
    @Published var showingMultiplayer = false
    lazy var multiplayer = MultiplayerModel(motion: self)
    @Published var selectedSport: AircadeSport = .neonRush
    let players = PlayerSession()
    let camera = HandTracker()
    let scene = SaberScene()
    lazy var arena = TrainingArena(scene: scene)
    lazy var game = ArcadeGame(scene: scene, clock: { [weak self] in self?.now ?? ProcessInfo.processInfo.systemUptime })
    lazy var tennis = TennisGame(scene: scene, clock: { [weak self] in self?.now ?? ProcessInfo.processInfo.systemUptime })
    private var customBasis: simd_quatf?
    // Temporarily bypass the newer calibration at the user's request. Retained below
    // for comparison; the live app defaults to three instantaneous manual captures.
    var useSimpleCalibration = true
    var openCalibrationWhenReady = false
    private var simpleCalibration = SimpleGripCalibration()
    private var calibrationSession: GripCalibrationSession?
    private var sourceLock = MotionSourceLock()
    private var lastReportedAt: Double?
    private var handAnchor: CGPoint?
    private var handPosition = SIMD3<Float>(0, -0.5, 0)
    private var lastHandTime = 0.0
    let logDirectory: URL
    private var manager: CMHeadphoneMotionManager?
    private let motionInbox = LatestInputBuffer<HeadphoneDelivery>()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Aircade.HeadphoneMotion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var inputTimer: Timer?
    private var trackingStartedAt = 0.0
    private var timer: Timer?
    private var demoTimer: Timer?
    private var tracker = OrientationTracker()
    private var continuity = ContinuityTracker()
    private var trial = ContinuityTracker()
    private var detector = SwingDetector()
    private var rawOrientation: simd_quatf?
    private var trialReference: simd_quatf?
    private var trialCondition = ""
    private var lastReceived: Double?
    private var lastSensorTime: Double?
    private var arrivals: [Double] = []
    private var log: FileHandle?
    private var lastHealthWrite = 0.0
    private var demoOrigin = 0.0

    override convenience init() {
        self.init(logDirectory: ProcessInfo.processInfo.environment["AIRCADE_LOG_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    init(logDirectory customLogDirectory: URL?) {
        logDirectory = customLogDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aircade/Logs", isDirectory: true)
        super.init()
        game.authorizeRun = { [weak self] in self?.players.authorize() ?? false }
        game.onRunStarted = { [weak self] demo in self?.players.beginRun(demo: demo) }
        game.onRunFinished = { [weak self] state, demo in self?.players.finishRun(state, demo: demo) }
        tennis.authorizeRun = { [weak self] in self?.players.authorize() ?? false }
        tennis.onRunStarted = { [weak self] in self?.players.beginRun(demo: false) }
        tennis.onRunFinished = { [weak self] state in self?.players.finishTennis(state, demo: false) }
        tennis.enabled = false
        arena.enabled = false
        scene.setSport(.neonRush)
        scene.setArcadeVisible(true)
        game.onEvent = { [weak self] message in self?.event(message) }
        game.pollInput = { [weak self] in
            guard let self else { return }
            if self.scriptedScenario != nil { self.updateScriptedSaber() }
            else { self.consumeMotion() }
        }
        tennis.pollInput = { [weak self] in self?.consumeMotion() }
        arena.onEvent = { [weak self] message in self?.event(message) }
        camera.onPoint = { [weak self] point, time in self?.receiveHand(point, time: time) }
        camera.onLost = { [weak self] in
            guard let self else { return }
            self.handAnchor = nil
            if self.useCamera { self.arena.invalidateInput(); self.game.invalidateInput(); self.tennis.invalidateInput(); self.scene.setLive(false) }
        }
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        let inputTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.consumeMotion() }
        RunLoop.main.add(inputTimer, forMode: .common)
        self.inputTimer = inputTimer
    }

    // Injectable clock and storage keep model regressions isolated from real controllers and saved grips.
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var gripDefaults = UserDefaults.standard
    private var now: Double { clock() }
    private var basis: simd_quatf {
        if grip == 4, let customBasis { return customBasis }
        switch grip {
        case 1: return simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        case 2: return simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        case 3: return simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        default: return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    func start(demo: Bool = false) {
        stop()
        if demo { useCamera = false; grip = 0 }
        simulated = demo
        running = true
        trackingStartedAt = now
        waitingForMotion = false; motionError = ""
        source = "None"; incomingSource = "None"
        sourceLock = MotionSourceLock(); lastReportedAt = nil
        calibrationStep = 0; calibrationSession = nil
        samples = 0; gaps = 0; switches = 0; swings = 0
        frequency = 0; lastReceived = nil; lastSensorTime = nil
        rawOrientation = nil; calibrated = false
        arrivals = []; speedHistory = []
        continuity = ContinuityTracker(); tracker = OrientationTracker(); detector = SwingDetector()
        saber = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        scene.setOrientation(saber)
        testMessage = "No hardware test completed in this session"
        testProgress = 0; testAngle = 0
        openLog()
        if demo {
            status = "SIMULATED INPUT — hardware not verified"
            demoOrigin = now
            demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                let t = self.now - self.demoOrigin
                let yaw = Float(sin(t * 2.4) * 1.0)
                let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 0, 1))
                self.receive(q: q, euler: SIMD3(0, 0, Double(yaw)),
                             rate: SIMD3(0, 0, cos(t * 2.4) * 2.4),
                             accel: .zero, sensorTime: self.now, location: "Simulated")
            }
        } else {
            status = "Waiting for AirPods motion…"
            let manager = CMHeadphoneMotionManager()
            self.manager = manager
            manager.delegate = self
            refreshPermissions()
            let session = motionInbox.begin()
            let inbox = motionInbox
            manager.startConnectionStatusUpdates()
            manager.startDeviceMotionUpdates(to: motionQueue) { motion, error in
                if let error {
                    inbox.submit(.error(error.localizedDescription), session: session)
                }
                guard let motion else { return }
                let q = motion.attitude.quaternion
                let r = motion.rotationRate
                let a = motion.userAcceleration
                let location: String
                switch motion.sensorLocation {
                case .headphoneLeft: location = "Left"
                case .headphoneRight: location = "Right"
                default: location = "Unknown"
                }
                inbox.submit(.sample(HeadphoneReading(
                    q: simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)),
                    euler: SIMD3(motion.attitude.yaw, motion.attitude.pitch, motion.attitude.roll),
                    rate: SIMD3(r.x, r.y, r.z), acceleration: SIMD3(a.x, a.y, a.z),
                    timestamp: motion.timestamp, source: location,
                    receivedAt: ProcessInfo.processInfo.systemUptime)), session: session)
            }
        }
        event(demo ? "Started simulation" : "Started real AirPods stream")
    }

    func startScripted(_ scenario: SaberScript) {
        stop()
        selectedSport = .neonRush
        showLab(false)
        useCamera = false; simulated = true; running = true; calibrated = true
        scriptedScenario = scenario; scriptController = ScriptedSaber(scenario)
        source = "Simulated"; incomingSource = "Simulated"
        samples = 0; arrivals = []; sampleAge = 0
        status = "SCRIPTED SABER • \(scenario.rawValue)"
        openLog()
        updateScriptedSaber()
        game.start(demo: true, seed: 42)
        event("SCRIPT_START \(scenario.rawValue)")
    }

    private func updateScriptedSaber() {
        guard running, scriptedScenario != nil else { return }
        let t = now
        let pose = scriptController.pose(for: game.state)
        lastReceived = t; sampleAge = 0; samples += 1
        saber = pose.orientation
        scene.setPose(pose, trail: true); scene.setLive(true)
        game.update(pose: pose, time: t, ready: true)
    }

    func stop() {
        motionInbox.stop()
        manager?.stopDeviceMotionUpdates()
        manager?.stopConnectionStatusUpdates()
        manager?.delegate = nil
        manager = nil
        motionServiceActive = false; waitingForMotion = false
        demoTimer?.invalidate(); demoTimer = nil
        scriptedScenario = nil
        if testing { finishTrial(message: "Test interrupted: tracking stopped") }
        if running { event("Stopped stream") }
        running = false
        calibrated = false
        calibrationStep = 0; calibrationSession = nil
        status = "Stopped"
        scene.setLive(false)
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
        try? log?.close(); log = nil
        lastHealthWrite = 0
        tick()
    }

    private func consumeMotion() {
        guard running, !simulated, let delivery = motionInbox.take() else { return }
        switch delivery {
        case .error(let message):
            motionError = message; status = message; event("Motion error: \(message)")
        case .sample(let sample):
            guard now - sample.receivedAt < 0.25 else { return }
            if waitingForMotion { waitingForMotion = false }
            if !motionError.isEmpty { motionError = "" }
            receive(q: sample.q, euler: sample.euler, rate: sample.rate, accel: sample.acceleration,
                    sensorTime: sample.timestamp, location: sample.source, receivedAt: sample.receivedAt)
        }
    }

    func recenter() {
        guard calibrationStep == 0, hasFreshMotion, let rawOrientation else { return }
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
        handAnchor = camera.point
        handPosition = SIMD3<Float>(0, -0.5, 0)
        tracker.recenter(rawOrientation)
        saber = tracker.displayed
        scene.setOrientation(saber)
        calibrated = true
        event("Recentered, axis preset \(grip)")
        updateScene(at: now)
    }

    func beginTrial() {
        guard hasFreshMotion, !simulated, calibrationStep == 0 else { return }
        trial = ContinuityTracker()
        trialReference = rawOrientation
        trialCondition = condition
        testAngle = 0; testProgress = 0; testing = true
        testMessage = "Testing: \(trialCondition). Move through multiple angles."
        event("BEGIN 120s test: \(trialCondition)")
    }

    func cancelTrial() { finishTrial(message: "Test cancelled — no pass recorded") }

    private func finishTrial(message: String) {
        testing = false
        testMessage = message
        event(message)
        let report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()),
            "conditionUserReported": trialCondition, "result": message,
            "longestContinuousSeconds": trial.longest, "gaps": trial.gaps,
            "sourceSwitches": trial.switches, "samples": trial.count,
            "maxRotationDegrees": testAngle, "logPath": logPath]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let url = logDirectory.appendingPathComponent("test-\(UUID().uuidString.prefix(8)).json")
            try data.write(to: url)
        } catch { logError = "Could not save test report: \(error.localizedDescription)" }
    }

    var sourceMismatch: Bool { !simulated && incomingSource != "None" && source != incomingSource }
    var hasFreshMotion: Bool {
        running && !sourceMismatch && (lastReceived.map { now - $0 < 0.25 } ?? false)
    }
    var controllerSampleAge: Double { lastReceived.map { max(0, now - $0) } ?? 60 }
    var canAdoptIncomingSource: Bool {
        sourceMismatch && (incomingSource == "Left" || incomingSource == "Right") &&
        (lastReportedAt.map { now - $0 < 0.25 } ?? false)
    }
    var controllerName: String {
        if simulated { return scriptedScenario == nil ? "Demo controller" : "Scripted saber" }
        return source == "Left" || source == "Right" ? "\(source) AirPod" : "AirPod"
    }
    var calibrationButtonTitle: String { "\(hasGripCalibration ? "Recalibrate" : "Calibrate") \(controllerName)" }
    var controllerLabel: String {
        if simulated { return scriptedScenario == nil ? "Demo controller" : "Scripted saber" }
        if source == "None" { return "Waiting for an AirPod sensor" }
        if sourceMismatch { return "Selected: \(source) · macOS reporting: \(incomingSource)" }
        return "Controller: \(source) AirPod"
    }

    func adoptIncomingSource() {
        guard canAdoptIncomingSource, sourceLock.adoptReported() else { return }
        let wasCalibrating = calibrationStep > 0
        source = sourceLock.selected ?? "None"
        rawOrientation = nil; lastReceived = nil; lastSensorTime = nil; sampleAge = .infinity
        calibrated = false; tracker = OrientationTracker(); arrivals.removeAll()
        loadGrip(for: source)
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput(); scene.setLive(false)
        if wasCalibrating {
            simpleCalibration = SimpleGripCalibration()
            calibrationSession = useSimpleCalibration ? nil : GripCalibrationSession(source: source)
            calibrationSource = source; calibrationStep = 1; calibrationError = ""
            calibrationMessage = "Controller changed. Start again with the \(source) AirPod."
        }
        event("User selected \(source) AirPod; recenter or calibrate before playing")
    }

    private func interruptCalibration(_ message: String) {
        guard calibrationStep > 0 else { return }
        if useSimpleCalibration {
            guard calibrationError != message else { return }
            simpleCalibration = SimpleGripCalibration()
            calibrationStep = 1
        } else {
            guard calibrationSession?.interruption == nil else { return }
            calibrationSession?.interrupt(message)
        }
        calibrationError = message
        calibrationMessage = message
        event("CALIBRATION_INTERRUPTED \(message)")
    }

    func receive(q: simd_quatf, euler: SIMD3<Double>, rate: SIMD3<Double>,
                         accel: SIMD3<Double>, sensorTime: Double, location: String,
                         receivedAt: Double? = nil) {
        let received = receivedAt ?? now
        guard now - received < 0.25, received <= now,
              q.vector.indices.allSatisfy({ q.vector[$0].isFinite }),
              simd_length(q.vector) > 0.001, sensorTime.isFinite else { return }
        if !simulated {
            let previousReported = incomingSource
            let accepted = sourceLock.observe(location)
            incomingSource = location; lastReportedAt = received
            if previousReported != location && previousReported != "None" {
                switches += 1
                event("macOS source changed \(previousReported) → \(location); selected=\(source)")
            }
            guard accepted else {
                if testing { finishTrial(message: "Test interrupted: motion source changed — no pass recorded") }
                calibrated = false; tracker = OrientationTracker()
                arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput(); scene.setLive(false)
                interruptCalibration("macOS switched to \(location). Return to \(source), then Start over, or select the other earbud below.")
                status = "\(source) selected, but macOS is sending \(location) motion"
                return
            }
            if source == "None" {
                source = location
                loadGrip(for: location)
            }
        } else { source = location; incomingSource = location }
        // A repeated hardware timestamp must never refresh an old pose.
        if let lastSensorTime, sensorTime <= lastSensorTime { return }
        let dt = lastReceived.map { received - $0 } ?? 0.02
        let interrupted = dt >= ArcadeGame.trackingLossDelay
        lastReceived = received; lastSensorTime = sensorTime
        sampleAge = max(0, now - received)
        if interrupted {
            calibrated = false; tracker = OrientationTracker()
            arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
            interruptCalibration("Motion was interrupted. Check your controller, then choose Start over.")
            event("Stream resumed — recenter required")
        } else if dt > 0.5 && calibrationStep > 0 {
            // Keep setup's existing continuity requirements separate from gameplay.
            interruptCalibration("Motion was interrupted. Check your controller, then choose Start over.")
        }
        rawOrientation = simd_normalize(q)
        if samples == 0 { tracker.recenter(q); calibrated = true }
        samples += 1
        if calibrationStep > 0 {
            calibrationSession?.ingest(q: q, speed: Float(simd_length(rate)), sensorTime: sensorTime,
                                       receivedAt: received, source: location)
        }
        attitude = euler * (180 / .pi)
        rotation = rate; acceleration = accel; quaternion = q.vector
        speed = simd_length(rate)
        speedHistory.append(speed)
        if speedHistory.count > 100 { speedHistory.removeFirst() }
        arrivals.append(received)
        arrivals.removeAll { received - $0 > 2 }
        frequency = arrivals.count > 1 ? Double(arrivals.count - 1) / (received - arrivals[0]) : 0
        continuity.ingest(time: received, source: location)
        gaps = continuity.gaps
        if calibrated && calibrationStep == 0 {
            saber = tracker.update(q, basis: basis, delta: min(dt, 0.1),
                                   smoothing: dt >= ArcadeGame.freshInputAge ? 0 : smoothing)
        }
        updateScene(at: received)
        if detector.update(speed: speed, time: received, threshold: swingThreshold) {
            swings += 1
            scene.flash()
        }
        if !simulated { status = calibrated ? "Live AirPods motion" : "Source changed or resumed — press Recenter" }
        if testing {
            let previousGaps = trial.gaps
            let previousSwitches = trial.switches
            trial.ingest(time: received, source: location)
            if trialReference == nil || previousGaps != trial.gaps || previousSwitches != trial.switches {
                trialReference = q; testAngle = 0
                event("Test continuity reset — need 120 uninterrupted seconds from one source")
            }
            if let trialReference {
                let relative = simd_normalize(trialReference.inverse * q)
                let angle = 2 * acos(min(1, abs(Double(relative.real)))) * 180 / .pi
                testAngle = max(testAngle, angle)
            }
            testProgress = trial.current
            if trial.current >= 120 && testAngle >= 30 {
                finishTrial(message: "PASS: 120s continuous motion + ≥30° rotation (\(trialCondition), user-reported condition)")
            }
        }
        writeCSV([String(received), String(sensorTime), simulated ? "simulation" : "airpods", location,
                  testing ? trialCondition : condition, String(q.vector.x), String(q.vector.y), String(q.vector.z), String(q.real),
                  String(attitude.x), String(attitude.y), String(attitude.z),
                  String(rate.x), String(rate.y), String(rate.z), String(accel.x), String(accel.y), String(accel.z),
                  String(calibrated), String(swings), ""])
    }

    private func refreshPermissions() {
        guard let manager else { return }
        if available != manager.isDeviceMotionAvailable { available = manager.isDeviceMotionAvailable }
        if motionServiceActive != manager.isDeviceMotionActive { motionServiceActive = manager.isDeviceMotionActive }
        let permission: String
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: permission = "Allowed"
        case .denied: permission = "Denied — enable Motion & Fitness in System Settings"
        case .restricted: permission = "Restricted"
        case .notDetermined: permission = "Not requested"
        @unknown default: permission = "Unknown"
        }
        if authorization != permission { authorization = permission }
    }

    func tick() {
        if openCalibrationWhenReady && hasFreshMotion {
            openCalibrationWhenReady = false
            beginGripCalibration()
        }
        if running && !simulated { refreshPermissions() }
        let waiting = running && !simulated && samples == 0 && now - trackingStartedAt > 5
        if waitingForMotion != waiting { waitingForMotion = waiting }
        if waiting && motionError.isEmpty {
            let message = authorization.hasPrefix("Denied") || authorization == "Restricted"
                ? "Motion permission is blocked — check System Settings"
                : "No motion received yet — reconnect your AirPods"
            if status != message { status = message }
        }
        sampleAge = lastReceived.map { now - $0 } ?? .infinity
        if sampleAge >= ArcadeGame.freshInputAge {
            frequency = 0
            scene.setLive(false)
            arena.invalidateInput()
            if selectedSport == .tennis { tennis.waitForFreshInput() }
            else { game.waitForFreshInput() }
            if running && samples > 0 && !sourceMismatch { status = "Motion stale — waiting for fresh samples" }
            if sampleAge > 0.5 && running && samples > 0 {
                interruptCalibration("Motion stopped during setup. Wait for fresh motion, then choose Start over.")
            }
            if sampleAge > 0.5 && testing { testProgress = 0 }
        }
        if now - lastHealthWrite > 1 {
            lastHealthWrite = now
            let health: [String: Any] = ["running": running, "simulated": simulated,
                "status": status, "authorization": authorization, "available": available,
                "motionServiceActive": motionServiceActive, "waitingForMotion": waitingForMotion,
                "cachedMotionAvailable": manager?.deviceMotion != nil, "motionError": motionError,
                "source": source, "incomingSource": incomingSource, "sourceMismatch": sourceMismatch, "samples": samples, "sampleAgeSeconds": sampleAge.isFinite ? sampleAge : -1,
                "frequencyHz": frequency, "testMessage": testMessage, "testProgressSeconds": testProgress,
                "calibrated": calibrated, "logPath": logPath,
                "gripPreset": grip, "calibrationStep": calibrationStep,
                "calibrationMode": useSimpleCalibration ? "simple-three-pose-v1" : "steady-five-step",
                "calibrationMessage": calibrationMessage, "calibrationError": calibrationError,
                "calibrationSource": calibrationSource,
                "calibrationTiltDegrees": calibrationTiltDegrees.map { Double($0) } ?? -1,
                "calibrationPoseReady": calibrationPoseReady, "calibrationHint": calibrationPoseHint,
                "calibrationAxisSeparationDegrees": calibrationAssessment?.separationDegrees.map { Double($0) } ?? -1,
                "cameraEnabled": useCamera, "cameraStatus": camera.status,
                "cameraTracking": camera.point != nil, "cameraHz": camera.frameRate,
                "scriptedScenario": scriptedScenario?.rawValue ?? "",
                "gameMaxFeedbackSeconds": game.maxFeedbackSeconds, "gameSlowFrames": game.slowFrames,
                "gameMaxFrameSeconds": game.maxFrameSeconds,
                "gameRecoveringInput": game.recoveringInput, "gameTransientInputGaps": game.transientInputGaps,
                "gamePauseReason": game.pauseReason,
                "gamePhase": game.state.phase.rawValue, "gameScore": game.state.score, "gameLives": game.state.lives, "gameRemaining": game.state.remaining,
                "arenaMode": arena.mode.rawValue, "hits": arena.hits, "parries": arena.parries,
                "misses": arena.misses, "arenaMessage": arena.message]
            if let data = try? JSONSerialization.data(withJSONObject: health, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: logDirectory.appendingPathComponent("latest-status.json"), options: .atomic)
            }
        }
    }

    private func openLog() {
        logError = ""
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = logDirectory.appendingPathComponent("\(simulated ? "simulation" : "airpods")-\(stamp)-\(UUID().uuidString.prefix(6)).csv")
        do {
            try Data().write(to: url)
            log = try FileHandle(forWritingTo: url)
            logPath = url.path
            writeCSV(["received_uptime_s", "sensor_uptime_s", "mode", "source", "condition_user_reported",
                      "qx", "qy", "qz", "qw", "yaw_deg", "pitch_deg", "roll_deg",
                      "rotation_x_rad_s", "rotation_y_rad_s", "rotation_z_rad_s",
                      "accel_x_g", "accel_y_g", "accel_z_g", "calibrated", "swing_count", "event"])
        } catch { logError = error.localizedDescription }
    }

    private func writeCSV(_ fields: [String]) {
        let line = fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") + "\n"
        do { try log?.write(contentsOf: Data(line.utf8)) }
        catch { logError = error.localizedDescription; try? log?.close(); log = nil }
    }

    private func event(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        events.insert("\(stamp)  \(message)", at: 0)
        if events.count > 10 { events.removeLast() }
        var row = Array(repeating: "", count: 21)
        row[0] = String(now); row[2] = simulated ? "simulation" : "airpods"
        row[3] = source; row[4] = condition; row[20] = message
        writeCSV(row)
    }


    func showLab(_ visible: Bool) {
        if showingMultiplayer { multiplayer.close(); showingMultiplayer = false }
        game.leave()
        tennis.leave()
        showingLab = visible
        game.enabled = !visible && selectedSport == .neonRush
        tennis.enabled = !visible && selectedSport == .tennis
        arena.enabled = visible
        if visible { arena.reset() }
        if !visible { scene.setSport(selectedSport) }
        scene.setArcadeVisible(!visible)
    }

    func showMultiplayer(_ visible: Bool) {
        game.leave(); tennis.leave(); showingLab = false; arena.enabled = false
        showingMultiplayer = visible
        game.enabled = !visible && selectedSport == .neonRush
        tennis.enabled = !visible && selectedSport == .tennis
        if visible { multiplayer.open() } else { multiplayer.close() }
    }

    func selectSport(_ sport: AircadeSport) {
        guard !showingLab else { return }
        if showingMultiplayer { multiplayer.close(); showingMultiplayer = false }
        game.leave()
        tennis.leave()
        selectedSport = sport
        game.enabled = sport == .neonRush
        tennis.enabled = sport == .tennis
        scene.setSport(sport)
        scene.setArcadeVisible(true)
        updateScene(at: now)
    }

    func startCamera() {
        useCamera = true
        camera.start()
    }

    private func receiveHand(_ point: CGPoint, time: Double) {
        guard useCamera else { return }
        if handAnchor == nil {
            handAnchor = point
            handPosition = SIMD3<Float>(0, -0.5, 0)
            arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
        }
        guard let handAnchor else { return }
        let target = SIMD3<Float>(Float((point.x - handAnchor.x) * cameraGain),
                                  Float((point.y - handAnchor.y) * cameraGain) - 0.5, 0)
        let bounded = SIMD3<Float>(min(2.2, max(-2.2, target.x)), min(1.4, max(-1.2, target.y)), 0)
        let dt = min(0.1, max(0.001, time - lastHandTime))
        lastHandTime = time
        handPosition = simd_mix(handPosition, bounded, SIMD3<Float>(repeating: Float(1 - exp(-dt / 0.045))))
        updateScene(at: now)
    }

    private func updateScene(at time: Double) {
        if showingMultiplayer { return }
        let freshMotion = lastReceived.map { now - $0 < 0.25 } ?? false
        let freshHand = camera.running && camera.point != nil && now - lastHandTime < 0.25
        let ready = running && !sourceMismatch && calibrated && freshMotion && (!useCamera || freshHand) && calibrationStep == 0
        let pose = SaberPose(position: useCamera ? handPosition : SIMD3<Float>(0, -0.5, 0), orientation: saber)
        scene.setPose(pose, trail: ready)
        scene.setLive(ready)
        if showingLab { arena.update(pose: pose, time: time, ready: ready) }
        else if running && !sourceMismatch && calibrated && calibrationStep == 0 && !freshMotion {
            if selectedSport == .tennis { tennis.waitForFreshInput() }
            else { game.waitForFreshInput() }
        } else if selectedSport == .tennis { tennis.update(pose: pose, time: time, ready: ready) }
        else { game.update(pose: pose, time: time, ready: ready) }
    }

    func beginGripCalibration() {
        guard running, !simulated, hasFreshMotion else { return }
        simpleCalibration = SimpleGripCalibration()
        calibrationSession = useSimpleCalibration ? nil : GripCalibrationSession(source: source)
        calibrationError = ""; calibrationAttempt = 0; calibrationSource = source
        calibrationStep = 1
        calibrationMessage = "Hold the \(source) AirPod in your playing grip. Save an upright starting pose."
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
    }

    func cancelGripCalibration() {
        calibrationStep = 0; calibrationSession = nil
        calibrationError = ""
        calibrationMessage = "Calibration cancelled. Your previous grip is unchanged. Recenter before playing."
        calibrated = false
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
    }

    var calibrationAssessment: GripCalibration.TiltAssessment? { calibrationSession?.assessment(at: now) }
    var calibrationTiltDegrees: Float? { hasFreshMotion ? calibrationSession?.angleDegrees(at: now) : nil }
    var calibrationPreview: simd_quatf? { hasFreshMotion ? calibrationSession?.preview(at: now) : nil }
    var calibrationPoseReady: Bool { hasFreshMotion && (useSimpleCalibration || calibrationSession?.feedback(at: now).ready == true) }
    var calibrationPoseHint: String {
        if sourceMismatch { return "macOS is sending \(incomingSource) motion. Your \(source) calibration is paused. Choose which earbud to use." }
        if useSimpleCalibration { return calibrationError.isEmpty ? calibrationMessage : calibrationError }
        return calibrationSession?.feedback(at: now).message ?? "Start grip setup to capture a starting pose."
    }

    func useSavedGrip() {
        guard hasGripCalibration, hasFreshMotion else { return }
        calibrationStep = 0; calibrationSession = nil; calibrationError = ""
        loadingGrip = true; grip = 4; loadingGrip = false
        calibrated = false
        calibrationMessage = "Using saved grip for \(source). Hold upright and press R before playing."
        arena.invalidateInput(); game.invalidateInput(); tennis.invalidateInput()
    }

    private func rejectCalibration(_ message: String) {
        calibrationError = message
        calibrationMessage = message
        calibrationAttempt += 1
        event("CALIBRATION_REJECT step=\(calibrationStep) source=\(source) \(message)")
    }

    func captureGripPose() {
        consumeMotion()
        guard running, !simulated, hasFreshMotion, source == calibrationSource else {
            rejectCalibration(calibrationPoseHint); return
        }
        if useSimpleCalibration { captureSimpleGripPose(); return }
        // Newer steady-window calibration is bypassed while useSimpleCalibration is true.
        let capturedStep = calibrationStep
        guard calibrationSession?.capture(at: now) == true else {
            rejectCalibration(calibrationPoseHint); return
        }
        calibrationError = ""
        if capturedStep == GripCalibrationSession.Stage.verify.rawValue {
            guard let value = calibrationSession?.proposedBasis, let reference = calibrationSession?.reference else {
                rejectCalibration("The proposed grip is missing. Choose Start over."); return
            }
            customBasis = value; hasGripCalibration = true
            gripDefaults.set(value.vector.indices.map { Double(value.vector[$0]) }, forKey: "grip.\(source)")
            loadingGrip = true; grip = 4; loadingGrip = false
            tracker.recenter(reference)
            if let rawOrientation { saber = tracker.update(rawOrientation, basis: value, delta: 1, smoothing: 0) }
            calibrated = true; calibrationStep = 0; calibrationSession = nil
            calibrationMessage = "Grip verified and saved for \(source). Recalibrate if the earbud shifts in your fingers."
            event("CALIBRATION_COMMIT source=\(source) basis=\(value.vector)")
            updateScene(at: now)
        } else {
            calibrationStep = calibrationSession?.stage.rawValue ?? 1
            calibrationMessage = "Pose saved. Follow the next step."
            event("CALIBRATION_CAPTURE step=\(capturedStep) source=\(source) next=\(calibrationStep)")
        }
    }

    private func captureSimpleGripPose() {
        guard let rawOrientation else { return }
        guard simpleCalibration.capture(rawOrientation) else {
            calibrationError = simpleCalibration.error
            return
        }
        calibrationError = ""
        if let value = simpleCalibration.basis, let reference = simpleCalibration.reference {
            customBasis = value; hasGripCalibration = true
            gripDefaults.set(value.vector.indices.map { Double(value.vector[$0]) }, forKey: "grip.\(source)")
            loadingGrip = true; grip = 4; loadingGrip = false
            tracker.recenter(reference)
            saber = tracker.update(rawOrientation, basis: value, delta: 1, smoothing: 0)
            calibrated = true; calibrationStep = 0
            calibrationMessage = "\(source) AirPod calibrated. Keep using this earbud; return upright and press R."
            event("SIMPLE_CALIBRATION_SAVED source=\(source)")
            updateScene(at: now)
        } else {
            calibrationStep = simpleCalibration.step
            calibrationMessage = calibrationStep == 2 ? "Upright saved for \(source) AirPod. Lean toward your left, then capture." : "Left tilt saved for \(source) AirPod. Return upright, then tip toward the screen and finish."
            event("SIMPLE_CALIBRATION_CAPTURE next=\(calibrationStep) source=\(source)")
        }
    }

    private func loadGrip(for location: String) {
        loadingGrip = true
        defer { loadingGrip = false }
        if let values = gripDefaults.array(forKey: "grip.\(location)") as? [Double], values.count == 4,
           values.allSatisfy({ $0.isFinite }) {
            let v = SIMD4<Float>(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))
            if simd_length(v) > 0.1 {
                customBasis = simd_normalize(simd_quatf(vector: v)); hasGripCalibration = true; grip = 4
                calibrationMessage = "Loaded grip calibration for \(location). Press R in your neutral pose."
                return
            }
        }
        customBasis = nil; hasGripCalibration = false; grip = 0
    }

    func revealLogs() { NSWorkspace.shared.open(logDirectory) }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.manager === manager else { return }
            self.event("Headphones connected")
        }
    }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.manager === manager else { return }
            self.interruptCalibration("AirPods disconnected. Reconnect, then choose Start over.")
            self.status = "Headphones disconnected"
            self.calibrated = false
            self.arena.invalidateInput(); self.game.invalidateInput(); self.tennis.invalidateInput()
            self.scene.setLive(false)
            self.event("Headphones disconnected")
        }
    }
}
