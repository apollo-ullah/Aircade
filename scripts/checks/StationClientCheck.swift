import Foundation
import MotionCore
import CoreImage
import Vision

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
        // A generated test QR goes through the production Vision reader, not a mocked scanner.
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("native-client-test-badge".utf8), forKey: "inputMessage")
        let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let canvas = qr.transformed(by: CGAffineTransform(translationX: 40, y: 40))
            .composited(over: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: qr.extent.width + 80, height: qr.extent.height + 80)))
        let image = CIContext().createCGImage(canvas, from: canvas.extent)!
        let scan = BadgeScanner.read(using: VNImageRequestHandler(cgImage: image, orientation: .up))
        try check(scan?.payload == "native-client-test-badge", "Vision did not read the test badge")
        let session = PlayerSession(queueDirectory: root, automaticRetry: false)
        try check(session.authorize() && !session.showingSignIn, "Guest play must not require a profile")
        session.signIn(scan!.payload, suggestedName: "Test Name")
        try await wait { !session.busy }
        try check(session.player != nil, session.message)
        try check(session.suggestedName == "Test Name" && session.player!.nickname != "Test Name", "OCR requires confirmation")
        session.saveProfile(nickname: "Native Test Player", isPublic: true)
        try await wait { !session.busy }
        let originalID = session.player!.id
        session.signIn(scan!.payload, suggestedName: "Wrong OCR")
        try await wait { !session.busy }
        try check(session.player?.id == originalID && session.suggestedName == nil, "Returning badge identity/name changed")
        var result = NeonRush(); result.start(difficulty: .arcade); result.advance(3); result.advance(NeonRush.duration)
        let demo = session.beginRun(game: .neonRush, mode: "Arcade", simulated: true)
        session.finishRun(result, demo: true, runID: demo.id)
        try check(session.pendingRuns.isEmpty, "Demo entered upload queue")
        var offline = try JSONSerialization.jsonObject(with: goodConfig) as! [String: Any]
        offline["url"] = "http://127.0.0.1:1"
        try JSONSerialization.data(withJSONObject: offline).write(to: configURL)
        let round = session.beginRun(game: .neonRush, mode: "Arcade")
        session.logout() // Upload ownership stays with the player at start.
        session.finishRun(result, demo: false, runID: round.id)
        await session.flushPending()
        let queue = root.appendingPathComponent("pending-runs.json")
        let stored = try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: queue))
        try check(stored.count == 1 && stored[0].playerID == originalID, "Lost queued score or changed owner")
        try goodConfig.write(to: configURL)
        let restored = PlayerSession(queueDirectory: root, automaticRetry: false)
        restored.signIn(scan!.payload)
        try await wait { !restored.busy }
        await restored.flushPending()
        try await wait { restored.bests["Arcade"] != nil && restored.lastRankProgress?.runID == round.id }
        try check(restored.pendingRuns.isEmpty && restored.lastRankProgress?.standing.rank != nil, "Upload or ranking receipt failed")
        restored.refreshLeaderboard("Arcade")
        try await wait { restored.leaderboards["Arcade"]?.rows.contains(where: { $0.nickname == "Native Test Player" }) == true }
        var tennis = TennisMatch(); let opponent = AutomaticReboundOpponent()
        tennis.start(); tennis.advance(3, opponent: opponent); tennis.advance(TennisMatch.duration, opponent: opponent)
        let rally = restored.beginRun(game: .tennis, mode: "Tennis")
        restored.finishTennis(tennis, demo: false, runID: rally.id)
        await restored.flushPending()
        try await wait { restored.bests["Tennis"] != nil && restored.lastRankProgress?.runID == rally.id }
        try check(restored.lastRankProgress?.standing.difficulty == "Tennis", "Tennis board mixed with Neon Rush")
        restored.refreshLeaderboard("Tennis")
        try await wait { restored.leaderboards["Tennis"]?.difficulty == "Tennis" && restored.standings["Tennis"]?.difficulty == "Tennis" }
        try check(restored.leaderboards["Tennis"]?.rows.contains(where: { $0.nickname == "Native Test Player" }) == true, "Tennis score missing from its own board")
        restored.logout()
        try check(restored.player == nil && restored.standings.isEmpty && restored.lastRankProgress == nil, "Logout leaked previous rank")
        print("PASS: generated QR → real Vision reader → native badge/profile → MongoDB → offline restart/retry → native Neon Rush/Tennis ranks and public board; no physical badge or gameplay claim")
    }
}
