import Foundation
import MotionCore

@main struct StationClientCheck {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AIRCADE_CHECK_DIRECTORY"]!)
        let configURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AIRCADE_STATION_CONFIG"]!)
        let goodConfig = try Data(contentsOf: configURL)
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }
            throw NSError(domain: "StationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out"])
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "StationCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let session = PlayerSession(queueDirectory: root, automaticRetry: false)
        try check(!session.authorize() && session.showingSignIn, "Physical play must require a profile")
        session.signIn("native-client-test-badge", suggestedName: "Test Name")
        try await wait { !session.busy }
        try check(session.player != nil, session.message)
        try check(session.suggestedName == "Test Name", "First scan should suggest the OCR name")
        try check(session.player!.nickname != "Test Name", "OCR must not save a name without confirmation")
        session.saveProfile(nickname: "Chosen Name", isPublic: false)
        try await wait { !session.busy }
        let originalID = session.player!.id
        session.signIn("native-client-test-badge", suggestedName: "Wrong OCR")
        try await wait { !session.busy }
        try check(session.player?.id == originalID, "Returning badge changed identity")
        try check(session.suggestedName == nil && session.player?.nickname == "Chosen Name", "Returning name must not be overwritten")
        try check(BadgeNameReader.clean("Badge ID: something") == nil && BadgeNameReader.clean("x@example.com") == nil, "Reject badge labels and email")
        try check(BadgeNameReader.clean("  Élodie   O’Neil ") == "Élodie O’Neil", "Preserve Unicode names")
        var state = NeonRush(); state.start(difficulty: .arcade)
        session.beginRun(demo: true); session.finishRun(state, demo: true)
        let queue = root.appendingPathComponent("pending-runs.json")
        try check(!FileManager.default.fileExists(atPath: queue.path), "Demo entered upload queue")
        var offline = try JSONSerialization.jsonObject(with: goodConfig) as! [String: Any]
        offline["url"] = "http://127.0.0.1:1"
        try JSONSerialization.data(withJSONObject: offline).write(to: configURL)
        session.beginRun(demo: false)
        session.player = nil // Score ownership must be the profile captured at start.
        session.finishRun(state, demo: false)
        try await wait { session.saveStatus.contains("queued") }
        let stored = try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: queue))
        try check(stored.count == 1 && stored[0].playerID == originalID, "Lost queued score or changed owner")
        try goodConfig.write(to: configURL)
        let restored = PlayerSession(queueDirectory: root, automaticRetry: false)
        restored.flush()
        try await wait { restored.saveStatus == "Score saved to MongoDB." }
        try check(try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: queue)).isEmpty, "Queue did not drain")
        restored.signIn("native-client-test-badge")
        try await wait { !restored.busy }
        restored.refreshBests()
        try await wait { restored.bests["Arcade"] != nil }
        restored.logout()
        try check(restored.player == nil && restored.bests.isEmpty && !restored.showingSignIn, "Logout must clear only the active player state")
        restored.signIn("native-client-test-badge")
        try await wait { !restored.busy }
        try await wait { restored.bests["Arcade"] != nil }
        try check(restored.player?.id == originalID, "Rescan after logout must restore the same profile")
        restored.beginRun(demo: false)
        var tennis = TennisMatch()
        let opponent = AutomaticReboundOpponent()
        tennis.start(); tennis.advance(3, opponent: opponent); tennis.advance(0.25, opponent: opponent)
        tennis.advance(tennis.ball!.duration, opponent: opponent)
        _ = tennis.playerHit(speed: 2, horizontalDirection: 0)
        restored.finishTennis(tennis, demo: false)
        try await wait { restored.bests["Tennis"] != nil }
        try check(restored.bests["Tennis"] == tennis.score, "Tennis best was not attached to the badge profile")
        print("PASS: native profile recognition, scan gate, logout/rescan, demo exclusion, frozen run identity, offline persistence, restart/retry, Neon Rush and Tennis per-player bests")
    }
}
