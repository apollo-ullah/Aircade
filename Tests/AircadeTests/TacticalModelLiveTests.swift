import XCTest
import MotionCore
@testable import Aircade

final class TacticalModelLiveTests: XCTestCase {
    /// The first request is real in the opt-in test. Later refresh attempts are
    /// deliberately stopped at transport, keeping the live billable budget at
    /// one request per provider without fabricating any replacement decisions.
    private final class OneRequestTransport {
        private let lock = NSLock()
        private var used = false
        private let operation: BasetenTennisOpponent.Transport
        init(operation: @escaping BasetenTennisOpponent.Transport) { self.operation = operation }
        func send(_ data: Data) async throws -> Data {
            try reserve()
            return try await operation(data)
        }
        private func reserve() throws {
            lock.lock(); defer { lock.unlock() }
            guard !used else { throw URLError(.cancelled) }
            used = true
        }
    }

    func testSimulatedControllerContactPreservesDecisionProvenanceOffline() throws {
        for provider in ["astra", "jev"] {
            let bounded = OneRequestTransport { data in
                let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let shot = (request["candidates"] as! [[String: Any]]).first { $0["id"] as? String == "deep-left" }!
                return try JSONSerialization.data(withJSONObject: [
                    "provider": provider == "astra" ? "OpenAI API" : "Vercel Jev",
                    "modelVersion": provider == "astra" ? "gpt-6-astra" : "typesafe-ai/jev",
                    "latencyMs": 0, "fallbackUsed": false,
                    "observationID": request["observationID"]!, "decisionID": "mock-decision",
                    "selectedCandidateID": "deep-left", "responseID": "mock-response",
                    "inputSummary": "Mock fixture; five legal shots.",
                    "returns": [["candidateID": "deep-left", "targetX": shot["targetX"]!,
                                 "flightDuration": shot["flightDuration"]!, "delay": shot["delay"]!, "stroke": shot["stroke"]!]]
                ])
            }
            _ = try verifyControllerContact(provider: provider, transport: bounded.send, live: false)
        }
    }

