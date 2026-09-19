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
}
