import SwiftUI
import Combine
import simd

struct SensorEvidenceView: View {
    @ObservedObject private var evidence: SensorEvidenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var recorded = false
    @State private var replayTime = 0.0
    @State private var replaying = false
    @State private var replayTick = Date()
    @State private var clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let beginRecording: () -> Void
    private let cancelRecording: () -> Void

    init(motion: MotionModel) {
        self.init(evidence: motion.sensorEvidence,
                  beginRecording: { motion.beginSensorEvidenceRecording() },
                  cancelRecording: { motion.cancelSensorEvidenceRecording() })
    }

    init(evidence: SensorEvidenceStore, initiallyRecorded: Bool = false, initialReplayTime: Double = 0,
         beginRecording: @escaping () -> Void = {}, cancelRecording: @escaping () -> Void = {}) {
        self.evidence = evidence; self.beginRecording = beginRecording; self.cancelRecording = cancelRecording
        _recorded = State(initialValue: initiallyRecorded && evidence.trace != nil)
        _replayTime = State(initialValue: max(0, min(initialReplayTime, evidence.trace?.duration ?? 0)))
    }

    /// Stable screenshot fixture, conspicuously simulated and unable to control a game.
    static var previewFixture: SensorEvidenceView { SensorEvidenceView(evidence: .preview) }
    static var recordedPreviewFixture: SensorEvidenceView {
        SensorEvidenceView(evidence: .recordedPreview, initiallyRecorded: true, initialReplayTime: 5.9)
    }

