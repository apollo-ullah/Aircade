import XCTest
import simd
@testable import Aircade

final class CalibrationIntegrationTests: XCTestCase {
    var model: MotionModel!
    var time = 100.0
    var suite: String!
    var logs: URL!
    let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    let left = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 0, 1))
    let forward = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(-1, 0, 0))

    override func setUp() {
        super.setUp()
        suite = "com.aircade.tests.\(UUID().uuidString)"
        logs = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        model = MotionModel(logDirectory: logs)
        model.useSimpleCalibration = false
        model.clock = { [unowned self] in self.time }
        model.gripDefaults = UserDefaults(suiteName: suite)!
        model.running = true // Inject packets; never start the physical Core Motion manager.
    }
    override func tearDown() {
        model.running = false
        model.gripDefaults.removePersistentDomain(forName: suite)
        model = nil
        try? FileManager.default.removeItem(at: logs)
        super.tearDown()
    }
    func feed(_ pose: simd_quatf, source: String = "Left", receipt: Double? = nil) {
        time += 0.03
        model.receive(q: pose, euler: .zero, rate: .zero, accel: .zero,
                      sensorTime: time, location: source, receivedAt: receipt ?? time)
    }
    func hold(_ pose: simd_quatf, source: String = "Left") {
        for _ in 0..<16 { feed(pose, source: source) }
    }
    func throughPreview() {
        feed(identity)
        model.beginGripCalibration()
        hold(identity); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 2)
        hold(left); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 3)
        hold(identity); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 4)
        hold(forward); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 5)
    }

    func testFullCalibrationDoesNotPersistUntilPreviewConfirmed() {
        throughPreview()
        XCTAssertNil(model.gripDefaults.array(forKey: "grip.Left"))
        XCTAssertFalse(model.hasGripCalibration)
        XCTAssertNotNil(model.calibrationPreview)
        model.captureGripPose() // Still tilted; cannot commit.
        XCTAssertEqual(model.calibrationStep, 5)
        hold(identity); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 0)
        XCTAssertTrue(model.calibrated)
        XCTAssertTrue(model.hasGripCalibration)
        XCTAssertNotNil(model.gripDefaults.array(forKey: "grip.Left"))
        XCTAssertNil(model.gripDefaults.array(forKey: "grip.Right"))
        hold(left)
        XCTAssertLessThan(model.saber.act(SIMD3<Float>(0, 1, 0)).x, -0.49)
    }

    func testCancelPreviewPreservesExistingSavedMapping() {
        let saved = [0.0, 0.0, 0.0, 1.0]
        model.gripDefaults.set(saved, forKey: "grip.Left")
        throughPreview()
        model.cancelGripCalibration()
        XCTAssertEqual(model.gripDefaults.array(forKey: "grip.Left") as? [Double], saved)
        XCTAssertTrue(model.hasGripCalibration)
        XCTAssertFalse(model.calibrated)
    }

    func testSourceSwitchCannotSilentlyLoadOrRecenterOtherEarbud() {
        model.gripDefaults.set([0.0, 0.0, 0.0, 1.0], forKey: "grip.Right")
        feed(identity)
        model.beginGripCalibration()
        hold(identity); model.captureGripPose()
        feed(left, source: "Right")
        XCTAssertEqual(model.source, "Left")
        XCTAssertEqual(model.incomingSource, "Right")
        XCTAssertTrue(model.sourceMismatch)
        XCTAssertFalse(model.calibrated)
        XCTAssertFalse(model.hasGripCalibration)
        XCTAssertFalse(model.calibrationPoseReady)
        XCTAssertEqual(model.calibrationStep, 2, "Keep the sheet visible with an interruption reason")
        XCTAssertFalse(model.game.inputReady)
        model.adoptIncomingSource()
        XCTAssertEqual(model.source, "Right")
        XCTAssertTrue(model.hasGripCalibration)
        XCTAssertFalse(model.calibrated, "Loading a mapping must not recenter an old sample")
        XCTAssertEqual(model.calibrationStep, 1)
        XCTAssertEqual(model.calibrationSource, "Right")
        XCTAssertNil(model.calibrationTiltDegrees)
        hold(identity, source: "Right")
        XCTAssertTrue(model.calibrationPoseReady)
    }

    func testReturnedOriginalSourceStillRequiresRestartAfterInterruption() {
        feed(identity); model.beginGripCalibration()
        hold(identity); model.captureGripPose()
        feed(left, source: "Right")
        hold(left)
        XCTAssertFalse(model.sourceMismatch)
        XCTAssertFalse(model.calibrationPoseReady)
        XCTAssertFalse(model.calibrated)
        model.beginGripCalibration()
        hold(identity)
        XCTAssertTrue(model.calibrationPoseReady)
        XCTAssertEqual(model.calibrationStep, 1)
    }

    func testUseSavedGripSelectsMeasuredMappingWithoutRecenteringTiltedPose() {
        model.gripDefaults.set([0.0, 0.0, 0.0, 1.0], forKey: "grip.Left")
        feed(identity)
        model.grip = 0
        model.beginGripCalibration()
        hold(left)
        model.useSavedGrip()
        XCTAssertEqual(model.grip, 4)
        XCTAssertFalse(model.calibrated)
        XCTAssertEqual(model.calibrationStep, 0)
        hold(identity); model.recenter()
        XCTAssertTrue(model.calibrated)
    }

    func testSourceSwitchCannotCountAsUninterruptedHardwareTrial() {
        feed(identity)
        model.beginTrial()
        XCTAssertTrue(model.testing)
        feed(left, source: "Right")
        XCTAssertFalse(model.testing)
        XCTAssertTrue(model.testMessage.contains("no pass recorded"))
    }

    func testSimpleModeCapturesSmallTiltsImmediatelyAndFinishesInThreeClicks() {
        model.useSimpleCalibration = true
        feed(identity); model.beginGripCalibration(); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 2)
        feed(simd_quatf(angle: 4 * .pi / 180, axis: SIMD3<Float>(0, 0, 1)))
        model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 3)
        feed(simd_quatf(angle: 6 * .pi / 180, axis: SIMD3<Float>(-1, 0, 0)))
        model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 0)
        XCTAssertTrue(model.calibrated)
        XCTAssertTrue(model.hasGripCalibration)
        XCTAssertNotNil(model.gripDefaults.array(forKey: "grip.Left"))
    }

    func testSimpleModeStillCannotMixEarbuds() {
        model.useSimpleCalibration = true
        feed(identity); model.beginGripCalibration(); model.captureGripPose()
        feed(left, source: "Right"); model.captureGripPose()
        XCTAssertEqual(model.calibrationStep, 1)
        XCTAssertNil(model.gripDefaults.array(forKey: "grip.Left"))
        XCTAssertFalse(model.calibrated)
    }

    func testQueuedOldDeliveryCannotBecomeFreshAtConsumption() {
        feed(identity)
        let count = model.samples
        time += 1
        feed(left, receipt: time - 0.4)
        XCTAssertEqual(model.samples, count)
        XCTAssertFalse(model.hasFreshMotion)
        model.beginGripCalibration()
        XCTAssertEqual(model.calibrationStep, 0)
    }
}
