import XCTest
import MotionCore
import simd
@testable import Aircade

final class SensorEvidenceTests: XCTestCase {
    private func frame(_ time: Double, source: String = "Left", reported: String? = nil,
                       simulated: Bool = false, fresh: Bool = true, sensorTime: Double? = nil,
                       angle: Float = 0.3) -> SensorEvidenceFrame {
        SensorEvidenceFrame(capturedAt: time, receivedAt: time - 0.02, sensorTime: sensorTime ?? time,
            source: source, reportedSource: reported ?? source, simulated: simulated, fresh: fresh,
            calibrated: true, quaternion: simd_quatf(angle: angle, axis: SIMD3(0, 0, 1)).vector,
            reference: SIMD4(0, 0, 0, 1), basis: simd_quatf(angle: 0.4, axis: SIMD3(1, 0, 0)).vector,
            racket: simd_quatf(angle: angle * 0.9, axis: SIMD3(0, 0, 1)).vector,
            eulerDegrees: SIMD3(0, 0, Double(angle) * 180 / .pi),
            angularVelocity: SIMD3(0, 0, 2.5), userAcceleration: SIMD3(0.1, 0.2, 0.3),
            frequency: 50, smoothingSeconds: 0.045, calibrationMode: "Three captured poses",
            grip: "Measured grip axes", cameraEnabled: false)
    }

    func testOnlyFreshCalibratedHardwareCanStartEvidenceRecording() {
        let store = SensorEvidenceStore()
        XCTAssertFalse(store.begin(with: .preview()))
        XCTAssertFalse(store.begin(with: frame(1, fresh: false)))
        XCTAssertFalse(store.begin(with: frame(1, reported: "Right")))
        XCTAssertFalse(store.begin(with: frame(1, source: "Unknown")))
        XCTAssertNil(store.trace)
        XCTAssertTrue(store.begin(with: frame(1)))
        XCTAssertTrue(store.recording)
        store.cancel()
        XCTAssertFalse(store.recording)
        XCTAssertNil(store.trace)
    }

    func testRecordingKeepsMappingAndOutputWithoutReprocessingOrDuplicateSamples() throws {
        let store = SensorEvidenceStore()
        let first = frame(10)
        XCTAssertTrue(store.begin(with: first))
        store.accept(frame(10.01, sensorTime: 10))
        let later = frame(10.02, angle: 1.2)
        store.accept(later)
        store.event("TENNIS PLAYER RETURN +50 · Left AirPod", at: 10.02)
        store.publish(frame(28.1))
        let trace = try XCTUnwrap(store.trace)
        XCTAssertFalse(store.recording)
        XCTAssertTrue(trace.isHardwareRecording)
        XCTAssertEqual(trace.frames, [first, later])
        XCTAssertEqual(trace.events.count, 1)
        let decoded = try JSONDecoder().decode(SensorEvidenceTrace.self, from: JSONEncoder().encode(trace))
        XCTAssertEqual(decoded.frames[1].reference, later.reference)
        XCTAssertEqual(decoded.frames[1].basis, later.basis)
        XCTAssertEqual(decoded.frames[1].racket, later.racket)
        XCTAssertEqual(decoded.frames[1].smoothingSeconds, later.smoothingSeconds)
        XCTAssertEqual(decoded.frame(at: 0), first)
        XCTAssertEqual(decoded.frame(at: 100), later)
    }

    func testSourceChangeStopsRecordingWithoutMixingEarbuds() throws {
        let store = SensorEvidenceStore()
        XCTAssertTrue(store.begin(with: frame(1)))
        store.accept(frame(1.02))
        store.accept(frame(1.04, source: "Right"))
        let trace = try XCTUnwrap(store.trace)
        XCTAssertFalse(store.recording)
        XCTAssertEqual(trace.frames.count, 2)
        XCTAssertTrue(trace.frames.allSatisfy { $0.source == "Left" })
        XCTAssertTrue(trace.completion.contains("source changed"))
        XCTAssertTrue(trace.isHardwareRecording)
    }

    func testRecorderAndEventMemoryRemainBoundedAndCancelledAttemptKeepsPreviousTrace() throws {
        let store = SensorEvidenceStore()
        XCTAssertTrue(store.begin(with: frame(0)))
        for index in 1...2000 {
            let time = Double(index) * 0.001
            store.event("Sample \(index)", at: time)
            store.accept(frame(time))
        }
        let trace = try XCTUnwrap(store.trace)
        XCTAssertEqual(trace.frames.count, SensorEvidenceStore.maximumFrames)
        XCTAssertEqual(trace.events.count, 200)
        XCTAssertTrue(store.begin(with: frame(4)))
        store.cancel()
        XCTAssertEqual(store.trace?.id, trace.id)
        store.publish(frame(5))
        XCTAssertLessThanOrEqual(store.recentEvents.count, 8)
    }

