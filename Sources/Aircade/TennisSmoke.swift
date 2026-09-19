import AppKit
import SceneKit
import MotionCore
import simd

/// Pose-only native rehearsal. It follows the normal sensor, collision and result
/// path, uses a simulated run, and never opens Core Motion or writes real records.
enum TennisSmoke {
    private final class Driver {
        var time = ProcessInfo.processInfo.systemUptime
        var capturedPlay = false
        var frames = 0
    }

    static func run(_ motion: MotionModel) {
        let driver = Driver()
        motion.clock = { driver.time }
        motion.controllers.selectSolo(.airPod)
        motion.simulated = true; motion.running = true; motion.smoothing = 0
        motion.selectSport(.tennis)
        motion.receive(q: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                       euler: .zero, rate: .zero, accel: .zero, sensorTime: driver.time, location: "Simulated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            capture(motion, name: "menu")
            motion.tennis.start(demo: true)
            let began = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
                // Three physics steps per rendered frame shorten the unattended run.
                // Each step still has a truthful, independent 60 Hz capture timestamp.
                for _ in 0..<3 {
                    let dt = 1.0 / 60
                    driver.time += dt; driver.frames += 1
                    var q = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                    if let flight = motion.tennis.state.ball, flight.direction == .towardPlayer {
                        let targetTime = flight.arrival - 0.14
                        let point = flight.position(at: targetTime)
                        let hilt = SIMD3<Float>(0, -0.5, 0)
                        let aim = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(point - hilt))
                        q = motion.tennis.state.elapsed < targetTime
                            ? simd_quatf(angle: Float(4.8 * dt), axis: SIMD3<Float>(1, 0, 0)) * aim : aim
                    }
                    motion.receive(q: q, euler: .zero, rate: .zero, accel: .zero,
                                   sensorTime: driver.time, location: "Simulated", receivedAt: driver.time)
                    motion.tennis.tick()
                    if motion.tennis.state.phase == .results { break }
                }
                if !driver.capturedPlay && motion.tennis.state.elapsed > 3 {
                    driver.capturedPlay = true; capture(motion, name: "play")
                }
                if motion.tennis.state.phase == .results || ProcessInfo.processInfo.systemUptime - began > 40 {
                    timer.invalidate()
                    let state = motion.tennis.state
                    let passed = state.phase == .results && state.completed && state.returns >= 8 &&
                        motion.tennis.isDemo && motion.players.pendingRuns.isEmpty
                    let report: [String: Any] = ["passed": passed, "phase": state.phase.rawValue,
                        "elapsed": state.elapsed, "returns": state.returns, "misses": state.misses,
                        "score": state.score, "frames": driver.frames, "input": "scripted orientations",
                        "hardwareVerified": false, "queuedScores": motion.players.pendingRuns.count]
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: motion.logDirectory.appendingPathComponent("tennis-smoke-result.json"))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        capture(motion, name: "results")
                        NSApp.terminate(nil)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func capture(_ motion: MotionModel, name: String) {
        if let content = NSApp.windows.first?.contentView,
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("tennis-\(name)-ui.png"))
            }
        }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1340, height: 900))
        view.scene = motion.scene.scene; view.antialiasingMode = .multisampling4X
        if let data = view.snapshot().tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: motion.logDirectory.appendingPathComponent("tennis-\(name)-scene.png"))
        }
    }
}
