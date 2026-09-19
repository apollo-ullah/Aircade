import XCTest
import Network
import simd
import MotionCore
import ControllerLink
@testable import Aircade

/// A real loopback ControllerLink client. Only the phone's sensor readings and
/// the host clock are synthetic; routing, freshness, collision and scoring are production code.
private final class ArcadeTestPhone {
    let id = UUID()
    let sessionID = UUID()
    let link: ControllerLink
    var orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
    var simulated = false
    var ready = true
    var sequence: UInt64 = 0
    var greetings = 0
    var transportReady = false
    var closeReason = ""
    var recenterRequests = 0
    var role: ControllerRole = .unassigned
    var cues: [(UUID, ControllerFeedback)] = []

    init(port: NWEndpoint.Port, code: String) {
        link = ControllerLink(connection: NWConnection(host: "127.0.0.1", port: port, using: ControllerLink.parameters()))
        link.onReady = { [weak self] in
            guard let self else { return }
            self.transportReady = true
            self.link.send(.hello(code: code, controller: self.id, session: self.sessionID))
        }
        link.onClose = { [weak self] error in self?.closeReason = String(describing: error) }
        link.onMessage = { [weak self] message in
            guard let self else { return }
            switch message {
            case .welcome: self.greetings += 1
            case .assignment(let role): self.role = role
            case .recenter: self.recenterRequests += 1
            case let .feedbackEvent(run, cue): self.cues.append((run, cue))
            case .poll(let request):
                self.sequence += 1
                self.link.send(.sample(request: request, frame: PlayerControllerFrame(
                    controllerID: self.id, sessionID: self.sessionID, sequence: self.sequence,
                    source: "iPhone", orientation: self.orientation, ready: self.ready,
                    simulated: self.simulated, sampleAge: 0)))
            default: break
            }
        }
        link.start()
    }

    func close() { link.onReady = nil; link.onMessage = nil; link.cancel() }
}

final class ArcadeSessionIntegrationTests: XCTestCase {
    private final class Rig {
        private var gameTime = 100.0
        private let transportOrigin = ProcessInfo.processInfo.systemUptime
        // Keep real packet timestamps strictly advancing while accelerating the
        // game. Freezing network time creates changed poses at identical times.
        var time: Double { gameTime + ProcessInfo.processInfo.systemUptime - transportOrigin }
        let model: MotionModel
        let defaults: UserDefaults
        let suite = "com.aircade.cross-game.\(UUID().uuidString)"
        let directory: URL
        var phone: ArcadeTestPhone!
        var feedAirPod = false

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defaults = UserDefaults(suiteName: suite)!
            model = MotionModel(logDirectory: directory, scoreDefaults: defaults)
            model.clock = { [unowned self] in self.time }
            model.gripDefaults = defaults
            model.smoothing = 0
            model.game.sound = false
            model.game.renderingEnabled = false
            model.tennis.sound = false
            model.startControllerSession()
            try pump("host listener") {
                self.model.controllers.phoneHost.listeningPort != nil &&
                self.model.controllers.phoneHost.networkStatus == "Visible to nearby iPhones"
            }
            phone = ArcadeTestPhone(port: try XCTUnwrap(model.controllers.phoneHost.listeningPort),
                                    code: model.controllers.phoneHost.code)
            try pump("paired phone") { self.phone.greetings == 1 && self.model.controllers.phoneHost.connected }
            model.controllers.selectSolo(.phone)
            try publishPhone()
        }

