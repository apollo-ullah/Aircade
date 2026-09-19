import XCTest
@testable import Aircade

final class AIChallengeScoresTests: XCTestCase {
    func score(id: String = UUID().uuidString, player: String? = "badge-a", provider: String = "jev", model: String = "typesafe-ai/jev", human: Int = 3, opponent: Int = 1, simulated: Bool = false, exhibition: Bool = false, interrupted: Bool = false, assisted: Bool = false) -> AIChallengeScore {
        AIChallengeScore(id: id, playerID: player, nickname: "Test player", provider: provider, model: model,
            controlMode: provider == "jev" ? "state" : "screen", rules: "controlled-v1", flightSeconds: 8,
            human: human, opponent: opponent, simulated: simulated, exhibition: exhibition, assisted: assisted,
            interrupted: interrupted, completed: true, createdAt: Date(), isPublic: true)
    }
    func testEligibilityAndPersistentIdempotentRanking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scores.json"), board = AIChallengeScores(url: url)
        let best = score(); board.record(best); board.record(best)
        for excluded in [score(player: nil), score(simulated: true), score(exhibition: true), score(interrupted: true), score(assisted: true)] {
            XCTAssertFalse(excluded.eligible); board.record(excluded)
        }
        board.record(score(human: 1, opponent: 2))
        board.record(score(player: "badge-b", human: 5, opponent: 0))
        board.record(score(player: "badge-c", provider: "astra", model: "gpt-6-astra", human: 9, opponent: 0))
        board.record(score(player: "badge-d", model: "future-model", human: 9, opponent: 0))
        var privateScore = score(player: "private-badge"); privateScore.isPublic = false; board.record(privateScore)
        XCTAssertEqual(board.records.count, 11)
        XCTAssertEqual(board.leaders(provider: "jev").map(\.playerID), ["badge-b", "badge-a"])
        XCTAssertEqual(AIChallengeScores(url: url).leaders(provider: "jev").map(\.id), board.leaders(provider: "jev").map(\.id))
    }
}
