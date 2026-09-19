import XCTest
import simd
@testable import Aircade

/// Exercise the real receive -> orientation -> scene/game path with missing
/// packets. A continuously updated scripted SaberPose cannot catch this bug.
final class InputRecoveryIntegrationTests: XCTestCase {
    private var model: MotionModel!
    private var time = 100.0
    private var suite = ""
    private var logs: URL!
    private var pose = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))

    override func setUp() {
        super.setUp()
        suite = "com.aircade.recovery-tests.\(UUID().uuidString)"
        logs = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = MotionModel(logDirectory: logs)
        model.clock = { [unowned self] in self.time }
        model.gripDefaults = UserDefaults(suiteName: suite)!
        model.running = true // Never open Core Motion or connect physical AirPods.
        model.game.sound = false; model.game.renderingEnabled = false
        feed()
        model.game.start(demo: true, seed: 42)
    }
    override func tearDown() {
        model.stop()
        model.gripDefaults.removePersistentDomain(forName: suite)
        model = nil
        try? FileManager.default.removeItem(at: logs)
        super.tearDown()
    }
    private func feed(source: String = "Right") {
        model.receive(q: pose, euler: .zero, rate: .zero, accel: .zero,
                      sensorTime: time, location: source, receivedAt: time)
    }
    private func swingUntilHit() {
        for _ in 0..<400 {
            time += 0.03
            pose = simd_quatf(angle: Float(sin((time - 100) * 2.4)), axis: SIMD3<Float>(0, 0, 1))
            feed(); model.game.tick()
            if model.game.state.cuts > 0 { return }
        }
        XCTFail("The test must produce a real geometric hit before dropping packets")
    }

    func testRecordedPostHitGapAndLongerBriefGapsRecoverWithoutRecalibration() {
        swingUntilHit()
        for gap in [0.280104375, 0.65, 0.32] { // First value is the user's recorded receipt gap.
            let start = time
            let cuts = model.game.state.cuts
            let lives = model.game.state.lives
            time = start + 0.26
            model.game.tick(); model.tick()
            XCTAssertFalse(model.hasFreshMotion, "Do not relabel stale input as fresh")
            XCTAssertTrue(model.game.recoveringInput)
            let heldTime = model.game.state.elapsed
            time = start + gap - 0.001
            model.game.tick(); model.tick()
            XCTAssertEqual(model.game.state.elapsed, heldTime)
            time = start + gap
            feed(); model.game.tick(); model.tick()
            XCTAssertTrue(model.calibrated, "A short same-earbud gap must keep the neutral reference")
            XCTAssertTrue(model.hasFreshMotion)
            XCTAssertFalse(model.game.recoveringInput)
            XCTAssertEqual(model.game.state.phase, .playing)
            XCTAssertEqual(model.game.state.elapsed, heldTime)
            XCTAssertEqual(model.game.state.cuts, cuts)
            XCTAssertEqual(model.game.state.lives, lives)
            time += 0.03; feed(); model.game.tick()
            XCTAssertGreaterThan(model.game.state.elapsed, heldTime)
        }
        XCTAssertEqual(model.game.transientInputGaps, 3)
    }

    func testSustainedLossStillPausesAndRequiresRecenterOnReturn() {
        swingUntilHit()
        let elapsed = model.game.state.elapsed
        time += 1.05; model.game.tick(); model.tick()
        XCTAssertEqual(model.game.state.phase, .paused)
        XCTAssertEqual(model.game.state.elapsed, elapsed)
        XCTAssertTrue(model.game.pauseReason.contains("1 second"))
        feed(); model.game.tick()
        XCTAssertFalse(model.calibrated)
        XCTAssertEqual(model.game.state.phase, .paused)
        model.recenter()
        XCTAssertTrue(model.calibrated)
        XCTAssertEqual(model.game.state.phase, .paused, "Recenter must not silently resume an explicit pause")
    }

    func testSourceSwitchDuringRecoveryCannotAutoResumeOrKeepOldMappingActive() {
        swingUntilHit()
        time += 0.27; model.game.tick()
        XCTAssertTrue(model.game.recoveringInput)
        time += 0.02; feed(source: "Left"); model.game.tick()
        XCTAssertTrue(model.sourceMismatch)
        XCTAssertFalse(model.calibrated)
        XCTAssertFalse(model.game.recoveringInput)
        XCTAssertEqual(model.game.state.phase, .paused)
        XCTAssertEqual(model.source, "Right")
    }
}