        func close() {
            phone?.close()
            model.game.enabled = false
            model.tennis.enabled = false
            model.multiplayer.close()
            model.shutdownControllerSession()
            model.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func pump(_ description: String, _ condition: @escaping () -> Bool) throws {
            if condition() { return }
            let completed = XCTestExpectation(description: description)
            var done = false
            let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] _ in
                guard !done else { return }
                self?.model.controllers.tick()
                if condition() { done = true; completed.fulfill() }
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate() }
            guard XCTWaiter.wait(for: [completed], timeout: 3) == .completed else {
                throw NSError(domain: "ArcadeSessionIntegrationTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(description): \(model.controllers.phoneHost.networkStatus); \(model.controllers.phoneHost.status); transport=\(phone?.transportReady == true) greetings=\(phone?.greetings ?? 0) close=\(phone?.closeReason ?? "")"])
            }
        }

        func publishPhone() throws {
            let prior = model.controllers.snapshot(for: .phone)?.sequence ?? 0
            let requestedAfter = time
            try pump("current phone sample") {
                guard let sample = self.model.controllers.snapshot(for: .phone) else { return false }
                return sample.sequence > prior && sample.capturedAt >= requestedAfter
            }
        }

        func step(_ delta: Double = 0.05) throws {
            gameTime += delta
            if feedAirPod {
                model.running = true // Never start CMHeadphoneMotionManager in a test.
                model.receive(q: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                              euler: .zero, rate: .zero, accel: .zero,
                              sensorTime: time, location: "Left", receivedAt: time)
            }
            try publishPhone()
            model.tick()
            if model.showingMultiplayer { model.multiplayer.tick() }
            else if model.selectedSport == .tennis { model.tennis.tick() }
            else { model.game.tick() }
        }

        func advance(until condition: () -> Bool, maxSteps: Int = 1600) throws {
            for _ in 0..<maxSteps {
                if condition() { return }
                try step()
            }
            XCTFail("Game failed to reach expected state: rush=\(model.game.state.phase), tennis=\(model.tennis.state.phase)")
        }

        func startRush() throws {
            model.selectSport(.neonRush)
            try publishPhone()
            model.game.start(demo: false, seed: 42)
            XCTAssertEqual(model.game.state.phase, .countdown)
            try advance(until: { self.model.game.state.phase == .playing })
        }

        /// Swing orientation alone through the first block from the production
        /// solo hilt. No direct contact(), judgment or score injection is used.
        func hitFirstRushBlock() throws {
            try advance(until: { !self.model.game.state.targets.isEmpty })
            let target = try XCTUnwrap(model.game.state.targets.first)
            let angle = atan2(-target.x, target.y + 0.5)
            phone.orientation = simd_quatf(angle: angle + 0.55, axis: SIMD3<Float>(0, 0, 1))
            try advance(until: { self.model.game.state.elapsed >= target.arrival + 0.02 })
            let before = model.game.state.cuts
            phone.orientation = simd_quatf(angle: angle - 0.55, axis: SIMD3<Float>(0, 0, 1))
            try step(0.025)
            XCTAssertEqual(model.game.state.cuts, before + 1, "A phone rotation must cut the real game target")
            XCTAssertGreaterThan(model.game.state.score, 0)
            phone.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
    }

    func testPhonePairsOnceAndPlaysAcrossTennisRushDuelAndHome() throws {
        let rig = try Rig()
        defer { rig.close() }
        let model = rig.model
        let port = model.controllers.phoneHost.listeningPort
        let code = model.controllers.phoneHost.code
        let id = rig.phone.id, sessionID = rig.phone.sessionID
        XCTAssertFalse(model.running, "Phone-only games must not start the AirPod manager")
        XCTAssertFalse(model.calibrated)

        model.selectSport(.tennis)
        try rig.publishPhone()
        XCTAssertTrue(model.tennis.liveReady)
        model.tennis.start()
        XCTAssertEqual(model.players.activeRun?.game, .tennis)
        try rig.advance(until: { model.tennis.state.phase == .playing && model.tennis.state.elapsed > 0.2 })
        XCTAssertTrue(model.players.activeRun?.isGuest == true)
        let tennisID = model.tennis.runID

        try rig.startRush()
        XCTAssertEqual(model.tennis.state.phase, .menu)
        XCTAssertFalse(model.tennis.enabled)
        XCTAssertNotEqual(model.game.runID, tennisID)
        XCTAssertEqual(model.players.activeRun?.game, .neonRush)
        try rig.hitFirstRushBlock()
        XCTAssertFalse(model.players.showingSignIn)
        XCTAssertFalse(model.running)

        rig.feedAirPod = true
        try rig.step()
        model.showMultiplayer(true)
        try rig.step()
        try rig.pump("phone assigned to player two") { rig.phone.role == .player(2) }
        XCTAssertTrue(model.multiplayer.bothReady)
        XCTAssertNil(model.players.activeRun, "Leaving a solo run abandons its result context")
        XCTAssertEqual(model.controllers.snapshot(for: .two)?.controllerID, id)
        let airPodReference = model.controllers.snapshot(for: .airPod)?.sessionID
        model.controllers.assign(.phone, to: .one)
        try rig.step()
        try rig.pump("phone assigned to player one") { rig.phone.role == .player(1) }
        XCTAssertEqual(model.controllers.snapshot(for: .one)?.controllerID, id)
        XCTAssertEqual(model.controllers.device(for: .two), .airPod)
        XCTAssertEqual(model.controllers.snapshot(for: .airPod)?.sessionID, airPodReference)
        model.multiplayer.start()
        XCTAssertEqual(model.multiplayer.match.phase, .countdown)

        model.showMultiplayer(false) // Existing home/menu route before shell composition.
        try rig.publishPhone()
        try rig.pump("phone solo role restored") { rig.phone.role == .solo }
        XCTAssertFalse(model.showingMultiplayer)
        XCTAssertEqual(model.game.state.phase, .menu)
        XCTAssertEqual(model.controllers.phoneHost.listeningPort, port)
        XCTAssertEqual(model.controllers.phoneHost.code, code)
        XCTAssertEqual(model.controllers.snapshot(for: .phone)?.controllerID, id)
        XCTAssertEqual(model.controllers.snapshot(for: .phone)?.sessionID, sessionID)
        XCTAssertEqual(rig.phone.greetings, 1)
        XCTAssertEqual(rig.phone.recenterRequests, 0)
        XCTAssertTrue(model.controllers.phoneHost.connected)
        XCTAssertTrue(model.game.liveReady)
        XCTAssertTrue(model.players.pendingRuns.isEmpty)
    }

    func testUnusedAirPodStalenessAndStopNeverPausePhoneGames() throws {
        let rig = try Rig()
        defer { rig.close() }
        let model = rig.model
        for sport in AircadeSport.allCases {
            model.selectSport(sport)
            rig.feedAirPod = true
            try rig.step()
            rig.feedAirPod = false
            if sport == .tennis { model.tennis.start() }
            else { model.game.start(demo: false, seed: 42) }
            for _ in 0..<80 { try rig.step() }
            XCTAssertFalse(try XCTUnwrap(model.controllers.snapshot(for: .airPod)).isFresh(at: rig.time))
            XCTAssertEqual(model.controllers.soloDevice, .phone)
            if sport == .tennis {
                XCTAssertEqual(model.tennis.state.phase, .playing)
                XCTAssertFalse(model.tennis.recoveringInput)
            } else {
                XCTAssertEqual(model.game.state.phase, .playing)
                XCTAssertFalse(model.game.recoveringInput)
            }
            model.stop()
            try rig.step()
            if sport == .tennis { XCTAssertEqual(model.tennis.state.phase, .playing) }
            else { XCTAssertEqual(model.game.state.phase, .playing) }
            XCTAssertFalse(model.running)
        }
    }

    func testControllerAssignmentRequiresResumeAndCannotCreateASlash() throws {
        let rig = try Rig()
        defer { rig.close() }
        let model = rig.model
        rig.feedAirPod = true
        try rig.startRush()
        try rig.advance(until: { !model.game.state.targets.isEmpty })
        let target = try XCTUnwrap(model.game.state.targets.first)
        let angle = atan2(-target.x, target.y + 0.5)
        rig.phone.orientation = simd_quatf(angle: angle + 0.55, axis: SIMD3<Float>(0, 0, 1))
        try rig.advance(until: { model.game.state.elapsed >= target.arrival })
        let elapsed = model.game.state.elapsed, cuts = model.game.state.cuts
        model.controllers.selectSolo(.airPod)
        XCTAssertEqual(model.game.state.phase, .paused)
        rig.phone.orientation = simd_quatf(angle: angle - 0.55, axis: SIMD3<Float>(0, 0, 1))
        try rig.step()
        model.controllers.selectSolo(.phone)
        try rig.step()
        XCTAssertEqual(model.game.state.phase, .paused)
        XCTAssertEqual(model.game.state.elapsed, elapsed)
        XCTAssertEqual(model.game.state.cuts, cuts)
        model.game.resume()
        XCTAssertEqual(model.game.state.phase, .countdown)
        try rig.advance(until: { model.game.state.phase == .playing })
        try rig.step()
        XCTAssertEqual(model.game.state.cuts, cuts, "Changing controllers cannot bridge old/new poses into a hit")

        model.showMultiplayer(true)
        try rig.step()
        model.multiplayer.start()
        try rig.advance(until: { model.multiplayer.match.phase == .playing })
        model.controllers.assign(.phone, to: .one)
        XCTAssertEqual(model.multiplayer.match.phase, .paused)
        let health = model.multiplayer.match.health
        rig.phone.orientation = simd_quatf(angle: -1.3, axis: SIMD3<Float>(0, 0, 1))
        try rig.step()
        XCTAssertEqual(model.multiplayer.match.health, health)
        model.multiplayer.resume()
        XCTAssertEqual(model.multiplayer.match.phase, .countdown)
        XCTAssertEqual(rig.phone.recenterRequests, 0)
    }

    func testRealGuestPhoneRunSavesLocalBestWithoutProfileOrServer() throws {
        let rig = try Rig()
        defer { rig.close() }
        try rig.startRush()
        try rig.hitFirstRushBlock()
        try rig.advance(until: { rig.model.game.state.phase == .results })
        let game = rig.model.game
        XCTAssertGreaterThan(game.state.score, 0)
        XCTAssertFalse(game.isDemo)
        XCTAssertTrue(game.newRecord)
        XCTAssertEqual(rig.defaults.integer(forKey: "neonRush.best.Arcade"), game.state.score)
        XCTAssertTrue(rig.model.players.pendingRuns.isEmpty)
        XCTAssertNil(rig.model.players.activeRun)
        XCTAssertFalse(rig.model.players.showingSignIn)
    }

    func testMidrunSimulatedPhoneFrameDisqualifiesNonzeroScoreThenFreshRunCanRank() throws {
        let rig = try Rig()
        defer { rig.close() }
        let alice = BadgePlayer(id: "11111111-1111-1111-1111-111111111111", nickname: "Alice", isPublic: false)
        let bob = BadgePlayer(id: "22222222-2222-2222-2222-222222222222", nickname: "Bob", isPublic: true)
        rig.model.players.player = alice
        try rig.startRush()
        try rig.hitFirstRushBlock()
        rig.phone.simulated = true
        try rig.step()
        rig.phone.simulated = false
        try rig.step()
        XCTAssertTrue(rig.model.game.isDemo)
        XCTAssertTrue(rig.model.players.activeRun?.isSimulated == true)
        try rig.advance(until: { rig.model.game.state.phase == .results })
        XCTAssertGreaterThan(rig.model.game.state.score, 0)
        XCTAssertEqual(rig.defaults.integer(forKey: "neonRush.best.Arcade"), 0)
        XCTAssertFalse(rig.model.game.newRecord)
        XCTAssertTrue(rig.model.players.pendingRuns.isEmpty)

        rig.phone.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
        try rig.startRush()
        let realRun = try XCTUnwrap(rig.model.game.runID)
        try rig.hitFirstRushBlock()
        rig.model.players.player = bob
        try rig.advance(until: { rig.model.game.state.phase == .results })
        XCTAssertFalse(rig.model.game.isDemo)
        XCTAssertGreaterThan(rig.model.game.state.score, 0)
        XCTAssertEqual(rig.model.players.pendingRuns.count, 1)
        XCTAssertEqual(rig.model.players.pendingRuns.first?.id, realRun)
        XCTAssertEqual(rig.model.players.pendingRuns.first?.playerID, alice.id)
        XCTAssertEqual(rig.defaults.integer(forKey: "neonRush.best.Arcade"), rig.model.game.state.score)
    }
}
