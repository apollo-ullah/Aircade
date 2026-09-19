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
}
private enum HeadphoneDelivery {
    case sample(HeadphoneReading)
    case error(String)
}

final class MotionModel: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published var running = false
    @Published var simulated = false
    @Published var status = "Connect AirPods, then start tracking"
    @Published var authorization = "Not requested"
    @Published var available = false
    @Published var motionServiceActive = false
    @Published var waitingForMotion = false
    @Published var motionError = ""
    @Published var source = "None"
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
    @Published var grip = 0 { didSet { recenter() } }
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
            arena.invalidateInput(); game.invalidateInput()
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
    let camera = HandTracker()
    let scene = SaberScene()
    lazy var arena = TrainingArena(scene: scene)
    lazy var game = ArcadeGame(scene: scene)
    private var customBasis: simd_quatf?
    private var calibrationReference: simd_quatf?
    private var calibrationLeft: SIMD3<Float>?
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

    override init() {
        logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aircade/Logs", isDirectory: true)
        super.init()
        arena.enabled = false
        scene.setArcadeVisible(true)
        game.onEvent = { [weak self] message in self?.event(message) }
        arena.onEvent = { [weak self] message in self?.event(message) }
        camera.onPoint = { [weak self] point, time in self?.receiveHand(point, time: time) }
        camera.onLost = { [weak self] in
            guard let self else { return }
            self.handAnchor = nil
            if self.useCamera { self.arena.invalidateInput(); self.game.invalidateInput(); self.scene.setLive(false) }
        }
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        let inputTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.consumeMotion() }
        RunLoop.main.add(inputTimer, forMode: .common)
        self.inputTimer = inputTimer
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
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
        source = "None"
        calibrationStep = 0
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
                    timestamp: motion.timestamp, source: location)), session: session)
            }
        }
        event(demo ? "Started simulation" : "Started real AirPods stream")
    }

    func stop() {
        motionInbox.stop()
        manager?.stopDeviceMotionUpdates()
        manager?.stopConnectionStatusUpdates()
        manager?.delegate = nil
        manager = nil
        motionServiceActive = false; waitingForMotion = false
        demoTimer?.invalidate(); demoTimer = nil
        if testing { finishTrial(message: "Test interrupted: tracking stopped") }
        if running { event("Stopped stream") }
        running = false
        status = "Stopped"
        scene.setLive(false)
        arena.invalidateInput(); game.invalidateInput()
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
            if waitingForMotion { waitingForMotion = false }
            if !motionError.isEmpty { motionError = "" }
            receive(q: sample.q, euler: sample.euler, rate: sample.rate, accel: sample.acceleration,
                    sensorTime: sample.timestamp, location: sample.source)
        }
    }

    func recenter() {
        guard running, let rawOrientation, sampleAge < 0.5 else { return }
        arena.invalidateInput(); game.invalidateInput()
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
        guard running, !simulated, sampleAge < 0.5 else { return }
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

    private func receive(q: simd_quatf, euler: SIMD3<Double>, rate: SIMD3<Double>,
                         accel: SIMD3<Double>, sensorTime: Double, location: String) {
        let received = now
        guard q.vector.x.isFinite, q.vector.y.isFinite, q.vector.z.isFinite, q.vector.w.isFinite,
              simd_length(q.vector) > 0.001 else { return }
        // Core Motion can repeat a timestamp. Such callbacks must not count as fresh tracking.
        if location == source, let lastSensorTime, sensorTime <= lastSensorTime { return }
        let changed = source != "None" && source != location
        let interrupted = lastReceived.map { received - $0 > 0.5 } ?? false
        let dt = lastReceived.map { received - $0 } ?? 0.02
        lastReceived = received; lastSensorTime = sensorTime
        sampleAge = 0
        if changed || interrupted {
            calibrated = false
            tracker = OrientationTracker()
            arena.invalidateInput(); game.invalidateInput()
            calibrationStep = 0
            event(changed ? "Source changed to \(location) — recenter required" : "Stream resumed — recenter required")
        }
        if source != location {
            source = location
            if !simulated { loadGrip(for: location) }
            if changed { calibrated = false; tracker = OrientationTracker() }
        }
        rawOrientation = simd_normalize(q)
        // Only the very first sample is automatically calibrated. Later interruptions need explicit recentering.
        if samples == 0 { tracker.recenter(q); calibrated = true }
        source = location; samples += 1
        attitude = euler * (180 / .pi)
        rotation = rate; acceleration = accel; quaternion = q.vector
        speed = simd_length(rate)
        speedHistory.append(speed)
        if speedHistory.count > 100 { speedHistory.removeFirst() }
        arrivals.append(received)
        arrivals.removeAll { received - $0 > 2 }
        frequency = arrivals.count > 1 ? Double(arrivals.count - 1) / (received - arrivals[0]) : 0
        continuity.ingest(time: received, source: location)
        gaps = continuity.gaps; switches = continuity.switches
        if calibrated {
            saber = tracker.update(q, basis: basis, delta: min(dt, 0.1), smoothing: smoothing)
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

    private func tick() {
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
        if sampleAge > 0.5 {
            frequency = 0
            scene.setLive(false)
            arena.invalidateInput(); game.invalidateInput()
            if running && samples > 0 { status = "Motion stale — waiting for fresh samples" }
            if testing { testProgress = 0 }
        }
        if now - lastHealthWrite > 1 {
            lastHealthWrite = now
            let health: [String: Any] = ["running": running, "simulated": simulated,
                "status": status, "authorization": authorization, "available": available,
                "motionServiceActive": motionServiceActive, "waitingForMotion": waitingForMotion,
                "cachedMotionAvailable": manager?.deviceMotion != nil, "motionError": motionError,
                "source": source, "samples": samples, "sampleAgeSeconds": sampleAge.isFinite ? sampleAge : -1,
                "frequencyHz": frequency, "testMessage": testMessage, "testProgressSeconds": testProgress,
                "calibrated": calibrated, "logPath": logPath,
                "gripPreset": grip, "calibrationStep": calibrationStep,
                "calibrationMessage": calibrationMessage, "calibrationError": calibrationError,
                "calibrationSource": calibrationSource,
                "calibrationTiltDegrees": calibrationAssessment.map { Double($0.degrees) } ?? -1,
                "calibrationAxisSeparationDegrees": calibrationAssessment?.separationDegrees.map { Double($0) } ?? -1,
                "cameraEnabled": useCamera, "cameraStatus": camera.status,
                "cameraTracking": camera.point != nil, "cameraHz": camera.frameRate,
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
        game.leave()
        showingLab = visible
        game.enabled = !visible
        arena.enabled = visible
        if visible { arena.reset() }
        scene.setArcadeVisible(!visible)
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
            arena.invalidateInput(); game.invalidateInput()
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
        let freshMotion = lastReceived.map { now - $0 < 0.25 } ?? false
        let freshHand = camera.running && camera.point != nil && now - lastHandTime < 0.25
        let ready = running && calibrated && freshMotion && (!useCamera || freshHand) && calibrationStep == 0
        let pose = SaberPose(position: useCamera ? handPosition : SIMD3<Float>(0, -0.5, 0), orientation: saber)
        scene.setPose(pose, trail: ready)
        scene.setLive(ready)
        if showingLab { arena.update(pose: pose, time: time, ready: ready) }
        else { game.update(pose: pose, time: time, ready: ready) }
    }

    func beginGripCalibration() {
        guard running, !simulated, sampleAge < 0.5 else { return }
        calibrationError = ""; calibrationAttempt = 0; calibrationSource = source
        calibrationStep = 1
        calibrationMessage = "1 / 3 · Hold the controller upright, in the centre. Capture neutral."
        calibrationReference = nil; calibrationLeft = nil
        arena.invalidateInput(); game.invalidateInput()
    }

    func cancelGripCalibration() {
        calibrationStep = 0
        calibrationError = ""
        calibrationMessage = "Calibration cancelled. Recenter before playing."
        calibrated = false
        arena.invalidateInput(); game.invalidateInput()
    }

    var calibrationAssessment: GripCalibration.TiltAssessment? {
        guard calibrationStep > 1, let reference = calibrationReference, let rawOrientation else { return nil }
        let vector = GripCalibration.rotationVector(reference: reference, sample: rawOrientation)
        return GripCalibration.assessTilt(vector, comparedTo: calibrationStep == 3 ? calibrationLeft : nil)
    }

    var calibrationPoseHint: String {
        guard running, sampleAge < 0.25 else { return "Waiting for fresh motion. Keep the active earbud out of its case." }
        if calibrationStep == 1 { return "Hold the \(source) AirPod upright, then save your starting pose." }
        guard let assessment = calibrationAssessment else { return "The starting pose is missing. Choose Start over." }
        switch assessment.issue {
        case .tooSmall: return "Tilt more from upright. Aim for 30–60°. Rotate the \(source) AirPod, not just your arm."
        case .tooLarge: return "Too far from the starting pose. Return upright, then make a smaller 30–60° tilt."
        case .sameAxis: return "This repeats the left-tilt motion. Return upright, then tip toward the screen instead of sideways."
        case .invalid: return "The saved poses cannot be compared. Choose Start over and keep the same grip."
        case nil: return "Pose looks good. Hold it here and press \(calibrationStep == 3 ? "Finish" : "Save")."
        }
    }

    func useSavedGrip() {
        guard hasGripCalibration else { return }
        calibrationStep = 0; calibrationError = ""
        recenter()
        calibrationMessage = "Using saved grip for \(source). Press R while upright."
    }

    private func rejectCalibration(_ message: String) {
        calibrationError = message
        calibrationMessage = message
        calibrationAttempt += 1
        event("CALIBRATION_REJECT step=\(calibrationStep) source=\(source) \(message)")
    }

    func captureGripPose() {
        consumeMotion()
        guard running, !simulated, let lastReceived, now - lastReceived < 0.25, let rawOrientation else {
            rejectCalibration("No fresh motion to save. Move the active earbud gently, then try again.")
            return
        }
        guard source == calibrationSource else {
            rejectCalibration("The active earbud changed to \(source). Choose Start over using that earbud.")
            return
        }
        calibrationError = ""
        switch calibrationStep {
        case 1:
            calibrationReference = rawOrientation
            calibrationStep = 2
            calibrationMessage = "2 / 3 · Tilt the TOP of the grip 30–60° to your LEFT (don't just slide it). Capture left."
            event("CALIBRATION_CAPTURE neutral source=\(source)")
        case 2:
            guard let reference = calibrationReference else {
                rejectCalibration("The upright pose is missing. Choose Start over."); return
            }
            let vector = GripCalibration.rotationVector(reference: reference, sample: rawOrientation)
            guard GripCalibration.assessTilt(vector).isValid else {
                rejectCalibration(calibrationPoseHint)
                return
            }
            calibrationLeft = vector
            calibrationStep = 3
            calibrationMessage = "3 / 3 · Return upright, then tilt the TOP 30–60° FORWARD (away from you). Capture forward."
            event("CALIBRATION_CAPTURE left vector=\(vector)")
        case 3:
            guard let reference = calibrationReference, let left = calibrationLeft else {
                rejectCalibration("One of the saved poses is missing. Choose Start over."); return
            }
            let forward = GripCalibration.rotationVector(reference: reference, sample: rawOrientation)
            guard GripCalibration.assessTilt(forward, comparedTo: left).isValid else {
                rejectCalibration(calibrationPoseHint)
                return
            }
            guard let value = GripCalibration.basis(left: left, forward: forward) else {
                rejectCalibration("These poses could not produce a grip mapping. Choose Start over.")
                return
            }
            customBasis = value; hasGripCalibration = true
            UserDefaults.standard.set(value.vector.indices.map { Double(value.vector[$0]) }, forKey: "grip.\(source)")
            grip = 4
            tracker.recenter(reference)
            calibrated = true; calibrationStep = 0
            calibrationMessage = "Grip saved for \(source). Return upright and press R. Repeat if you change your grip."
            event("Saved measured grip basis for \(source): \(value.vector)")
        default: break
        }
    }

    private func loadGrip(for location: String) {
        if let values = UserDefaults.standard.array(forKey: "grip.\(location)") as? [Double], values.count == 4,
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
            self.status = "Headphones disconnected"
            self.calibrated = false
            self.arena.invalidateInput(); self.game.invalidateInput()
            self.scene.setLive(false)
            self.event("Headphones disconnected")
        }
    }
}
