import XCTest
import Network
import simd
import ControllerLink
@testable import MotionCore
@testable import Aircade

/// Sensor samples are synthetic; feedback, pairing, run callbacks, and resume
/// use the real app/session/transport paths. Collision physics is tested elsewhere.
private final class FeedbackPhone {
    let id = UUID(), session = UUID()
    let link: ControllerLink
    var run: UUID?
    var cues: [(UUID, ControllerFeedback)] = []
    var sequence: UInt64 = 0
    var welcomed = false
    var closeReason = ""
    init(port: NWEndpoint.Port, code: String) {
        link = ControllerLink(connection: NWConnection(host: "127.0.0.1", port: port, using: ControllerLink.parameters()))
        link.onReady = { [weak self] in
            guard let self else { return }
            self.link.send(.hello(code: code, controller: self.id, session: self.session))
        }
        link.onMessage = { [weak self] message in
            guard let self else { return }
            switch message {
            case .welcome: self.welcomed = true
            case .activeRun(let run): self.run = run
            case let .feedbackEvent(run, cue): self.cues.append((run, cue))
            case .poll(let request):
                self.sequence += 1
                self.link.send(.sample(request: request, frame: PlayerControllerFrame(
                    controllerID: self.id, sessionID: self.session, sequence: self.sequence,
                    source: "iPhone", orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), ready: true)))
            default: break
            }
        }
        link.onClose = { [weak self] reason in self?.closeReason = reason }
        link.start()
    }
    func close() { link.onReady = nil; link.onMessage = nil; link.cancel() }
}

