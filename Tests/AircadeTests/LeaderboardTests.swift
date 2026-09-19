import XCTest
import MotionCore
@testable import Aircade

final class LeaderboardTests: XCTestCase {
    @MainActor
    func testGameSelectionReachesBothLeaderboardAndStandingEndpoints() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let players = PlayerSession(queueDirectory: directory, automaticRetry: false,
            configurationProvider: { StationConfiguration(url: "http://127.0.0.1:8787", token: "test-only") },
            transport: { request in
                let mode = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "difficulty" })?.value ?? "Arcade"
                let data: Data
                if request.url!.path.hasSuffix("standing") {
                    data = try JSONEncoder().encode(LeaderboardStanding(difficulty: mode, isPublic: true, personalBest: nil, rank: nil, totalPlayers: 0, next: nil))
                } else {
                    data = try JSONEncoder().encode(LeaderboardBoard(difficulty: mode, totalPlayers: 0, rows: []))
                }
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        players.player = BadgePlayer(id: UUID().uuidString, nickname: "Test Player", isPublic: true)
        for mode in ["Arcade", "Chill", "Tennis"] { players.refreshLeaderboard(mode) }
        for _ in 0..<100 {
            if players.standings.count == 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        for mode in ["Arcade", "Chill", "Tennis"] {
            XCTAssertEqual(players.leaderboards[mode]?.difficulty, mode)
            XCTAssertEqual(players.standings[mode]?.difficulty, mode)
        }
    }

    func testScoreTargetMustBeatTieAndPrivateProfilesDoNotAdvertiseARank() {
        var standing = LeaderboardStanding(difficulty: "Tennis", isPublic: true, personalBest: 500,
            rank: 3, totalPlayers: 8, next: LeaderboardTarget(rank: 2, nickname: "Rival", score: 500, pointsNeeded: 1))
        XCTAssertEqual(standing.challenge, "Score 501 to pass Rival at #2.")
        standing.isPublic = false
        XCTAssertTrue(standing.challenge.contains("private"))
        XCTAssertFalse(standing.challenge.contains("Rival"))
    }

    @MainActor
    func testUploadedRankReceiptBelongsToTheFinishedRunAndClearsForNextPlayer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let playerID = UUID().uuidString
        let config = StationConfiguration(url: "http://127.0.0.1:8787", token: "test-only")
        let players = PlayerSession(queueDirectory: directory, automaticRetry: false, uploadOnFinish: false,
            configurationProvider: { config }, transport: { request in
                if request.url?.path == "/api/runs" {
                    let run = try JSONDecoder().decode(BadgeRun.self, from: XCTUnwrap(request.httpBody))
                    let progress = RankProgress(runID: run.id, playerID: playerID, newPersonalBest: true,
                        previousBest: 0, previousRank: 3, placesClimbed: 1,
                        standing: LeaderboardStanding(difficulty: "Arcade", isPublic: true, personalBest: 100,
                            rank: 2, totalPlayers: 3, next: nil))
                    let object = ["progress": try JSONSerialization.jsonObject(with: JSONEncoder().encode(progress))]
                    return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                throw URLError(.notConnectedToInternet)
            })
        players.player = BadgePlayer(id: playerID, nickname: "Test Player", isPublic: true)
        let run = players.beginRun(game: .neonRush, mode: "Arcade")
        var state = NeonRush(); state.start(difficulty: .arcade); state.advance(3); state.advance(NeonRush.duration)
        _ = players.finishRun(state, demo: false, runID: run.id)
        await players.flushPending()
        XCTAssertTrue(players.pendingRuns.isEmpty)
        XCTAssertEqual(players.lastRankProgress?.runID, run.id)
        XCTAssertEqual(players.lastRankProgress?.headline, "Up 1 place!")
        XCTAssertEqual(players.standings["Arcade"]?.rank, 2)
        players.logout()
        XCTAssertNil(players.lastRankProgress)
        XCTAssertTrue(players.standings.isEmpty)
    }

    func testFirstRankAndPersonalBestAreDistinctFromClimbing() {
        var receipt = RankProgress(runID: "test", playerID: "test", newPersonalBest: true, previousBest: nil,
            previousRank: nil, placesClimbed: 0,
            standing: LeaderboardStanding(difficulty: "Arcade", isPublic: true, personalBest: 100, rank: 8, totalPlayers: 8, next: nil))
        XCTAssertEqual(receipt.headline, "On the board at #8!")
        receipt.standing.isPublic = false
        XCTAssertEqual(receipt.headline, "New personal best!")
        receipt.newPersonalBest = false
        XCTAssertEqual(receipt.headline, "Another round in the books.")
    }
}
