import XCTest
import Network
import simd
import MotionCore
@testable import ControllerLink

final class ControllerLinkTests: XCTestCase {
    func testProtocolRoundTripPreservesIdentityAndRejectsOversizedMessages() throws {
        let id = UUID(), session = UUID()
        let encoded = try ControllerLink.encode(.hello(code: "123456", controller: id, session: session))
        let length = encoded.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertEqual(length, encoded.count - 4)
        let decoded = try JSONDecoder().decode(ControllerMessage.self, from: encoded.dropFirst(4))
        guard case let .hello(code, actualID, actualSession) = decoded else { return XCTFail() }
        XCTAssertEqual(code, "123456"); XCTAssertEqual(actualID, id); XCTAssertEqual(actualSession, session)
        XCTAssertThrowsError(try ControllerLink.encode(.feedback(String(repeating: "x", count: 9000))))
    }

    func testRealTCPLoopbackPollReturnsAnIndependentControllerFrame() throws {
        let listener = try NWListener(using: ControllerLink.parameters(), on: .any)
        let received = expectation(description: "Controller responds to host poll")
        let request = UUID(), controller = UUID(), session = UUID()
        var host: ControllerLink?, phone: ControllerLink?
        listener.newConnectionHandler = { connection in
            let link = ControllerLink(connection: connection); host = link
            link.onReady = { link.send(.poll(request: request)) }
            link.onMessage = { message in
                guard case let .sample(actual, frame) = message else { return }
                XCTAssertEqual(actual, request); XCTAssertEqual(frame.controllerID, controller)
                XCTAssertTrue(frame.isValid); XCTAssertEqual(frame.sequence, 7)
                received.fulfill()
            }
            link.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let link = ControllerLink(connection: NWConnection(host: "127.0.0.1", port: port, using: ControllerLink.parameters()))
            phone = link
            link.onMessage = { message in
                guard case let .poll(request) = message else { return }
                link.send(.sample(request: request, frame: PlayerControllerFrame(controllerID: controller, sessionID: session,
                    sequence: 7, source: "iPhone", orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), ready: true)))
            }
            link.start()
        }
        listener.start(queue: .main)
        wait(for: [received], timeout: 5)
        host?.onReady = nil; host?.onMessage = nil; phone?.onMessage = nil
        host?.cancel(); phone?.cancel(); listener.cancel()
    }

    func testPhoneRoleRecenterAndRunScopedFeedbackWireCompatibility() throws {
        func decode(_ message: ControllerMessage) throws -> ControllerMessage {
            try JSONDecoder().decode(ControllerMessage.self, from: ControllerLink.encode(message).dropFirst(4))
        }
        for role in [ControllerRole.unassigned, .solo, .player(1), .player(2)] {
            guard case .assignment(let result) = try decode(.assignment(role)) else { return XCTFail("Role envelope") }
            XCTAssertEqual(result, role); XCTAssertTrue(result.isValid)
        }
        XCTAssertFalse(ControllerRole.player(0).isValid)
        XCTAssertFalse(ControllerRole.player(3).isValid)
        for player in 0...2 {
            guard case .welcome(let result) = try decode(.welcome(player: player)) else { return XCTFail("Greeting") }
            XCTAssertEqual(result, player)
        }
        guard case .recenter = try decode(.recenter) else { return XCTFail("Recenter") }
        let run = UUID()
        guard case .activeRun(let active) = try decode(.activeRun(run)) else { return XCTFail("Run") }
        XCTAssertEqual(active, run)
        guard case .activeRun(let ended) = try decode(.activeRun(nil)) else { return XCTFail("Run end") }
        XCTAssertNil(ended)
        for cue in ControllerFeedback.allCases {
            guard case let .feedbackEvent(resultRun, resultCue) = try decode(.feedbackEvent(run: run, cue: cue)) else {
                return XCTFail("Feedback")
            }
            XCTAssertEqual(resultRun, run); XCTAssertEqual(resultCue, cue)
        }
    }
}