final class SoloFeedbackRecoveryTests: XCTestCase {
    private final class Rig {
        let suite = "com.aircade.feedback-recovery.\(UUID().uuidString)"
        let model: MotionModel
        let defaults: UserDefaults
        let directory: URL
        var phone: FeedbackPhone!
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defaults = UserDefaults(suiteName: suite)!
            model = MotionModel(logDirectory: directory, scoreDefaults: defaults, tennisOpponent: AutomaticReboundOpponent())
            model.gripDefaults = defaults
            model.game.sound = false; model.game.renderingEnabled = false; model.tennis.sound = false
            model.startControllerSession()
            try pump("listener") {
                self.model.controllers.phoneHost.listeningPort != nil &&
                self.model.controllers.phoneHost.networkStatus == "Visible to nearby iPhones"
            }
            try connectPhone()
            model.controllers.selectSolo(.phone)
        }
        func close() {
            phone?.close(); model.game.leave(); model.tennis.leave()
            model.game.enabled = false; model.tennis.enabled = false
            model.shutdownControllerSession(); model.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        func pump(_ message: String, _ condition: @escaping () -> Bool) throws {
            if condition() { return }
            let ready = XCTestExpectation(description: message)
            var done = false
            let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] _ in
                guard !done else { return }
                self?.model.controllers.tick()
                if condition() { done = true; ready.fulfill() }
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate() }
            guard XCTWaiter.wait(for: [ready], timeout: 3) == .completed else {
                throw NSError(domain: "SoloFeedbackRecoveryTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out: \(message); host=\(model.controllers.phoneHost.status); close=\(phone?.closeReason ?? "")"])
            }
        }
        func connectPhone() throws {
            phone = FeedbackPhone(port: try XCTUnwrap(model.controllers.phoneHost.listeningPort), code: model.controllers.phoneHost.code)
            try pump("paired phone") { self.phone.welcomed && self.model.controllers.phoneHost.connected }
            try freshPhone()
        }
        func freshPhone() throws {
            let previous = model.controllers.snapshot(for: .phone)?.sequence ?? 0
            try pump("fresh phone input") { (self.model.controllers.snapshot(for: .phone)?.sequence ?? 0) > previous }
        }
        func start(_ sport: AircadeSport) throws {
            model.selectSport(sport, notify: false)
            try freshPhone()
            if sport == .tennis { model.tennis.start() } else { model.game.start(demo: false, seed: 42) }
            try pump("feedback run started") { self.phone.run != nil }
        }
        func resume(_ sport: AircadeSport) {
            if sport == .tennis { model.tennis.resume() } else { model.game.resume() }
        }
        func hit(_ sport: AircadeSport) {
            if sport == .tennis { model.tennis.onJudgment?(.playerReturn(points: 100)) }
            else {
                let target = RushTarget(id: 1, born: 0, travel: 2, window: 0.2, x: 0, y: 0, hazard: false, direction: .any)
                model.game.onJudgment?(RushJudgment(target: target, kind: .cut, points: 100))
            }
        }
        func runID(_ sport: AircadeSport) -> String? { sport == .tennis ? model.tennis.runID : model.game.runID }
        func assertPaused(_ sport: AircadeSport, file: StaticString = #filePath, line: UInt = #line) {
            if sport == .tennis { XCTAssertEqual(model.tennis.state.phase, .paused, file: file, line: line) }
            else { XCTAssertEqual(model.game.state.phase, .paused, file: file, line: line) }
        }
    }

    func testResumeRenewsSoloFeedbackRecipientWithoutChangingScoreIdentityOrProvenance() throws {
        let rig = try Rig(); defer { rig.close() }
        for sport in AircadeSport.allCases {
            rig.model.players.player = BadgePlayer(id: "11111111-1111-1111-1111-111111111111", nickname: "Original player", isPublic: false)
            try rig.start(sport)
            let originalFeedback = try XCTUnwrap(rig.phone.run)
            let scoreID = try XCTUnwrap(rig.runID(sport))
            rig.model.players.observeInput(simulated: true, runID: scoreID)
            let originalContext = try XCTUnwrap(rig.model.players.activeRun)
            let cueCount = rig.phone.cues.count
            rig.hit(sport)
            try rig.pump("first phone hit") { rig.phone.cues.count == cueCount + 1 }

            rig.model.controllers.selectSolo(.airPod)
            rig.assertPaused(sport)
            rig.model.players.player = BadgePlayer(id: "22222222-2222-2222-2222-222222222222", nickname: "Next player", isPublic: true)
            try rig.pump("old feedback ended on assignment") { rig.phone.run == nil }
            rig.hit(sport) // An effect from before explicit resume has no active recipient.
            rig.model.controllers.submitAirPod(orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                source: "Left AirPod", ready: true, sampleTime: ProcessInfo.processInfo.systemUptime)
            rig.resume(sport)
            try rig.pump("new AirPod feedback run") { rig.phone.run != nil && rig.phone.run != originalFeedback }
            let airPodFeedback = try XCTUnwrap(rig.phone.run)
            rig.hit(sport) // Assigned AirPod must not vibrate the still-connected phone.
            rig.model.controllers.selectSolo(.phone)
            rig.assertPaused(sport)
            try rig.pump("AirPod feedback ended") { rig.phone.run == nil }
            try rig.freshPhone()
            rig.resume(sport)
            try rig.pump("new phone feedback run") { rig.phone.run != nil && rig.phone.run != airPodFeedback }
            let resumedFeedback = try XCTUnwrap(rig.phone.run)
            XCTAssertNotEqual(resumedFeedback, originalFeedback)
            rig.model.controllers.sendFeedback(run: originalFeedback, to: .phone, cue: .damage)
            rig.model.controllers.sendFeedback(run: airPodFeedback, to: .phone, cue: .defeat)
            rig.hit(sport)
            try rig.pump("resumed phone hit") { rig.phone.cues.count >= cueCount + 2 }
            XCTAssertEqual(Array(rig.phone.cues.dropFirst(cueCount)).map(\.1), [.hit, .hit])
            XCTAssertEqual(rig.phone.cues.last?.0, resumedFeedback)
            XCTAssertEqual(rig.runID(sport), scoreID)
            XCTAssertEqual(rig.model.players.activeRun, originalContext, "Resume must preserve score ownership and simulation downgrade")
            rig.model.game.leave(); rig.model.tennis.leave()
            try rig.pump("feedback ended on leave") { rig.phone.run == nil }
        }
    }

    func testReconnectThenResumeRenewsConnectionEpochAndRejectsPreviousFeedback() throws {
        let rig = try Rig(); defer { rig.close() }
        for sport in AircadeSport.allCases {
            try rig.start(sport)
            let scoreID = try XCTUnwrap(rig.runID(sport))
            let originalContext = try XCTUnwrap(rig.model.players.activeRun)
            let oldFeedback = try XCTUnwrap(rig.phone.run)
            rig.phone.close()
            try rig.pump("disconnect") { !rig.model.controllers.phoneHost.connected }
            rig.assertPaused(sport)
            try rig.connectPhone()
            XCTAssertNil(rig.phone.run, "Reconnected device must stay feedback-inactive until resume")
            rig.resume(sport)
            try rig.pump("resumed connection feedback") { rig.phone.run != nil }
            let resumedFeedback = try XCTUnwrap(rig.phone.run)
            XCTAssertNotEqual(resumedFeedback, oldFeedback)
            rig.model.controllers.sendFeedback(run: oldFeedback, to: .phone, cue: .damage)
            rig.hit(sport)
            try rig.pump("hit on reconnected phone") { !rig.phone.cues.isEmpty }
            XCTAssertEqual(rig.phone.cues.map(\.1), [.hit])
            XCTAssertEqual(rig.phone.cues.first?.0, resumedFeedback)
            XCTAssertEqual(rig.runID(sport), scoreID)
            XCTAssertEqual(rig.model.players.activeRun, originalContext)
            rig.model.game.leave(); rig.model.tennis.leave()
            try rig.pump("feedback ended on leave") { rig.phone.run == nil }
        }
    }

    func testResumeCallbackOnlyRunsForActualReadyPausedTransition() {
        var now = 100.0
        let defaults = UserDefaults(suiteName: "com.aircade.resume-callback.\(UUID().uuidString)")!
        let scene = SaberScene()
        let rush = ArcadeGame(scene: scene, automaticTimer: false, clock: { now }, scoreDefaults: defaults)
        let tennis = TennisGame(scene: scene, opponent: AutomaticReboundOpponent(), automaticTimer: false, clock: { now }, scoreDefaults: defaults)
        tennis.enabled = true
        var callbacks: [String?] = []
        rush.onRunStarted = { _ in "rush" }; tennis.onRunStarted = { _ in "tennis" }
        rush.onRunResumed = { callbacks.append($0) }; tennis.onRunResumed = { callbacks.append($0) }
        let pose = SaberPose(position: .zero, orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)))
        rush.update(pose: pose, time: now, ready: true); tennis.update(pose: pose, time: now, ready: true)
        rush.resume(); tennis.resume()
        XCTAssertTrue(callbacks.isEmpty)
        rush.start(demo: true); tennis.start(demo: true)
        rush.pause(); tennis.pause()
        now += 0.3
        rush.resume(); tennis.resume()
        XCTAssertTrue(callbacks.isEmpty, "Stale input cannot renew feedback")
        rush.update(pose: pose, time: now, ready: true); tennis.update(pose: pose, time: now, ready: true)
        rush.resume(); tennis.resume()
        rush.resume(); tennis.resume()
        XCTAssertEqual(callbacks, ["rush", "tennis"])
        XCTAssertEqual(rush.runID, "rush"); XCTAssertEqual(tennis.runID, "tennis")
    }
}
