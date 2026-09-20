import XCTest
import MotionCore
import simd
@testable import Aircade

/// The transport is deliberately allowed to finish after cancellation, proving
/// that lifecycle boundaries discard late model work rather than relying on HTTP.
final class TacticalOpponentLifecycleTests: XCTestCase {
    private final class Clock { var time = 100.0 }
    private final class Transport {
        struct Request {
            let body: [String: Any]
            let continuation: CheckedContinuation<Data, Error>
        }
        private let lock = NSLock()
        private var requests: [Request] = []
        var onRequest: (() -> Void)?
        var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
        func send(_ data: Data) async throws -> Data {
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock(); requests.append(Request(body: body, continuation: continuation)); lock.unlock()
                onRequest?()
            }
        }
        func request(_ index: Int) -> Request { lock.lock(); defer { lock.unlock() }; return requests[index] }
        func complete(_ index: Int, candidate: String = "deep-left", mutate: ([String: Any]) -> [String: Any] = { $0 }) throws {
            let request = request(index)
            let provider = request.body["provider"] as! String
            let shot = (request.body["candidates"] as! [[String: Any]]).first { $0["id"] as? String == candidate }!
            let response: [String: Any] = [
                "provider": provider == "astra" ? "OpenAI API" : "Vercel Jev",
                "modelVersion": provider == "astra" ? "gpt-6-astra" : "typesafe-ai/jev",
                "latencyMs": 80, "fallbackUsed": false,
                "observationID": request.body["observationID"]!, "decisionID": "decision-\(index)",
                "selectedCandidateID": candidate, "responseID": "response-\(index)",
                "inputSummary": "Score 0; five legal shots.",
                "returns": [["candidateID": candidate, "targetX": shot["targetX"]!,
                             "flightDuration": shot["flightDuration"]!, "delay": shot["delay"]!, "stroke": shot["stroke"]!]]
            ]
            request.continuation.resume(returning: try JSONSerialization.data(withJSONObject: mutate(response)))
        }
    }

    private func startRequest(_ transport: Transport, action: () -> Void) {
        let requested = expectation(description: "Transport received request")
        transport.onRequest = { requested.fulfill() }
        action()
        wait(for: [requested], timeout: 2)
        transport.onRequest = nil
    }
    private func finish(_ opponent: BasetenTennisOpponent, transport: Transport, index: Int,
                        candidate: String = "deep-left", expectedState: String = "Fresh",
                        mutate: ([String: Any]) -> [String: Any] = { $0 }) throws {
        let done = expectation(description: "Final \(expectedState) status")
        opponent.onStatus = { if $0.stateLabel == expectedState { done.fulfill() } }
        try transport.complete(index, candidate: candidate, mutate: mutate)
        wait(for: [done], timeout: 2)
        opponent.onStatus = nil
    }
    private func drainCancelledCompletion() {
        let drained = expectation(description: "Cancelled completion drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testExactSelectedShotIsAppliedOnlyAtContactAndNewResponseCannotRelabelIt() throws {
        let time = Clock(), transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send, clock: { time.time })
        opponent.select(provider: "astra")
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        time.time += 0.08
        try finish(opponent, transport: transport, index: 0)
        let first = opponent.returnPlan(rally: 0, sequence: 0)
        XCTAssertEqual(first.targetX, -3.1)
        XCTAssertEqual(first.flightDuration, 2.72)
        XCTAssertEqual(first.delay, 0.34)
        XCTAssertEqual(first.stroke, .forehand)
        XCTAssertNil(opponent.currentStatus.appliedDecisionID, "Preparing is not an applied shot")
        XCTAssertEqual(opponent.currentStatus.requestLatencyMS ?? 0, 80, accuracy: 0.001)

        time.time += 3
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        try finish(opponent, transport: transport, index: 1, candidate: "deep-right")
        opponent.markReturnApplied()
        let status = opponent.currentStatus
        XCTAssertEqual(status.selectedCandidateID, "deep-right")
        XCTAssertEqual(status.appliedCandidateID, "deep-left")
        XCTAssertEqual(status.decisionID, "decision-1")
        XCTAssertEqual(status.appliedDecisionID, "decision-0")
        XCTAssertEqual(status.appliedObservationID, transport.request(0).body["observationID"] as? String)
        XCTAssertEqual(status.stateLabel, "Cached")
        XCTAssertEqual(status.appliedObservationToShotMS ?? 0, 3080, accuracy: 0.001)
        XCTAssertEqual(transport.request(1).body["previousReturnX"] as? Double ?? 0, -3.1, accuracy: 0.0001)
    }

    func testProviderSwitchRejectsLateResponseAndRequiresNewValidatedPlan() throws {
        let transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send)
        opponent.select(provider: "astra")
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        opponent.select(provider: "jev")
        XCTAssertFalse(opponent.hasModelPlan)
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        try finish(opponent, transport: transport, index: 1, candidate: "right")
        try transport.complete(0)
        drainCancelledCompletion()
        XCTAssertEqual(opponent.currentStatus.provider, "Vercel Jev")
        XCTAssertEqual(opponent.currentStatus.selectedCandidateID, "right")
        XCTAssertEqual(opponent.returnPlan(rally: 0, sequence: 0).targetX, 1.55)
    }

    func testNewRunKeepsValidatedLobbyPlanAndInvalidatesInFlightRefresh() throws {
        let time = Clock(), transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send, clock: { time.time })
        opponent.select(provider: "astra")
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        try finish(opponent, transport: transport, index: 0)
        _ = opponent.returnPlan(rally: 0, sequence: 0)
        opponent.markReturnApplied()
        time.time += 3
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        opponent.beginRun()
        XCTAssertTrue(opponent.hasModelPlan)
        XCTAssertNil(opponent.currentStatus.appliedDecisionID)
        try transport.complete(1, candidate: "right")
        drainCancelledCompletion()
        XCTAssertEqual(opponent.currentStatus.selectedCandidateID, "deep-left")
        XCTAssertEqual(opponent.currentStatus.stateLabel, "Cached")
        opponent.markReturnApplied()
        XCTAssertNil(opponent.currentStatus.appliedDecisionID, "Previous run's prepared shot was cleared")
        _ = opponent.returnPlan(rally: 0, sequence: 0)
        opponent.markReturnApplied()
        XCTAssertEqual(opponent.currentStatus.appliedDecisionID, "decision-0")
    }

    func testPausePreservesPreparedShotButEndRunClearsIt() throws {
        let time = Clock(), transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send, clock: { time.time })
        opponent.select(provider: "astra")
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        try finish(opponent, transport: transport, index: 0)
        _ = opponent.returnPlan(rally: 0, sequence: 0)
        time.time += 3
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        opponent.suspend()
        opponent.refresh(playerID: nil, match: TennisMatch())
        XCTAssertEqual(transport.count, 2)
        try transport.complete(1, candidate: "middle")
        drainCancelledCompletion()
        opponent.resume()
        opponent.markReturnApplied()
        XCTAssertEqual(opponent.currentStatus.appliedDecisionID, "decision-0")
        opponent.endRun()
        XCTAssertFalse(opponent.hasModelPlan)
        XCTAssertNil(opponent.currentStatus.selectedCandidateID)
        XCTAssertNil(opponent.currentStatus.appliedDecisionID)
    }

    func testEndRunRejectsLateRequestAndClearsAppliedEvidence() throws {
        let transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send)
        opponent.select(provider: "astra")
        startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
        opponent.endRun()
        try transport.complete(0)
        drainCancelledCompletion()
        XCTAssertFalse(opponent.hasModelPlan)
        XCTAssertNil(opponent.currentStatus.selectedCandidateID)
        XCTAssertNil(opponent.currentStatus.appliedDecisionID)
        XCTAssertEqual(opponent.currentStatus.stateLabel, "Waiting")
    }

    func testRejectsWrongIdentityEchoFallbackAndModifiedLegalShot() throws {
        let mutations: [([String: Any]) -> [String: Any]] = [
            { var r = $0; r["provider"] = "Vercel Jev"; return r },
            { var r = $0; r["modelVersion"] = "another-model"; return r },
            { var r = $0; r["observationID"] = "stale-input"; return r },
            { var r = $0; r.removeValue(forKey: "decisionID"); return r },
            { var r = $0; r["fallbackUsed"] = true; return r },
            { var r = $0; r["selectedCandidateID"] = "right"; return r },
            { var r = $0; var shots = r["returns"] as! [[String: Any]]; shots[0]["targetX"] = -3.0; r["returns"] = shots; return r },
            { var r = $0; var shots = r["returns"] as! [[String: Any]]; shots[0]["flightDuration"] = 3.4; r["returns"] = shots; return r },
            { var r = $0; var shots = r["returns"] as! [[String: Any]]; shots[0]["delay"] = 0.35; r["returns"] = shots; return r },
            { var r = $0; var shots = r["returns"] as! [[String: Any]]; shots[0]["stroke"] = "backhand"; r["returns"] = shots; return r }
        ]
        for mutate in mutations {
            let transport = Transport()
            let opponent = BasetenTennisOpponent(transport: transport.send)
            opponent.select(provider: "astra")
            startRequest(transport) { opponent.refresh(playerID: nil, match: TennisMatch()) }
            try finish(opponent, transport: transport, index: 0, expectedState: "Unavailable", mutate: mutate)
            XCTAssertFalse(opponent.hasModelPlan)
            XCTAssertTrue(opponent.currentStatus.fallbackUsed)
            XCTAssertNil(opponent.currentStatus.selectedCandidateID)
        }
    }

    func testLobbyModelPrefetchSurvivesMissingInputButActiveTrackingLossCancelsIt() throws {
        let time = Clock(), transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send, clock: { time.time })
        let suite = "com.aircade.tactical-readiness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let game = TennisGame(scene: SaberScene(), opponent: opponent, automaticTimer: false,
                              clock: { time.time }, scoreDefaults: defaults)
        game.enabled = true; game.sound = false
        startRequest(transport) { game.selectTacticalOpponent("astra") }
        game.invalidateInput("Controller not connected yet")
        game.start()
        XCTAssertEqual(game.state.phase, .menu)
        XCTAssertEqual(game.opponentStatus.decision, "Requesting a model shot")
        let gameStatus = opponent.onStatus
        let ready = expectation(description: "Prefetched plan survives missing controller")
        opponent.onStatus = { status in
            gameStatus?(status)
            if status.stateLabel == "Fresh" { ready.fulfill() }
        }
        try transport.complete(0)
        wait(for: [ready], timeout: 2)
        opponent.onStatus = gameStatus
        XCTAssertTrue(game.opponentReady)
        XCTAssertFalse(game.liveReady)
        game.start()
        XCTAssertEqual(game.state.phase, .menu, "Prepared model alone cannot start gameplay")

        let pose = SaberPose(position: SIMD3<Float>(0, -0.5, 0), orientation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)))
        game.update(pose: pose, time: time.time, ready: true)
        time.time += 1
        game.start()
        XCTAssertEqual(game.state.phase, .menu, "Stale controller input cannot start gameplay")
        game.update(pose: pose, time: time.time, ready: true)
        startRequest(transport) { game.start() }
        for _ in 0..<185 {
            time.time += 1.0 / 60
            game.update(pose: pose, time: time.time, ready: true)
            game.tick()
        }
        XCTAssertEqual(game.state.phase, .playing)
        game.invalidateInput("Controller disconnected during the match")
        XCTAssertEqual(game.state.phase, .paused)
        XCTAssertFalse(game.liveReady)
        try transport.complete(1, candidate: "right")
        drainCancelledCompletion()
        XCTAssertEqual(game.opponentStatus.selectedCandidateID, "deep-left", "Active tracking loss must discard a late response")
        XCTAssertEqual(game.opponentStatus.stateLabel, "Cached")
        game.update(pose: pose, time: time.time, ready: true)
        game.tick()
        XCTAssertEqual(game.state.phase, .paused, "Restored input still requires explicit resume")
        game.leave()
    }

    func testGameInspectorSuspendsMenuRequestAndRequiresExplicitMatchResume() throws {
        let time = Clock(), transport = Transport()
        let opponent = BasetenTennisOpponent(transport: transport.send, clock: { time.time })
        let suite = "com.aircade.tactical-lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let game = TennisGame(scene: SaberScene(), opponent: opponent, automaticTimer: false,
                              clock: { time.time }, scoreDefaults: defaults)
        game.enabled = true; game.sound = false
        startRequest(transport) { game.selectTacticalOpponent("astra") }
        game.suspendOpponentForInspector()
        try transport.complete(0)
        drainCancelledCompletion()
        XCTAssertFalse(game.opponentReady)
        XCTAssertEqual(game.state.phase, .menu)
        startRequest(transport) { game.dismissOpponentInspector() }
        let gameStatus = opponent.onStatus
        let ready = expectation(description: "Lobby plan ready")
        opponent.onStatus = { status in
            gameStatus?(status)
            if status.stateLabel == "Fresh" { ready.fulfill() }
        }
        try transport.complete(1)
        wait(for: [ready], timeout: 2)
        opponent.onStatus = gameStatus
        let pose = SaberPose(position: SIMD3<Float>(0, -0.5, 0), orientation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)))
        game.update(pose: pose, time: time.time, ready: true)
        startRequest(transport) { game.start() }
        XCTAssertEqual(game.state.phase, .countdown)
        XCTAssertFalse(game.state.assistedOpponent, "Tactical Astra runs at normal speed")
        game.suspendOpponentForInspector()
        XCTAssertEqual(game.state.phase, .paused)
        let elapsed = game.state.elapsed
        time.time += 0.1
        game.update(pose: pose, time: time.time, ready: true)
        game.resume()
        XCTAssertEqual(game.state.phase, .paused, "Open inspector cannot be bypassed by keyboard resume")
        game.dismissOpponentInspector()
        game.tick()
        XCTAssertEqual(game.state.elapsed, elapsed)
        XCTAssertEqual(game.state.phase, .paused, "Closing inspector must not resume physics")
        try transport.complete(2, candidate: "right")
        drainCancelledCompletion()
        XCTAssertEqual(opponent.currentStatus.selectedCandidateID, "deep-left")
        startRequest(transport) { game.resume() }
        XCTAssertEqual(game.state.phase, .countdown)
        try transport.complete(3, candidate: "middle")
        drainCancelledCompletion()
        for _ in 0..<150 {
            time.time += 1.0 / 60
            game.update(pose: pose, time: time.time, ready: true)
            game.tick()
            if game.state.ball != nil { break }
        }
        XCTAssertEqual(game.state.ball?.to.x, 0, "Exact model choice reaches the real match ball")
        XCTAssertEqual(game.state.ball?.duration, 2.42)
        XCTAssertEqual(game.opponentStatus.appliedCandidateID, "middle")
        XCTAssertEqual(game.opponentStatus.appliedDecisionID, "decision-3")
        game.leave()
        XCTAssertEqual(game.state.phase, .menu)
        XCTAssertFalse(opponent.hasModelPlan)
    }
}
