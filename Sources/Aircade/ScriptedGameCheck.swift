import AppKit
import MotionCore
import SwiftUI

/// Opt-in rendered checks. The script only supplies poses; this observes the
/// production game's judgments and finish state, including audio and effects.
enum ScriptedGameCheck {
    static func previewSetup(_ motion: MotionModel) {
        let host = NSHostingView(rootView: ScriptedControllerSetup(motion: motion, done: {}))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.center(); window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: motion.logDirectory.appendingPathComponent("scripted-setup-preview.png"))
                }
            }
            window.orderOut(nil)
            NSApp.terminate(nil)
        }
    }

    static func run(_ motion: MotionModel, reproduce: Bool = false) {
        let name = reproduce ? "scripted-repro" : "scripted-win"
        var judgments: [String: Int] = [:]
        motion.game.onJudgment = { event in judgments[String(describing: event.kind), default: 0] += 1 }
        let initialBest = motion.game.bestScore
        motion.game.sound = true
        motion.startScripted(reproduce ? .missAll : .perfectRun)
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            let game = motion.game
            let expired = ProcessInfo.processInfo.systemUptime - started > 100
            guard game.state.phase == .results || game.state.phase == .paused || expired else { return }
            timer.invalidate()
            let expectedFinish = reproduce
                ? game.state.phase == .results && !game.state.completed && game.state.lives == 0 && game.state.mistakes == game.difficulty.lives && game.state.score == 0
                : game.state.completed && game.state.lives == game.difficulty.lives && game.state.mistakes == 0 && game.state.cuts > 20
            let passed = expectedFinish && game.isDemo && game.bestScore == initialBest
            let report: [String: Any] = [
                "check": name, "passed": passed, "phase": game.state.phase.rawValue,
                "completed": game.state.completed, "score": game.state.score,
                "cuts": game.state.cuts, "lives": game.state.lives, "mistakes": game.state.mistakes,
                "elapsedGameSeconds": game.state.elapsed, "judgments": judgments,
                "pauseReason": game.pauseReason, "soundEnabled": game.sound,
                "maxFeedbackSeconds": game.maxFeedbackSeconds, "maxFrameSeconds": game.maxFrameSeconds,
                "slowFrames": game.slowFrames, "highScoreUnchanged": game.bestScore == initialBest,
                "hardwareVerified": false, "controller": "scripted poses through production collision code"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("\(name)-result.json"))
            }
            GameSmoke.capture(motion, name: name)
            motion.stop()
            NSApp.terminate(nil)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
