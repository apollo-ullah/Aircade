import XCTest
import Network
import simd
import MotionCore
import ControllerLink
@testable import Aircade

private final class TestPhonePeer {
    let id = UUID(), session = UUID()
    let link: ControllerLink
    var requests: [UUID] = []
    var roles: [ControllerRole] = []
    var greetings = 0
    var recenterRequests = 0
    var run: UUID?
    var cues: [(UUID, ControllerFeedback)] = []
    var role: ControllerRole { roles.last ?? .unassigned }
    init(port: NWEndpoint.Port, code: String) {
        link = ControllerLink(connection: NWConnection(host: "127.0.0.1", port: port, using: ControllerLink.parameters()))
        link.onReady = { [weak self] in
            guard let self else { return }
            self.link.send(.hello(code: code, controller: self.id, session: self.session))
        }
        link.onMessage = { [weak self] message in
            guard let self else { return }
            switch message {
            case .welcome(let player):
                XCTAssertTrue((0...2).contains(player)); self.greetings += 1
            case .assignment(let role): self.roles.append(role)
            case .poll(let request): self.requests.append(request)
            case .recenter: self.recenterRequests += 1
            case .activeRun(let id): self.run = id
            case let .feedbackEvent(run, cue): self.cues.append((run, cue))
            default: break
            }
        }
        link.start()
    }
    func respond(_ request: UUID, sequence: UInt64, age: Double = 0, session: UUID? = nil) {
        link.send(.sample(request: request, frame: PlayerControllerFrame(controllerID: id, sessionID: session ?? self.session,
            sequence: sequence, source: "iPhone", orientation: simd_quatf(angle: 0.45, axis: SIMD3<Float>(0, 0, 1)),
            ready: true, sampleAge: age)))
    }
    func close() { link.onMessage = nil; link.onReady = nil; link.cancel() }
}

final class ControllerSessionTests: XCTestCase {
    private func until(_ description: String, _ condition: @escaping () -> Bool) {
        let expectation = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
        expectation.expectationDescription = description
        wait(for: [expectation], timeout: 3)
    }
    private func peer(_ controllers: ControllerSession) throws -> TestPhonePeer {
        controllers.start()
        until("Phone host listening") { controllers.phoneHost.listeningPort != nil }
        let phone = TestPhonePeer(port: try XCTUnwrap(controllers.phoneHost.listeningPort), code: controllers.phoneHost.code)
        until("Phone paired") { controllers.phoneHost.connected && phone.greetings == 1 && !phone.roles.isEmpty }
        return phone
    }
    private func request(_ controllers: ControllerSession, _ phone: TestPhonePeer) throws -> UUID {
        let count = phone.requests.count
        until("One new poll") { controllers.tick(); return phone.requests.count == count + 1 }
        return try XCTUnwrap(phone.requests.last)
    }

    func testPersistentPairingRoleChangesAndDuelExitKeepCalibrationAndSample() throws {
        var now = 100.0
        let controllers = ControllerSession(clock: { now }, automaticTimer: false)
        let phone = try peer(controllers)
        defer { phone.close(); controllers.shutdown() }
        let port = controllers.phoneHost.listeningPort, code = controllers.phoneHost.code
        phone.respond(try request(controllers, phone), sequence: 1, age: 0.02)
        until("Accepted phone pose") { controllers.snapshot(for: .phone) != nil }
        let captured = try XCTUnwrap(controllers.snapshot(for: .phone))
        XCTAssertEqual(captured.capturedAt, 99.98, accuracy: 0.000001)

        controllers.selectSolo(.phone)
        until("Phone shows solo") { phone.role == .solo }
        let duel = MultiplayerModel(controllers: controllers)
        duel.open()
        until("Phone shows player two") { phone.role == .player(2) }
        controllers.assign(.phone, to: .one)
        until("Phone shows player one") { phone.role == .player(1) }
        XCTAssertEqual(controllers.device(for: .two), .airPod)
        XCTAssertEqual(controllers.snapshot(for: .one)?.controllerID, phone.id)
        duel.close()
        until("Solo role restored") { phone.role == .solo }
        XCTAssertTrue(controllers.phoneHost.connected)
        XCTAssertEqual(controllers.phoneHost.listeningPort, port)
        XCTAssertEqual(controllers.phoneHost.code, code)
        XCTAssertEqual(controllers.snapshot(for: .phone)?.capturedAt, captured.capturedAt)
        XCTAssertEqual(controllers.snapshot(for: .phone)?.sessionID, phone.session)
        XCTAssertEqual(phone.greetings, 1); XCTAssertEqual(phone.recenterRequests, 0)

        // A later duplicate poll does not re-date the sample or extend its freshness.
        now = 100.20
        phone.respond(try request(controllers, phone), sequence: 1)
        now = 100.24
        XCTAssertFalse(try XCTUnwrap(controllers.snapshot(for: .phone)).isFresh(at: now))
        XCTAssertEqual(controllers.snapshot(for: .phone)?.capturedAt, captured.capturedAt)
    }

