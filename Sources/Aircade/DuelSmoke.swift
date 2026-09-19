import AppKit
import SceneKit

/// Opt-in native UI/render verification. It never opens physical Core Motion.
enum DuelSmoke {
    static func run(_ motion: MotionModel) {
        motion.showMultiplayer(true)
        let duel = motion.multiplayer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            capture(motion, name: "lobby")
            duel.setScripted(true); duel.tick(); duel.start()
            var capturedPlay = false
            let started = ProcessInfo.processInfo.systemUptime
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                if duel.match.phase == .playing && !capturedPlay && duel.match.elapsed > 0.5 {
                    capturedPlay = true; capture(motion, name: "play")
                }
                if duel.match.phase == .results || ProcessInfo.processInfo.systemUptime - started > 25 {
                    timer.invalidate(); capture(motion, name: "results")
                    let passed = duel.match.phase == .results && duel.match.winner == .one && duel.match.health == [5, 0]
                    let report = "Duel smoke: \(passed ? "PASS" : "FAIL")\nHealth: \(duel.match.health)\nElapsed: \(duel.match.elapsed)\nInputs: scripted\nHardware verified: false\n"
                    try? report.write(to: motion.logDirectory.appendingPathComponent("duel-smoke-result.txt"), atomically: true, encoding: .utf8)
                    duel.close(); NSApp.terminate(nil)
                }
            }
        }
    }
    static func capture(_ motion: MotionModel, name: String) {
        if let content = NSApp.windows.first?.contentView,
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("duel-\(name)-ui.png"))
            }
        }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1340, height: 900))
        view.scene = motion.multiplayer.scene.court.scene
        view.antialiasingMode = .multisampling4X
        if let tiff = view.snapshot().tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: motion.logDirectory.appendingPathComponent("duel-\(name)-scene.png"))
        }
    }
}
