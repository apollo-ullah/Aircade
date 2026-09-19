import AppKit
import SceneKit

/// Opt-in native render/integration check; all inputs and scores remain marked as simulated.
enum GameSmoke {
    static func run(_ motion: MotionModel) {
        try? FileManager.default.removeItem(at: motion.logDirectory.appendingPathComponent("game-smoke-result.txt"))
        motion.start(demo: true)
        motion.game.sound = false
        let initialBest = motion.game.bestScore
        // Render first, then schedule actions relative to completion. A cold Metal shader
        // compilation can run a nested event loop and outlast wall-clock action deadlines.
        after(0.5) {
            capture(motion, name: "menu")
            after(0.3) {
                motion.game.start(demo: true)
                after(6.5) {
                    capture(motion, name: "play")
                    let frozenTime = motion.game.state.elapsed
                    motion.stop()
                    after(0.4) {
                        capture(motion, name: "pause")
                        let pausePassed = motion.game.state.phase == .paused && motion.game.state.elapsed == frozenTime
                        motion.start(demo: true)
                        after(0.4) {
                            motion.game.resume()
                            monitor(motion, initialBest: initialBest, pausePassed: pausePassed)
                        }
                    }
                }
            }
        }
    }
    private static func after(_ delay: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
    private static func monitor(_ motion: MotionModel, initialBest: Int, pausePassed: Bool) {
        let start = ProcessInfo.processInfo.systemUptime
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            let game = motion.game
            if game.state.phase == .results || ProcessInfo.processInfo.systemUptime - start > 75 {
                timer.invalidate()
                capture(motion, name: "results")
                let passed = game.state.phase == .results && game.state.cuts > 0 && game.isDemo && game.bestScore == initialBest && pausePassed
                let report = "Game smoke: \(passed ? "PASS" : "FAIL")\nPhase: \(game.state.phase.rawValue)\nSimulated samples after reconnect: \(motion.samples)\nGeometric cuts: \(game.state.cuts)\nScore: \(game.state.score)\nHigh score unchanged: \(game.bestScore == initialBest)\nTracking loss froze game: \(pausePassed)\nHardware verified: false\n"
                try? report.write(to: motion.logDirectory.appendingPathComponent("game-smoke-result.txt"), atomically: true, encoding: .utf8)
                motion.stop()
                NSApp.terminate(nil)
            }
        }
    }
    static func capture(_ motion: MotionModel, name: String) {
        if let content = NSApp.windows.first?.contentView,
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("game-\(name)-ui.png"))
            }
        }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1340, height: 900))
        view.scene = motion.scene.scene
        view.antialiasingMode = .multisampling4X
        if let tiff = view.snapshot().tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: motion.logDirectory.appendingPathComponent("game-\(name)-scene.png"))
        }
    }
}
