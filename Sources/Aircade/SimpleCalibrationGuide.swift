import SwiftUI

struct SimpleCalibrationSheet: View {
    @ObservedObject var motion: MotionModel
    var body: some View {
        SimpleCalibrationPanel(
            step: motion.calibrationStep, source: motion.calibrationSource,
            isLive: motion.hasFreshMotion,
            message: motion.calibrationError.isEmpty ? motion.calibrationMessage : motion.calibrationError,
            sourceWarning: motion.sourceMismatch ? motion.controllerLabel : nil,
            switchTitle: motion.canAdoptIncomingSource ? "Calibrate \(motion.incomingSource) AirPod instead" : nil,
            capture: { motion.captureGripPose() }, cancel: { motion.cancelGripCalibration() },
            restart: { motion.beginGripCalibration() }, switchSource: { motion.adoptIncomingSource() }
        )
    }
}

struct SimpleCalibrationPanel: View {
    let step: Int
    let source: String
    let isLive: Bool
    let message: String
    var sourceWarning: String? = nil
    var switchTitle: String? = nil
    var previewTime: Double? = nil
    var capture: () -> Void = {}
    var cancel: () -> Void = {}
    var restart: () -> Void = {}
    var switchSource: () -> Void = {}
    @State private var animationStart = Date()
    private let cyan = Color(red: 0.35, green: 0.93, blue: 0.91)
    private var title: String {
        step == 1 ? "Hold upright" : step == 2 ? "Lean toward your left" : "Tilt toward your Mac"
    }
    private var instruction: String {
        step == 1 ? "Hold the \(source) AirPod in your playing grip. Click to save your starting angle." :
        step == 2 ? "Keep holding the \(source) AirPod. Lean your imaginary handle toward your left and click. A small tilt is fine." :
        "Keep holding the \(source) AirPod. Return upright, then tip toward the screen. Click to finish."
    }
    private var buttonTitle: String {
        step == 1 ? "Save \(source) upright pose" : step == 2 ? "Save \(source) AirPod tilt" : "Finish \(source) calibration"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AIRCADE / SIMPLE CALIBRATION")
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(cyan)
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.plain)
            }
            HStack {
                ForEach(1...3, id: \.self) { index in
                    Label(index == 1 ? "Upright" : index == 2 ? "Lean left" : "Lean forward",
                          systemImage: index < step ? "checkmark.circle.fill" : "\(index).circle")
                        .foregroundStyle(index <= step ? cyan : .secondary)
                    if index < 3 { Spacer() }
                }
            }.font(.callout.weight(.semibold))
            EarbudIdentityCard(source: source, purpose: "CALIBRATING THIS EARBUD", isLive: isLive)
            if let sourceWarning {
                VStack(alignment: .leading, spacing: 7) {
                    Text(sourceWarning).font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    if let switchTitle { Button(switchTitle, action: switchSource) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(instruction).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.025))
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            GripAnimation(step: step, elapsed: previewTime ?? context.date.timeIntervalSince(animationStart))
                        }
                        Text("EXAMPLE MOTION").font(.caption2.monospaced()).foregroundStyle(cyan).padding(12)
                    }.frame(height: 210)
                    Text("Move your wrist or forearm—either is fine. Each click captures immediately; there is no angle target or hold timer.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(isLive ? message : sourceWarning ?? "Waiting for fresh sensor readings. Keep the selected earbud connected and out of its case.")
                .font(.callout).foregroundStyle(isLive ? cyan : .orange)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Start over", action: restart).disabled(!isLive)
                Spacer()
                Button(buttonTitle, action: capture).buttonStyle(.borderedProminent).tint(cyan)
                    .foregroundStyle(.black).controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    .disabled(!isLive)
            }
        }.padding(26).frame(width: 650, height: 700)
            .background(Color(red: 0.035, green: 0.045, blue: 0.07)).preferredColorScheme(.dark)
            .onChange(of: step) { animationStart = Date() }
    }
}
