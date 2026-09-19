import XCTest
import Network
import simd
import MotionCore
import ControllerLink
@testable import Aircade

final class MultiplayerIntegrationTests: XCTestCase {
    func testActualHostPairsPhoneKeepsPosesIndependentAndRejectsStaleInput() throws {
        let suite = "com.aircade.multiplayer-tests.\(UUID().uuidString)"
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let motion = MotionModel(logDirectory: logs)
        motion.gripDefaults = UserDefaults(suiteName: suite)!
        motion.smoothing = 0; motion.running = true
        let duel = motion.multiplayer
        motion.showMultiplayer(true)
        var phone: ControllerLink?
        defer {
            phone?.onReady = nil; phone?.onMessage = nil; phone?.cancel()
            duel.close(); motion.stop(); motion.gripDefaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: logs)
        }
        let listening = expectation(for: NSPredicate { _, _ in duel.listeningPort != nil }, evaluatedWith: nil)
        wait(for: [listening], timeout: 3)
        guard let port = duel.listeningPort else { return XCTFail("Listener did not start") }
        let link = ControllerLink(connection: NWConnection(host: "127.0.0.1", port: port, using: ControllerLink.parameters()))
        phone = link
        let id = UUID(), session = UUID()
        let phoneQ = simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 0, 1))
        var sequence: UInt64 = 0
        var oldSample = false
        var wrongSession = true
        link.onReady = { [weak link] in link?.send(.hello(code: duel.code, controller: id, session: session)) }
        link.onMessage = { [weak link] message in
            guard case let .poll(request) = message else { return }
            sequence += 1
            link?.send(.sample(request: request, frame: PlayerControllerFrame(controllerID: id,
                sessionID: wrongSession ? UUID() : session, sequence: sequence, source: "iPhone", orientation: phoneQ,
                ready: true, sampleAge: oldSample ? 2 : 0)))
        }
        link.start()
        let badPackets = expectation(for: NSPredicate { _, _ in sequence >= 3 }, evaluatedWith: nil)
        wait(for: [badPackets], timeout: 3)
        XCTAssertFalse(duel.ready[1], "Wrong session must not control the reserved player")
        wrongSession = false
        let phoneReady = expectation(for: NSPredicate { _, _ in duel.ready[1] }, evaluatedWith: nil)
        wait(for: [phoneReady], timeout: 3)
        XCTAssertFalse(duel.ready[0], "An iPhone must never masquerade as both players")
        let now = ProcessInfo.processInfo.systemUptime
        let neutral = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        motion.receive(q: neutral, euler: .zero, rate: .zero, accel: .zero, sensorTime: now, location: "Left", receivedAt: now)
        duel.tick()
        XCTAssertTrue(duel.bothReady)
        XCTAssertGreaterThan(abs(simd_dot(duel.orientation(.two)!.vector, phoneQ.vector)), 0.999)
        XCTAssertGreaterThan(abs(simd_dot(duel.orientation(.one)!.vector, neutral.vector)), 0.999)
        oldSample = true
        let stale = expectation(for: NSPredicate { _, _ in !duel.ready[1] }, evaluatedWith: nil)
        wait(for: [stale], timeout: 3)
        let later = ProcessInfo.processInfo.systemUptime
        motion.receive(q: neutral, euler: .zero, rate: .zero, accel: .zero, sensorTime: later, location: "Left", receivedAt: later)
        motion.recenter() // The test deliberately sent no AirPod packets during the network wait.
        duel.tick()
        XCTAssertTrue(duel.ready[0]); XCTAssertFalse(duel.ready[1])
        duel.forgetPhone()
        XCTAssertNil(duel.orientation(.two)); XCTAssertNotNil(duel.orientation(.one))
    }
}
