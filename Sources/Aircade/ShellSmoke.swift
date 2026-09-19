import AppKit

/// Opt-in native navigation check. It opens no physical motion source and saves no scores.
enum ShellSmoke {
    static func run(_ motion: MotionModel) {
        let routes: [Route] = [.home, .controller, .profile, .settings, .tennis, .home,
                               .neonRush, .home, .duel, .home, .scripts, .neonRush, .home]
        let code = motion.controllers.phoneHost.code
        var checks: [[String: Any]] = []
        var index = 0
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
            if index > 0 {
                let expected = routes[index - 1]
                let activeGameCorrect: Bool
                switch expected {
                case .tennis: activeGameCorrect = motion.tennis.enabled && !motion.game.enabled && !motion.showingMultiplayer
                case .neonRush: activeGameCorrect = motion.game.enabled && !motion.tennis.enabled && !motion.showingMultiplayer
                case .duel: activeGameCorrect = motion.showingMultiplayer && !motion.game.enabled && !motion.tennis.enabled
                default: activeGameCorrect = !motion.game.enabled && !motion.tennis.enabled && !motion.showingMultiplayer
                }
                let scriptCorrect = index == 12 ? motion.scriptedScenario != nil && motion.game.state.phase != .menu
                    : index == 13 ? motion.scriptedScenario == nil : true
                checks.append(["route": String(describing: expected),
                               "passed": motion.shellRoute == expected && activeGameCorrect && scriptCorrect && motion.controllers.phoneHost.code == code])
                if let view = NSApp.windows.first(where: { $0.contentView != nil })?.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: motion.logDirectory.appendingPathComponent("shell-\(index)-\(expected).png"))
                    }
                }
            }
            guard index < routes.count else {
                timer.invalidate()
                let report: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true },
                                              "checks": checks, "hardwareVerified": false]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: motion.logDirectory.appendingPathComponent("shell-smoke-result.json"))
                }
                NSApp.terminate(nil)
                return
            }
            if index == 11 { motion.startScripted(.perfectRun) }
            NotificationCenter.default.post(name: .wiiRouteRequest, object: routes[index])
            index += 1
        }
    }
}
