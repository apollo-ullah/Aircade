import XCTest
import MotionCore
@testable import Aircade

final class TacticalModelLiveTests: XCTestCase {
    func testLiveProvidersDriveActualReturnPlanWithoutReordering() throws {
        guard ProcessInfo.processInfo.environment["AIRCADE_TACTICAL_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in real model test") }
        for provider in ["baseten", "jev"] {
            let opponent = BasetenTennisOpponent()
            opponent.select(provider: provider)
            var observed: TennisOpponentStatus?
            let ready = expectation(description: "\(provider) model-selected plan")
            opponent.onStatus = { status in observed = status; ready.fulfill() }
            opponent.refresh(playerID: nil, match: TennisMatch())
            wait(for: [ready], timeout: 12)
            let status = try XCTUnwrap(observed)
            XCTAssertFalse(status.fallbackUsed, status.label)
            XCTAssertTrue(opponent.hasModelPlan)
            let id = status.decision.replacingOccurrences(of: "Model chose ", with: "")
            let expected: [String: Float] = ["deep-left": -3.1, "left": -1.55, "middle": 0, "right": 1.55, "deep-right": 3.1]
            let x = try XCTUnwrap(expected[id], status.label)
            for sequence in 0..<3 {
                let plan = opponent.returnPlan(rally: sequence, sequence: sequence)
                XCTAssertEqual(plan.targetX, x, accuracy: 0.001)
                XCTAssertLessThan(plan.flightDuration, 3)
                XCTAssertEqual(plan.validated(fallback: plan).targetX, x, accuracy: 0.001)
            }
            print("LIVE TACTICAL \(provider): \(status.label)")
        }
    }
}