    func testSensorSnapshotAndReplayCannotReplaceLivePoseOrSavedGrip() throws {
        let name = "sensor-evidence-test-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let model = MotionModel(logDirectory: directory, scoreDefaults: defaults, tennisOpponent: AutomaticReboundOpponent())
        var time = 100.0
        model.clock = { time }; model.gripDefaults = defaults
        model.running = true // No Core Motion manager or physical device is started.
        model.game.renderingEnabled = false; model.game.sound = false
        defer {
            model.stop(); defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        model.receive(q: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)), euler: .zero, rate: .zero,
                      accel: .zero, sensorTime: time, location: "Left", receivedAt: time)
        let savedGrip = defaults.dictionaryRepresentation()
        let pose = model.saber.vector
        let first = model.sensorEvidenceSnapshot
        let trace = SensorEvidenceTrace(id: UUID(), recordedAt: Date(), origin: "Recorded Core Motion output",
            completion: "Test only", frames: [frame(0), frame(1, angle: 1.2)], events: [])
        _ = trace.frame(at: 1)
        XCTAssertEqual(model.saber.vector, pose)
        XCTAssertEqual(model.source, "Left")
        XCTAssertEqual(model.sensorEvidenceSnapshot, first)
        XCTAssertTrue(NSDictionary(dictionary: defaults.dictionaryRepresentation()).isEqual(to: savedGrip))
        time += 0.3; model.tick()
        XCTAssertFalse(model.sensorEvidence.snapshot?.fresh ?? true)
        XCTAssertFalse(model.sensorEvidence.snapshot?.hardwareReady ?? true)
    }

    func testPreviewFixtureIsExplicitlySimulated() {
        let fixture = SensorEvidenceStore.preview
        XCTAssertEqual(fixture.snapshot?.simulated, true)
        XCTAssertFalse(fixture.snapshot?.hardwareReady ?? true)
        XCTAssertNil(fixture.trace)
        XCTAssertFalse(fixture.recording)
    }

    func testRecordedPreviewCannotMasqueradeAsHardwareEvidence() throws {
        let fixture = SensorEvidenceStore.recordedPreview
        let trace = try XCTUnwrap(fixture.trace)
        XCTAssertFalse(trace.isHardwareRecording)
        XCTAssertTrue(trace.frames.allSatisfy(\.simulated))
        XCTAssertEqual(trace.duration, 18, accuracy: 0.001)
        XCTAssertEqual(trace.frame(at: 5.9)?.capturedAt, 5.9)
        XCTAssertNil(fixture.exportPath)
        XCTAssertFalse(fixture.recording)
        XCTAssertFalse(fixture.begin(with: try XCTUnwrap(trace.frames.first)))
    }

    func testImportedRecordingLoadsWithDistinctReconstructedProvenance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = SensorEvidenceTrace(id: UUID(), recordedAt: Date(),
            origin: "Imported Core Motion CSV · reconstructed preview", completion: "Input only; example grip mapping.",
            frames: [frame(0), frame(0.02)], events: [])
        XCTAssertTrue(trace.isReprocessedRecording)
        XCTAssertFalse(trace.isHardwareRecording)
        try JSONEncoder().encode(trace).write(to: directory.appendingPathComponent("sensor-evidence-latest.json"))
        let store = SensorEvidenceStore(directory: directory)
        XCTAssertEqual(store.trace?.id, trace.id)
        XCTAssertTrue(store.status.contains("reconstructed"))

        let mixedSources = SensorEvidenceTrace(id: UUID(), recordedAt: Date(), origin: trace.origin,
            completion: "Invalid mixed-source import", frames: [frame(0), frame(0.02, source: "Right")], events: [])
        XCTAssertFalse(mixedSources.isReprocessedRecording)
        try JSONEncoder().encode(mixedSources).write(to: directory.appendingPathComponent("sensor-evidence-latest.json"))
        XCTAssertNil(SensorEvidenceStore(directory: directory).trace)
    }

    func testBundledRealInputExampleDecodesAndIsAlwaysLabelledReconstructed() throws {
        let example = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Judging/SensorExample.json")
        let decoded = try JSONDecoder().decode(SensorEvidenceTrace.self, from: Data(contentsOf: example))
        XCTAssertTrue(decoded.isReprocessedRecording)
        XCTAssertFalse(decoded.isHardwareRecording)
        XCTAssertTrue((15...20).contains(decoded.duration))
        XCTAssertTrue(decoded.frames.allSatisfy { !$0.simulated && !$0.calibrated })
        XCTAssertTrue(decoded.events.isEmpty)
        XCTAssertGreaterThan(decoded.recordedAt.timeIntervalSince1970, 1_600_000_000)
        let store = SensorEvidenceStore(bundledExampleURL: example)
        XCTAssertEqual(store.trace?.id, decoded.id)
        XCTAssertTrue(store.status.contains("reconstructed"))
        XCTAssertFalse(store.recording)
        XCTAssertNil(store.snapshot)
    }
}