    private var frame: SensorEvidenceFrame? {
        recorded ? evidence.trace?.frame(at: replayTime) : evidence.snapshot
    }
    private var reconstructed: Bool { recorded && evidence.trace?.isReprocessedRecording == true }
    private var modeLabel: String {
        if recorded {
            if reconstructed { return "RECORDED INPUT · RECONSTRUCTED RACKET PREVIEW" }
            return evidence.trace?.isHardwareRecording == true
                ? "RECORDED AIRPOD TRACE · DISPLAY ONLY"
                : "SIMULATED REPLAY · NO HARDWARE EVIDENCE"
        }
        if frame?.simulated == true { return "SIMULATED PREVIEW · NO HARDWARE EVIDENCE" }
        return frame?.fresh == true ? "LIVE AIRPOD INPUT" : "WAITING FOR FRESH AIRPOD INPUT"
    }
    private var accent: Color { recorded || frame?.simulated == true ? .orange : WiiTheme.accentDeep }
    private var displayEvents: [SensorEvidenceEvent] {
        guard recorded, let trace = evidence.trace, let first = trace.frames.first else { return evidence.recentEvents }
        return Array(trace.events.filter { $0.capturedAt <= first.capturedAt + replayTime }.suffix(3).reversed())
    }
    private var graph: [Double] {
        guard recorded, let trace = evidence.trace, let first = trace.frames.first else { return evidence.speedHistory }
        return trace.frames.filter { $0.capturedAt <= first.capturedAt + replayTime }.suffix(100).map(\.angularSpeed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("From AirPod to racket").font(WiiTheme.display(30))
                    Text("An angle becomes a motion controller.").foregroundStyle(WiiTheme.inkSoft)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Label(modeLabel, systemImage: recorded ? "play.rectangle" : "waveform.path")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(accent)
                Spacer()
                Picker("Evidence source", selection: $recorded) {
                    Text("Live input").tag(false)
                    Text("Recorded trace").tag(true)
                }.pickerStyle(.segmented).frame(width: 260).disabled(evidence.trace == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        inputCard
                        mappingCard
                        resultCard
                    }
                    if recorded { playback } else { recording }
                    DisclosureGroup("Technical details") { technicalDetails.padding(.top, 8) }
                        .font(WiiTheme.body(13, .semibold))
                    Text("The game stays paused while this screen is open. Close, check your live controller, then resume.")
                        .font(.caption).foregroundStyle(WiiTheme.inkSoft)
                }
            }
        }
        .padding(24).frame(width: 1000, height: 680)
        .foregroundStyle(WiiTheme.ink).background(WiiTheme.stage).tint(WiiTheme.accentDeep)
        .onChange(of: recorded) { replaying = false; replayTime = 0; replayTick = Date() }
        .onChange(of: evidence.trace?.id) { replaying = false; replayTime = 0 }
        .onReceive(clock) { now in
            defer { replayTick = now }
            guard recorded, replaying, let trace = evidence.trace else { return }
            replayTime = min(trace.duration, replayTime + min(0.3, max(0, now.timeIntervalSince(replayTick))))
            if replayTime >= trace.duration { replaying = false }
        }
    }

    private var inputCard: some View {
        stage("1", title: "Read the angle", symbol: "airpodspro") {
            Text(frame.map { $0.simulated ? "Simulated signal" : "\($0.source) AirPod" } ?? "No sensor yet").font(WiiTheme.display(20))
            Text("Core Motion reports orientation and rotation speed.")
                .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.2f", frame?.angularSpeed ?? 0)).font(WiiTheme.display(32)).monospacedDigit()
                Text("rad/s").font(.caption)
            }
            Sparkline(values: graph).stroke(accent, lineWidth: 2).frame(height: 54)
                .accessibilityLabel("Angular speed history, zero to ten radians per second")
            HStack {
                detail("UPDATE RATE", frame.map { String(format: "%.1f Hz", $0.frequency) } ?? "—")
                Spacer()
                detail("SAMPLE AGE", reconstructed ? "Unavailable" : frame?.sampleAge.map { String(format: "%.0f ms", $0 * 1000) } ?? "—")
            }
            Text(reconstructed ? "Rate derived from the recorded samples; receipt age was not captured."
                 : recorded ? "Age and rate shown as recorded." : "Sample age is time since app receipt, not end-to-end latency.")
                .font(.caption2).foregroundStyle(WiiTheme.inkSoft)
        }
    }

    private var mappingCard: some View {
        stage("2", title: "Map your grip", symbol: "hand.point.up.left") {
            Text(reconstructed ? "Example grip mapping." : "Your upright is zero.").font(WiiTheme.display(20))
            Text(reconstructed
                 ? "These are real input angles. The first sample and example axes reconstruct this preview."
                 : "Captured left and forward tilts teach the app how you hold the earbud.")
                .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            VStack(alignment: .leading, spacing: 14) {
                mappingRow("1", reconstructed ? "Use the first angle as zero" : "Save the starting angle")
                mappingRow("2", reconstructed ? "Apply example grip axes" : "Rotate into your grip axes")
                mappingRow("3", reconstructed ? "Preview relative orientation" : "Smooth small changes")
            }.padding(.vertical, 10)
            Text(frame?.grip ?? "Awaiting a controller").font(.caption.weight(.semibold))
            Text(reconstructed ? "Original grip, smoothing and racket output were not recorded in the CSV."
                 : frame?.calibrated == true ? "Mapping captured with this frame" : "Recenter or finish calibration before playing")
                .font(.caption2).foregroundStyle(frame?.calibrated == true ? WiiTheme.inkSoft : .orange)
        }
    }

    private var resultCard: some View {
        stage("3", title: "Move the racket", symbol: "figure.tennis") {
            SensorRacketPreview(orientation: frame?.racket, fresh: recorded || frame?.fresh == true, accent: accent)
                .frame(height: 150)
            Text(reconstructed ? "Reconstructed angle · no scoring" : "Angle preview · no scoring here").font(.caption.weight(.semibold))
            Text("In the game, a moving racket must intersect the ball. A fast swing alone is not a hit.")
                .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            if let event = displayEvents.first {
                Text("Last app event: \(event.message)").font(.system(size: 10, design: .monospaced)).lineLimit(2)
            } else {
                Text("No contact event recorded yet.").font(.caption2).foregroundStyle(WiiTheme.inkSoft)
            }
        }
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture the real signal").font(WiiTheme.display(16))
                    Text(evidence.status).font(.caption).foregroundStyle(WiiTheme.inkSoft)
                }
                Spacer()
                if evidence.recording {
                    Text(String(format: "%.1f / 18 s", evidence.progress)).monospacedDigit().font(.caption)
                    Button("Cancel recording", action: cancelRecording)
                } else {
                    Button("Record 18 seconds", action: beginRecording)
                        .buttonStyle(.borderedProminent).disabled(evidence.snapshot?.hardwareReady != true)
                }
            }
            if evidence.recording { ProgressView(value: evidence.progress, total: SensorEvidenceStore.recordingDuration) }
            Text("Hold still → tilt left and right → swing. The trace saves input, grip mapping, output and available game events.")
                .font(.caption2).foregroundStyle(WiiTheme.inkSoft)
            if evidence.recording {
                Text("Recording continues after closing this screen. Resume the game to include real contact events.")
                    .font(.caption2).foregroundStyle(WiiTheme.accentDeep)
            }
        }.padding(16).wiiPanel()
    }

    @ViewBuilder private var playback: some View {
        if let trace = evidence.trace {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(trace.isHardwareRecording || trace.isReprocessedRecording
                         ? "Recorded \(trace.recordedAt.formatted(date: .abbreviated, time: .shortened)) · \(trace.source) AirPod"
                         : "Simulated replay fixture · no real AirPod recording")
                        .font(WiiTheme.body(13, .semibold))
                    Spacer()
                    Button(replaying ? "Pause replay" : "Play replay") {
                        if replayTime >= trace.duration { replayTime = 0 }
                        replayTick = Date(); replaying.toggle()
                    }
                }
                HStack {
                    Slider(value: $replayTime, in: 0...max(0.01, trace.duration))
                    Text(String(format: "%.1f / %.1f s", replayTime, trace.duration)).font(.caption.monospacedDigit()).frame(width: 100)
                }
                Text("\(trace.completion) This recording cannot change the controller, calibration or score.")
                    .font(.caption2).foregroundStyle(WiiTheme.inkSoft)
            }.padding(16).wiiPanel()
        }
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These are fused Core Motion readings, not raw chip registers. User acceleration is shown for inspection; we do not integrate it into hand position.")
            if reconstructed {
                Text("Imported CSV: sensor input is recorded; neutral reference, grip axes and racket output are reconstructed. This is not the original calibrated gameplay or evidence of contact.")
            }
            if let frame {
                Text("Yaw / pitch / roll: \(vector(frame.eulerDegrees)) °    Rotation: \(vector(frame.angularVelocity)) rad/s")
                Text("User acceleration: \(vector(frame.userAcceleration)) g")
                Text("Input q: \(quaternion(frame.quaternion))    Reference q: \(quaternion(frame.reference))")
                Text("Grip basis q: \(quaternion(frame.basis))    Output q: \(quaternion(frame.racket))")
                Text(String(format: "Smoothing time constant: %.0f ms · %@", frame.smoothingSeconds * 1000, frame.calibrationMode))
                Text(frame.cameraEnabled ? "Camera enabled: it supplies screen-plane hand position separately." : "Camera off: the handle has a fixed pivot. Tennis moves the character automatically.")
                if frame.source != frame.reportedSource {
                    Text("Selected: \(frame.source) · macOS reports: \(frame.reportedSource). Check the controller before resuming.").foregroundStyle(.orange)
                }
            }
            Text("macOS selects one streaming earbud. The trace contains accepted app readings, not every hardware callback.")
            if let path = evidence.exportPath { Text("Trace file: \(path)").textSelection(.enabled) }
        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(WiiTheme.inkSoft)
    }

    private func stage<Content: View>(_ number: String, title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(number).font(WiiTheme.display(14)).frame(width: 27, height: 27)
                    .foregroundStyle(.white).background(accent, in: Circle())
                Text(title).font(WiiTheme.display(17))
                Spacer(minLength: 0)
                Image(systemName: symbol).foregroundStyle(accent)
            }
            Divider()
            content()
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading).wiiPanel()
    }

    private func mappingRow(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.caption.bold()).foregroundStyle(accent)
            Text(title).font(WiiTheme.body(13, .medium))
        }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(WiiTheme.inkSoft)
            Text(value).font(WiiTheme.body(15, .semibold)).monospacedDigit()
        }
    }
    private func vector(_ value: SIMD3<Double>) -> String { String(format: "%.2f, %.2f, %.2f", value.x, value.y, value.z) }
    private func quaternion(_ value: SIMD4<Float>?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f, %.2f, %.2f, %.2f", value.x, value.y, value.z, value.w)
    }
}