    func testLiveAPIDecisionSurvivesActualSimulatedControllerContact() throws {
        guard ProcessInfo.processInfo.environment["AIRCADE_TACTICAL_CONTACT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in: three real API calls; scripted controller poses, not physical hardware")
        }
        var reports: [[String: Any]] = []
        for provider in ["baseten", "astra", "jev"] {
            let bounded = OneRequestTransport(operation: BasetenTennisOpponent.stationRequest)
            reports.append(try verifyControllerContact(provider: provider, transport: bounded.send, live: true))
        }
        let report: [String: Any] = [
            "capturedAt": ISO8601DateFormatter().string(from: Date()), "liveAPI": true,
            "physicalHardwareVerified": false, "controller": "accelerated simulated poses through TennisGame.update",
            "scope": "One real API decision per provider, then explicitly cached shots through production collision and opponent-return events. This does not verify physical controller feel or real-time model refresh.",
            "results": reports
        ]
        if let path = ProcessInfo.processInfo.environment["AIRCADE_TACTICAL_CONTACT_REPORT"] {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        }
    }

    private func verifyControllerContact(provider: String, transport: @escaping BasetenTennisOpponent.Transport,
                                         live: Bool) throws -> [String: Any] {
        let opponent = BasetenTennisOpponent(transport: transport)
        opponent.select(provider: provider)
        let ready = expectation(description: "\(provider) final decision")
        var initial: TennisOpponentStatus?
        opponent.onStatus = { status in
            guard status.stateLabel == "Fresh" || status.stateLabel == "Unavailable" else { return }
            initial = status; ready.fulfill()
        }
        opponent.refresh(playerID: nil, match: TennisMatch())
        wait(for: [ready], timeout: 12)
        let decision = try XCTUnwrap(initial)
        XCTAssertEqual(decision.stateLabel, "Fresh", decision.label)
        XCTAssertTrue(opponent.hasModelPlan, decision.label)
        let decisionID = try XCTUnwrap(decision.decisionID)
        let observationID = try XCTUnwrap(decision.observationID)
        let selected = try XCTUnwrap(decision.selectedCandidateID)
        let expected: [String: (Float, Double)] = ["deep-left": (-3.1, 2.72), "left": (-1.55, 2.88),
                                                "middle": (0, 2.42), "right": (1.55, 2.86), "deep-right": (3.1, 2.68)]
        let target = try XCTUnwrap(expected[selected])
        let rig = TennisIntegrationTests.Rig(demo: true, opponent: opponent)
        defer { rig.game.leave() }
        var humanContact = false
        var subsequentOpponentReturn = false
        rig.game.onJudgment = { event in
            if case .playerReturn = event { humanContact = true }
            if case .opponentReturn = event, humanContact { subsequentOpponentReturn = true }
        }
        rig.run(returning: true, until: { subsequentOpponentReturn })
        XCTAssertTrue(humanContact, "Scripted orientation must pass the production racket/ball collision")
        XCTAssertGreaterThan(rig.game.state.returns, 0)
        XCTAssertTrue(subsequentOpponentReturn, "Require a return after the player contact, not only the opening serve")
        let ball = try XCTUnwrap(rig.game.state.ball)
        XCTAssertEqual(ball.direction, .towardPlayer)
        XCTAssertEqual(ball.to.x, target.0)
        XCTAssertEqual(ball.duration, target.1, "Normal tactical pace must preserve the exact legal shot")
        let applied = rig.game.opponentStatus
        XCTAssertEqual(applied.appliedCandidateID, selected)
        XCTAssertEqual(applied.appliedDecisionID, decisionID)
        XCTAssertEqual(applied.appliedObservationID, observationID)
        XCTAssertEqual(applied.stateLabel, "Cached", "A reused decision is not a fresh API call")
        let observationToShot = try XCTUnwrap(applied.appliedObservationToShotMS)
        let requestMS = try XCTUnwrap(decision.requestLatencyMS)
        XCTAssertGreaterThanOrEqual(observationToShot, requestMS)
        XCTAssertTrue(rig.game.isDemo)
        XCTAssertEqual(rig.starts, [true])
        XCTAssertFalse(rig.game.state.assistedOpponent)
        XCTAssertEqual(rig.defaults.integer(forKey: "tennis.best"), 0)
        let result: [String: Any] = [
            "provider": provider, "model": decision.modelVersion, "liveAPI": live,
            "candidateID": selected, "decisionID": decisionID, "observationID": observationID,
            "responseID": decision.responseID ?? "unavailable", "requestLatencyMS": requestMS,
            "observationToAppliedShotWallMS": observationToShot,
            "simulatedMatchElapsedSeconds": rig.game.state.elapsed, "humanContactReturns": rig.game.state.returns,
            "opponentReturnedAfterHumanContact": subsequentOpponentReturn,
            "appliedCandidateID": applied.appliedCandidateID ?? "unavailable", "appliedDecisionID": applied.appliedDecisionID ?? "unavailable",
            "appliedObservationID": applied.appliedObservationID ?? "unavailable", "state": applied.stateLabel,
            "simulatedInput": true, "scoreEligible": false, "physicalHardwareVerified": false
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("NATIVE TACTICAL CONTACT \(live ? "LIVE API" : "MOCK API") · SIMULATED INPUT: \(String(decoding: json, as: UTF8.self))")
        return result
    }

    func testLiveProvidersDriveActualReturnPlanWithoutReordering() throws {
        guard ProcessInfo.processInfo.environment["AIRCADE_TACTICAL_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in real model test") }
        for provider in ["baseten", "jev", "astra"] {
            let opponent = BasetenTennisOpponent()
            opponent.select(provider: provider)
            var observed: TennisOpponentStatus?
            let ready = expectation(description: "\(provider) model-selected plan")
            opponent.onStatus = { status in
                guard status.stateLabel == "Fresh" || status.stateLabel == "Unavailable" else { return }
                observed = status; ready.fulfill()
            }
            opponent.refresh(playerID: nil, match: TennisMatch())
            wait(for: [ready], timeout: 12)
            let status = try XCTUnwrap(observed)
            XCTAssertFalse(status.fallbackUsed, status.label)
            XCTAssertTrue(opponent.hasModelPlan)
            let id = try XCTUnwrap(status.selectedCandidateID, status.label)
            XCTAssertEqual(status.stateLabel, "Fresh")
            XCTAssertNotNil(status.observationID)
            XCTAssertNotNil(status.decisionID)
            let expected: [String: Float] = ["deep-left": -3.1, "left": -1.55, "middle": 0, "right": 1.55, "deep-right": 3.1]
            let x = try XCTUnwrap(expected[id], status.label)
            for sequence in 0..<3 {
                let plan = opponent.returnPlan(rally: sequence, sequence: sequence)
                XCTAssertEqual(plan.targetX, x, accuracy: 0.001)
                XCTAssertLessThan(plan.flightDuration, 3)
                XCTAssertEqual(plan.validated(fallback: plan).targetX, x, accuracy: 0.001)
            }
            opponent.endRun()
            print("LIVE TACTICAL \(provider): \(status.label)")
        }
    }
}
