import AppKit
import XCTest
import MotionCore
@testable import Aircade

final class AIChallengeIntegrationTests: XCTestCase {
    /// Opt-in only: real model calls, actual SceneKit observations, normal HTTP input path.
    /// Ten independent seeded incoming balls. No automated human returns or leaderboard writes.
    func testLiveAstraTenBalls() throws {
        guard ProcessInfo.processInfo.environment["AIRCADE_ASTRA_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in live API rehearsal") }
        let scene = SaberScene(); scene.setSport(.tennis)
        let game = AIChallengeGame(scene: scene)
        game.connect()
        defer { game.disconnect() }
        let connected = expectation(for: NSPredicate { _, _ in game.connected }, evaluatedWith: nil)
        wait(for: [connected], timeout: 10)
        guard game.connected else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent(".local/astra-arena-rehearsal")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var reports: [[String: Any]] = []
        for trial in 0..<10 {
            game.start(playerName: "Scripted incoming ball", simulated: true, rehearsalSeed: trial)
            let complete = expectation(description: "Trial \(trial)")
            var last = ProcessInfo.processInfo.systemUptime
            var captured = false
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
                let now = ProcessInfo.processInfo.systemUptime, dt = now - last; last = now
                game.tick(delta: dt, now: now, inputReady: true)
                if !captured && game.match.elapsed >= 4 {
                    captured = true
                    try? scene.challengeJPEG()?.write(to: output.appendingPathComponent("trial-\(trial).jpg"))
                }
                if game.match.aiReturns > 0 || game.match.humanPoints > 0 || game.match.phase == .paused {
                    timer.invalidate(); complete.fulfill()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            wait(for: [complete], timeout: 18); timer.invalidate()
            reports.append(["trial":trial,"lane":[-2.5,0,2.5][trial%3],"returns":game.match.aiReturns,
                            "misses":game.match.humanPoints,"status":game.status,"action":game.lastAction,
                            "captureMS":game.captureMS,"latencyMS":game.latencyMS])
            game.pause("Between rehearsal trials")
        }
        try JSONSerialization.data(withJSONObject: ["hardwareVerified":false,"trials":reports], options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        XCTAssertGreaterThanOrEqual(reports.reduce(0) { $0 + ($1["returns"] as? Int ?? 0) }, 3, "Experimental usability gate: three returns out of ten")
    }
}
