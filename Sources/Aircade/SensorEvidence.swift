import Foundation
import Combine
import simd

/// Value-only evidence. Reading or replaying a frame cannot drive a controller.
struct SensorEvidenceFrame: Codable, Equatable {
    let capturedAt: Double
    let receivedAt: Double?
    let sensorTime: Double?
    let source: String
    let reportedSource: String
    let simulated: Bool
    let fresh: Bool
    let calibrated: Bool
    let quaternion: SIMD4<Float>?
    let reference: SIMD4<Float>?
    let basis: SIMD4<Float>
    let racket: SIMD4<Float>
    let eulerDegrees: SIMD3<Double>
    let angularVelocity: SIMD3<Double>
    let userAcceleration: SIMD3<Double>
    let frequency: Double
    let smoothingSeconds: Double
    let calibrationMode: String
    let grip: String
    let cameraEnabled: Bool

    var angularSpeed: Double { simd_length(angularVelocity) }
    var sampleAge: Double? { receivedAt.map { max(0, capturedAt - $0) } }
    var hardwareReady: Bool {
        !simulated && fresh && calibrated && source == reportedSource &&
        (source == "Left" || source == "Right") && quaternion != nil
    }

    /// Screenshot-only fixture. Never inserted into MotionModel or saved as hardware evidence.
    static func preview(at time: Double = 2.4) -> Self {
        let angle = Float(sin(time * 1.6) * 0.65)
        let q = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1)).vector
        return Self(capturedAt: time, receivedAt: time - 0.02, sensorTime: time,
                    source: "Simulated", reportedSource: "Simulated", simulated: true,
                    fresh: true, calibrated: true, quaternion: q,
                    reference: SIMD4(0, 0, 0, 1), basis: SIMD4(0, 0, 0, 1), racket: q,
                    eulerDegrees: SIMD3(0, 0, Double(angle) * 180 / .pi),
                    angularVelocity: SIMD3(0, 0, 1.04 * cos(time * 1.6)), userAcceleration: .zero,
                    frequency: 50, smoothingSeconds: 0.045, calibrationMode: "Synthetic preview",
                    grip: "Example mapping", cameraEnabled: false)
    }
}

struct SensorEvidenceEvent: Codable, Equatable {
    let capturedAt: Double
    let message: String
}

struct SensorEvidenceTrace: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let origin: String
    let completion: String
    let frames: [SensorEvidenceFrame]
    let events: [SensorEvidenceEvent]
    var duration: Double { max(0, (frames.last?.capturedAt ?? 0) - (frames.first?.capturedAt ?? 0)) }
    var source: String { frames.first?.source ?? "Unknown" }
    var isHardwareRecording: Bool {
        origin == "Recorded Core Motion output" && hasValidRecordedInput
    }
    var isReprocessedRecording: Bool {
        origin == "Imported Core Motion CSV · reconstructed preview" && hasValidRecordedInput
    }
    private var hasValidRecordedInput: Bool {
        guard !frames.isEmpty, frames.count <= 1200, source == "Left" || source == "Right" else { return false }
        var previousTime = -Double.infinity
        for frame in frames {
            guard !frame.simulated, frame.source == source, frame.reportedSource == source,
                  frame.capturedAt.isFinite, frame.capturedAt >= previousTime,
                  let q = frame.quaternion, q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite,
                  simd_length_squared(q) > 0.5, simd_length_squared(q) < 1.5,
                  frame.racket.x.isFinite, frame.racket.y.isFinite, frame.racket.z.isFinite, frame.racket.w.isFinite,
                  frame.angularSpeed.isFinite else { return false }
            previousTime = frame.capturedAt
        }
        return true
    }
    func frame(at seconds: Double) -> SensorEvidenceFrame? {
        guard let first = frames.first else { return nil }
        let time = first.capturedAt + max(0, seconds)
        return frames.last(where: { $0.capturedAt <= time }) ?? first
    }
}

/// Updated by MotionModel's existing 10 Hz health tick. No timer or motion manager.
final class SensorEvidenceStore: ObservableObject {
    static let recordingDuration = 18.0
    static let maximumFrames = 1200
    @Published private(set) var snapshot: SensorEvidenceFrame?
    @Published private(set) var recentEvents: [SensorEvidenceEvent] = []
    @Published private(set) var speedHistory: [Double] = []
    @Published private(set) var trace: SensorEvidenceTrace?
    @Published private(set) var recording = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Record a real AirPod trace to replay it here."
    @Published private(set) var exportPath: String?
    private var recordingStart: Double?
    private var recordingDate = Date()
    private var recordingSource = ""
    private var frames: [SensorEvidenceFrame] = []
    private var capturedEvents: [SensorEvidenceEvent] = []
    private var pendingEvents: [SensorEvidenceEvent] = []
    private var lastHistoryReceipt: Double?
    private let directory: URL?
    private let persistenceQueue = DispatchQueue(label: "Aircade.SensorEvidenceSave", qos: .utility)