    func testHostRejectsWrongEpochLateAndPreRecenterResponses() throws {
        var now = 100.0
        let controllers = ControllerSession(clock: { now }, automaticTimer: false)
        let phone = try peer(controllers)
        defer { phone.close(); controllers.shutdown() }
        let first = try request(controllers, phone)
        phone.respond(first, sequence: 1, session: UUID())
        // A second poll proves that the first response has been processed.
        until("Wrong session response finished") {
            controllers.tick(); return phone.requests.count >= 2
        }
        XCTAssertNil(controllers.snapshot(for: .phone))
        let second = try XCTUnwrap(phone.requests.last)
        now += 0.30; phone.respond(second, sequence: 2)
        until("Late response finished") {
            controllers.tick(); return phone.requests.count >= 3
        }
        XCTAssertNil(controllers.snapshot(for: .phone))
        phone.respond(try XCTUnwrap(phone.requests.last), sequence: 3, age: 0.04)
        until("Fresh current epoch accepted") { controllers.snapshot(for: .phone)?.sequence == 3 }
        let current = try XCTUnwrap(controllers.snapshot(for: .phone))
        XCTAssertEqual(current.age(at: now), 0.04, accuracy: 0.000001)

        let pending = try request(controllers, phone)
        controllers.recenter(.phone)
        until("Recenter reached phone") { phone.recenterRequests == 1 }
        XCTAssertNil(controllers.snapshot(for: .phone))
        phone.respond(pending, sequence: 4)
        // This new poll has a different request identity, so the old reply cannot satisfy it.
        let replacement = try request(controllers, phone)
        let requestedAt = now; now += 0.05
        phone.respond(replacement, sequence: 5, age: 0.02)
        until("Post-recenter sample accepted") { controllers.snapshot(for: .phone)?.sequence == 5 }
        let afterRecenter = try XCTUnwrap(controllers.snapshot(for: .phone))
        XCTAssertEqual(afterRecenter.capturedAt, requestedAt - 0.02, accuracy: 0.000001)
        XCTAssertEqual(afterRecenter.age(at: now), 0.07, accuracy: 0.000001, "True input age includes sender age and full RTT")
        XCTAssertEqual(phone.greetings, 1)
    }

    func testFeedbackUsesRunAndConnectionIdentityAndNeverLeaksAfterLeave() throws {
        let controllers = ControllerSession(automaticTimer: false)
        let phone = try peer(controllers)
        defer { phone.close(); controllers.shutdown() }
        let run = controllers.beginRun()
        until("Run delivered") { phone.run == run }
        controllers.sendFeedback(run: run, to: .airPod, cue: .hit)
        controllers.sendFeedback(run: run, to: .phone, cue: .block)
        until("Only phone cue delivered") { phone.cues.count == 1 }
        XCTAssertEqual(phone.cues[0].1, .block)
        controllers.endRun(run)
        let replacement = controllers.beginRun()
        controllers.sendFeedback(run: run, to: .phone, cue: .damage)
        controllers.sendFeedback(run: replacement, to: .phone, cue: .victory)
        until("Replacement run feedback delivered") { phone.cues.count == 2 }
        XCTAssertEqual(phone.cues.map(\.1), [.block, .victory])
        XCTAssertEqual(phone.cues.last?.0, replacement)

        controllers.forgetPhone()
        XCTAssertFalse(controllers.phoneHost.connected)
        let replacementPhone = try peer(controllers)
        defer { replacementPhone.close() }
        controllers.sendFeedback(run: replacement, to: .phone, cue: .defeat)
        // Ordered role acknowledgement ensures earlier outbound operations have drained.
        controllers.selectSolo(.phone)
        until("Reconnected phone assigned") { replacementPhone.role == .solo }
        XCTAssertTrue(replacementPhone.cues.isEmpty, "Old run must not address a new connection epoch")
    }

    func testAirPodSnapshotsRemainStableAndAssignmentsDoNotRecalibrate() throws {
        var now = 10.0
        let controllers = ControllerSession(clock: { now }, automaticTimer: false)
        var invalidations: [ControllerDevice] = [], samples: [ControllerDevice] = []
        controllers.onInvalidation = { device, _ in invalidations.append(device) }
        controllers.onInputChanged = { samples.append($0) }
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        XCTAssertTrue(controllers.submitAirPod(orientation: identity, source: "Left AirPod", ready: true, sampleTime: 9.98))
        let first = try XCTUnwrap(controllers.snapshot(for: .airPod))
        now = 10.1
        XCTAssertFalse(controllers.submitAirPod(orientation: identity, source: "Left AirPod", ready: true, sampleTime: 9.98))
        XCTAssertFalse(controllers.submitAirPod(orientation: identity, source: "Left AirPod", ready: true, sampleTime: 10.2))
        XCTAssertEqual(controllers.snapshot(for: .airPod)?.capturedAt, first.capturedAt)
        XCTAssertEqual(samples, [.airPod])
        controllers.assign(.airPod, to: .two)
        XCTAssertEqual(controllers.snapshot(for: .two)?.capturedAt, first.capturedAt)
        XCTAssertEqual(controllers.snapshot(for: .two)?.sessionID, first.sessionID)
        XCTAssertTrue(invalidations.isEmpty)
        XCTAssertTrue(controllers.submitAirPod(orientation: identity, source: "Right AirPod", ready: false, sampleTime: now))
        XCTAssertEqual(invalidations, [.airPod])
        XCTAssertNotEqual(controllers.snapshot(for: .airPod)?.sessionID, first.sessionID)
        XCTAssertFalse(try XCTUnwrap(controllers.snapshot(for: .airPod)).isFresh(at: now))
        controllers.invalidateAirPod(reason: "Stopped")
        XCTAssertNil(controllers.snapshot(for: .airPod))
        now += 0.3
        XCTAssertTrue(controllers.submitAirPod(orientation: identity, source: "Right AirPod", ready: true, sampleTime: now - 0.3))
        XCTAssertEqual(try XCTUnwrap(controllers.snapshot(for: .airPod)).capturedAt, now - 0.3, accuracy: 0.000001)
        XCTAssertFalse(try XCTUnwrap(controllers.snapshot(for: .airPod)).isFresh(at: now), "Reference replacement must retain the original sample age")
    }
}