private struct SensorRacketPreview: View {
    let orientation: SIMD4<Float>?
    let fresh: Bool
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width * 0.5, y: size.height * 0.78)
            var guide = Path(); guide.move(to: CGPoint(x: pivot.x, y: 12)); guide.addLine(to: pivot)
            context.stroke(guide, with: .color(WiiTheme.hairline), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            guard let orientation else {
                context.draw(Text("Waiting for motion").font(.caption), at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let axis = simd_quatf(vector: orientation).act(SIMD3<Float>(0, 1, 0))
            let dx = CGFloat(axis.x + axis.z * 0.3)
            let dy = CGFloat(axis.y - axis.z * 0.2)
            let length = size.height * 0.53
            let head = CGPoint(x: pivot.x + dx * length, y: pivot.y - dy * length)
            var shaft = Path(); shaft.move(to: pivot); shaft.addLine(to: head)
            let color = fresh ? accent : Color.gray
            context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            var ring = context
            ring.translateBy(x: head.x, y: head.y)
            ring.rotate(by: .radians(Double(atan2(dx, dy))))
            ring.stroke(Path(ellipseIn: CGRect(x: -18, y: -27, width: 36, height: 54)), with: .color(color), lineWidth: 4)
            for x in stride(from: -9, through: 9, by: 9) {
                var string = Path(); string.move(to: CGPoint(x: x, y: -20)); string.addLine(to: CGPoint(x: x, y: 20))
                ring.stroke(string, with: .color(color.opacity(0.35)), lineWidth: 1)
            }
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - 6, y: pivot.y - 6, width: 12, height: 12)), with: .color(WiiTheme.ink))
        }.accessibilityLabel("Racket angle derived from the captured grip mapping")
    }
}