    init(directory: URL? = nil,
         bundledExampleURL: URL? = Bundle.main.url(forResource: "SensorExample", withExtension: "json")) {
        self.directory = directory
        // A fresh user recording always takes precedence over the bundled example.
        for url in [directory?.appendingPathComponent("sensor-evidence-latest.json"), bundledExampleURL].compactMap({ $0 }) {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 3_000_000, let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(SensorEvidenceTrace.self, from: data),
                  saved.isHardwareRecording || saved.isReprocessedRecording else { continue }
            trace = saved; exportPath = url.path
            status = saved.isReprocessedRecording
                ? "Imported AirPod readings ready. The racket mapping is reconstructed, not the original recorded output."
                : "Saved AirPod trace ready. Playback never controls the game."
            break
        }
    }

    @discardableResult
    func begin(with frame: SensorEvidenceFrame) -> Bool {
        guard !recording, frame.hardwareReady else {
            status = "Connect and recenter a live AirPod before recording."
            return false
        }
        recordingStart = frame.capturedAt; recordingDate = Date(); recordingSource = frame.source
        frames = [frame]; capturedEvents = []; progress = 0; recording = true
        status = "Recording 18 seconds: hold still, tilt left/right, then swing."
        return true
    }

    func cancel() {
        guard recording else { return }
        recording = false; recordingStart = nil; frames = []; capturedEvents = []; progress = 0
        status = "Recording cancelled. Your previous trace is unchanged."
    }

    func accept(_ frame: SensorEvidenceFrame) {
        guard recording, let start = recordingStart else { return }
        guard !frame.simulated, frame.source == recordingSource, frame.source == frame.reportedSource else {
            finish("Interrupted: controller source changed."); return
        }
        guard frame.capturedAt - start <= Self.recordingDuration else { finish("18-second recording complete."); return }
        guard frames.last?.sensorTime != frame.sensorTime else { return }
        if frames.count < Self.maximumFrames { frames.append(frame) }
        if frames.count >= Self.maximumFrames { finish("Recording reached its sample limit.") }
    }

    func event(_ message: String, at time: Double) {
        let event = SensorEvidenceEvent(capturedAt: time, message: message)
        pendingEvents.append(event)
        if pendingEvents.count > 8 { pendingEvents.removeFirst(pendingEvents.count - 8) }
        if recording, capturedEvents.count < 200 { capturedEvents.append(event) }
    }

    func publish(_ frame: SensorEvidenceFrame) {
        snapshot = frame
        if let receipt = frame.receivedAt, receipt != lastHistoryReceipt {
            lastHistoryReceipt = receipt
            speedHistory.append(frame.angularSpeed)
            if speedHistory.count > 100 { speedHistory.removeFirst(speedHistory.count - 100) }
        }
        if !pendingEvents.isEmpty {
            recentEvents = Array((Array(pendingEvents.reversed()) + recentEvents).prefix(8))
            pendingEvents.removeAll(keepingCapacity: true)
        }
        if recording, let start = recordingStart {
            progress = min(Self.recordingDuration, max(0, frame.capturedAt - start))
            if frame.simulated || frame.source != recordingSource || frame.source != frame.reportedSource {
                finish("Interrupted: controller source changed.")
            } else if frame.sampleAge.map({ $0 >= 1 }) ?? true {
                finish("Interrupted: motion stopped. Recorded gaps remain visible.")
            } else if progress >= Self.recordingDuration { finish("18-second recording complete.") }
        }
    }

    func interrupted(_ reason: String) { if recording { finish("Interrupted: \(reason)") } }

    private func finish(_ reason: String) {
        guard recording else { return }
        recording = false; recordingStart = nil
        guard frames.count >= 2 else {
            status = "Not enough live samples. Previous trace unchanged."; frames = []; capturedEvents = []; return
        }
        let result = SensorEvidenceTrace(id: UUID(), recordedAt: recordingDate,
            origin: "Recorded Core Motion output", completion: reason, frames: frames, events: capturedEvents)
        trace = result; status = reason; frames = []; capturedEvents = []
        guard let directory else { return }
        let url = directory.appendingPathComponent("sensor-evidence-latest.json")
        persistenceQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(result).write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    guard self?.trace?.id == result.id else { return }
                    self?.exportPath = url.path
                }
            } catch {
                DispatchQueue.main.async {
                    guard self?.trace?.id == result.id else { return }
                    self?.status = "Trace ready in memory; could not save: \(error.localizedDescription)"
                }
            }
        }
    }

    static var preview: SensorEvidenceStore {
        let value = SensorEvidenceStore(bundledExampleURL: nil)
        for index in 0..<60 { value.publish(.preview(at: Double(index) / 10)) }
        return value
    }

    /// Exercises replay UI without manufacturing or persisting hardware evidence.
    static var recordedPreview: SensorEvidenceStore {
        let value = preview
        value.trace = SensorEvidenceTrace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000039")!,
            recordedAt: Date(timeIntervalSince1970: 1_789_884_000),
            origin: "Simulated UI fixture", completion: "Simulated 18-second example; hardware not verified.",
            frames: (0...180).map { .preview(at: Double($0) / 10) },
            events: [SensorEvidenceEvent(capturedAt: 3, message: "SIMULATED swing example · no contact or score")])
        value.status = "Simulated preview only. Record a real AirPod trace before judging."
        return value
    }
}
