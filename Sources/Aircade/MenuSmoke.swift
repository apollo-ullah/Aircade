import AppKit
import simd

/// Supplies poses aimed at actual rendered button frames. Never calls their actions directly.
enum MenuSmoke {
    static func run(_ motion: MotionModel) {
        motion.simulated = true; motion.running = true; motion.smoothing = 0; motion.grip = 0
        let steps: [(String, () -> Bool)] = [
            ("channel-tennis", { motion.shellRoute == .tennis }),
            ("start-tennis", { [.countdown, .playing].contains(motion.tennis.state.phase) }),
            ("Back to menu", { motion.shellRoute == .home }),
            ("channel-neonRush", { motion.shellRoute == .neonRush }),
            ("start-neon-rush", { [.countdown, .playing].contains(motion.game.state.phase) }),
            ("Back to menu", { motion.shellRoute == .home }),
            ("settings", { motion.shellRoute == .settings }),
            ("Back to menu", { motion.shellRoute == .home })
        ]
        var step = 0, checks: [String] = [], gameplayGated = true
        var began = ProcessInfo.processInfo.systemUptime
        var waitingUntil = 0.0
        var maximumProgress = 0.0
        var transitions: [[String: Any]] = []
        var previousState = ""
        var q = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            let now = ProcessInfo.processInfo.systemUptime
            maximumProgress = max(maximumProgress, motion.menu.progress)
            let state = "\(step):\(motion.menu.active):\(motion.menu.diagnostics["armed"] ?? false):\(motion.menu.diagnostics["context"] ?? ""):\(motion.menu.hovered?.uuidString ?? "none")"
            if state != previousState {
                transitions.append(["state": state, "elapsed": now - began, "cursor": [motion.menu.pointer.unitPoint.x, motion.menu.pointer.unitPoint.y], "target": motion.menu.targets.first(where: { $0.id == motion.menu.hovered })?.name ?? "none", "progress": motion.menu.progress])
                previousState = state
            }
            motion.receive(q: q, euler: .zero, rate: .zero, accel: .zero, sensorTime: now, location: "Simulated")
            if waitingUntil > 0 {
                if now < waitingUntil { return }
                gameplayGated = gameplayGated && !motion.menu.active
                motion.tennis.pause("Controller menu test"); motion.game.pause("Controller menu test")
                waitingUntil = 0; began = now
            }
            if step < steps.count, steps[step].1() {
                checks.append(steps[step].0); step += 1; began = now; q = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                if step == 2 || step == 5 { waitingUntil = now + 1; return }
            }
            if step >= steps.count || now - began > 7 {
                timer.invalidate()
                let report: [String: Any] = ["passed": step == steps.count && gameplayGated,
                    "selectedButtons": checks, "gameplaySelectionDisabled": gameplayGated,
                    "phase": String(describing: motion.shellRoute), "cursorActive": motion.menu.active,
                    "targets": motion.menu.targets.map(\.name), "queuedScores": motion.players.pendingRuns.count, "samples": motion.samples,
                    "viewport": [motion.menu.size.width, motion.menu.size.height],
                    "cursor": [motion.menu.pointer.unitPoint.x, motion.menu.pointer.unitPoint.y],
                    "maximumProgress": maximumProgress, "menu": motion.menu.diagnostics,
                    "transitions": transitions,
                    "hardwareVerified": false]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: motion.logDirectory.appendingPathComponent("menu-smoke-result.json"))
                }
                capture(motion, name: "final")
                NSApp.terminate(nil); return
            }
            // Let the new menu finish appearing before deliberately aiming at its button.
            if now - began < 0.8 { q = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)); return }
            if let target = motion.menu.targets.first(where: { $0.name == steps[step].0 && $0.enabled }), motion.menu.size.width > 0 {
                let x = Float((target.frame.midX / motion.menu.size.width * 2 - 1) * 22.5 * .pi / 180)
                let y = Float((1 - target.frame.midY / motion.menu.size.height * 2) * 13 * .pi / 180)
                q = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(SIMD3<Float>(tan(x), 1, -tan(y))))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    private static func capture(_ motion: MotionModel, name: String) {
        if let view = NSApp.windows.first?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("menu-\(name).png"))
            }
        }
    }
}
