import SwiftUI
import simd

struct CalibrationSheet: View {
    @ObservedObject var motion: MotionModel
    var body: some View {
        if motion.useSimpleCalibration {
            SimpleCalibrationSheet(motion: motion)
        } else {
        // Newer five-step guide is intentionally bypassed for the simple build.
        CalibrationGuidePanel(
            step: motion.calibrationStep, status: motion.calibrationMessage,
            isLive: motion.hasFreshMotion && !motion.simulated,
            activeSource: motion.source, tiltDegrees: motion.calibrationTiltDegrees,
            poseHint: motion.calibrationPoseHint, poseReady: motion.calibrationPoseReady,
            errorMessage: motion.calibrationError, feedbackID: motion.calibrationAttempt,
            rotationSpeed: motion.speed, liveOrientation: motion.calibrationPreview,
            sourceWarning: motion.sourceMismatch ? motion.controllerLabel : nil,
            adoptSourceTitle: motion.canAdoptIncomingSource ? "Use \(motion.incomingSource) instead & restart" : nil,
            capture: { motion.captureGripPose() }, cancel: { motion.cancelGripCalibration() },
            restart: { motion.beginGripCalibration() },
            useSaved: motion.hasGripCalibration && motion.hasFreshMotion ? { motion.useSavedGrip() } : nil,
            adoptSource: { motion.adoptIncomingSource() }
        )
        }
    }
}

struct CalibrationGuidePanel: View {
    let step: Int
    let status: String
    let isLive: Bool
    var activeSource = ""
    var tiltDegrees: Float? = nil
    var poseHint = ""
    var poseReady = false
    var errorMessage = ""
    var feedbackID = 0
    var previewTime: Double? = nil
    var rotationSpeed = 0.0
    var liveOrientation: simd_quatf? = nil
    var sourceWarning: String? = nil
    var adoptSourceTitle: String? = nil
    var capture: () -> Void = {}
    var cancel: () -> Void = {}
    var restart: (() -> Void)? = nil
    var useSaved: (() -> Void)? = nil
    var adoptSource: () -> Void = {}
    @State private var animationStart = Date()
    private let cyan = WiiTheme.accentDeep
    private var labels: [String] { ["Start", "Left", "Return", "Forward", "Test"] }
    private var illustrationStep: Int { step == 2 ? 2 : step == 4 ? 3 : 1 }
    private var title: String {
        switch step {
        case 1: return "Check your earbud. Hold upright."
        case 2: return "Lean your handle to YOUR LEFT"
        case 3: return "Return to your starting angle"
        case 4: return "Lean your handle toward the screen"
        default: return "Try your blade before saving"
        }
    }
    private var instruction: String {
        switch step {
        case 1: return "Hold the \(activeSource) AirPod. Move only that earbud: the live speed below should react. Then hold your imaginary handle upright and still."
        case 2: return "Keep the same grip and tip the top left, roughly 30°. Moving your wrist, forearm or elbow is fine. Then hold still."
        case 3: return "Bring the earbud back to the angle you saved in step 1. The live angle below should return near 0°. Keep the same grip."
        case 4: return "From upright, tip the top away from your chest, toward your Mac, roughly 30°. Then hold still."
        default: return "Tilt left, right and toward your Mac. These two live views should follow. If they feel right, return upright and save."
        }
    }
    private var buttonTitle: String {
        switch step {
        case 1: return "Save upright pose"
        case 2: return "Save left tilt"
        case 3: return "I'm back upright — continue"
        case 4: return "Save forward tilt & test"
        default: return "Looks right — save grip"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AIRCADE / GRIP SETUP").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(cyan)
                Spacer()
                if let useSaved { Button("Use saved grip", action: useSaved).buttonStyle(.plain).foregroundStyle(cyan) }
                Button("Cancel", action: cancel).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 9) {
                ForEach(1...5, id: \.self) { index in
                    HStack(spacing: 5) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index).circle\(index == step ? ".fill" : "")")
                        Text(labels[index - 1])
                    }.font(.system(size: 12, weight: index == step ? .semibold : .regular))
                        .foregroundStyle(index <= step ? cyan : .secondary)
                    if index < 5 { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Label("SELECTED: \(activeSource.uppercased()) AIRPOD", systemImage: "airpodspro")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                if let sourceWarning {
                    Text(sourceWarning).font(.callout)
                    Text("macOS chooses which earbud sends motion. Aircade will not switch your controller silently.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if let adoptSourceTitle { Button(adoptSourceTitle, action: adoptSource).buttonStyle(.bordered) }
                }
            }.foregroundStyle(sourceWarning == nil ? cyan : .orange)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background((sourceWarning == nil ? cyan : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(.system(size: 27, weight: .bold, design: .default))
                        Text(instruction).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if step == 5 {
                        CalibrationBladePreview(orientation: liveOrientation).frame(height: 240)
                    } else {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.84, green: 0.93, blue: 0.98))
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                                GripAnimation(step: illustrationStep, elapsed: previewTime ?? context.date.timeIntervalSince(animationStart))
                            }
                            Text("EXAMPLE • NOT LIVE  /  " + (step == 4 ? "SIDE VIEW" : "YOUR VIEW"))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(cyan.opacity(0.9)).padding(16)
                        }.frame(height: 240)
                        HStack {
                            Text(step == 3 ? "Match your saved starting angle, not the exact drawing." : "Imagine a handle in your hand. The dot marks its top.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Replay") { animationStart = Date() }.font(.caption)
                        }
                    }
                    Label("Your forearm can move. Keep the AirPod fixed in your fingers: its angle controls the blade. Sliding your hand alone needs the optional webcam.", systemImage: "hand.draw")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }.frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if isLive, let tiltDegrees {
                        Text(String(format: "LIVE  %.0f° since saved start", tiltDegrees)).font(.headline.monospacedDigit())
                    } else if isLive {
                        Text(String(format: "LIVE  %.0f°/s rotation speed", rotationSpeed * 180 / .pi)).font(.headline.monospacedDigit())
                    } else { Text("Live motion unavailable").font(.headline) }
                    Spacer()
                    Text(isLive && poseReady ? "Ready" : "Not ready").font(.caption.weight(.semibold))
                }
                Text(poseHint.isEmpty ? status : poseHint).font(.callout).fixedSize(horizontal: false, vertical: true)
                if !errorMessage.isEmpty && !poseReady && errorMessage != poseHint {
                    Text("Not saved: " + errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                if step > 1 {
                    Text("This measures the earbud's orientation change, not your forearm's angle. Poses save only after a steady hold.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isLive && poseReady ? cyan : .orange)
                .background((isLive && poseReady ? cyan : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                if let restart { Button("Start over", action: restart).disabled(!isLive) }
                Spacer()
                Button(buttonTitle, action: capture)
                    .buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
                    .controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    .disabled(!isLive || !poseReady)
            }
        }.padding(26).frame(width: 700, height: 740)
            .background(WiiTheme.stageMid).preferredColorScheme(.light)
            .onChange(of: step) { animationStart = Date() }
    }
}

/// Two projections of the same unsmoothed, proposed grip mapping. No instructional
/// animation is mixed into the live feedback, and no gain is applied to the angle.
struct CalibrationBladePreview: View {
    let orientation: simd_quatf?
    private let cyan = WiiTheme.accentDeep
    var body: some View {
        Canvas { context, size in
            let direction = orientation?.act(SIMD3<Float>(0, 1, 0)) ?? SIMD3<Float>(0, 1, 0)
            for index in 0..<2 {
                let center = CGPoint(x: size.width * (index == 0 ? 0.25 : 0.75), y: size.height - 45)
                let length: CGFloat = 125
                let tip = CGPoint(x: center.x + CGFloat(index == 0 ? direction.x : -direction.z) * length,
                                  y: center.y - CGFloat(direction.y) * length)
                var neutral = Path(); neutral.move(to: center); neutral.addLine(to: CGPoint(x: center.x, y: center.y - length))
                context.stroke(neutral, with: .color(WiiTheme.ink.opacity(0.2)), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                var blade = Path(); blade.move(to: center); blade.addLine(to: tip)
                context.stroke(blade, with: .color(cyan.opacity(0.2)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                context.stroke(blade, with: .color(orientation == nil ? .gray : cyan), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.white))
                context.draw(Text(index == 0 ? "YOUR VIEW • LEFT ↔ RIGHT" : "SIDE VIEW • SCREEN →")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(cyan),
                             at: CGPoint(x: center.x, y: 26))
            }
            context.draw(Text(orientation == nil ? "WAITING FOR LIVE MOTION" : "LIVE PREVIEW • SAME MAPPING AS THE GAME")
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.gray),
                         at: CGPoint(x: size.width / 2, y: size.height - 15))
        }.background(Color(red: 0.84, green: 0.93, blue: 0.98), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Drawn from the user's point of view for left tilt, and explicitly from the side for forward tilt.
/// This is an instruction animation, not a live reconstruction of the user's hand.
struct GripAnimation: View {
    let step: Int
    let elapsed: Double
    private let cyan = WiiTheme.accentDeep

    private var phase: (amount: Double, text: String) {
        if step == 1 { return (0, "HOLD UPRIGHT") }
        let t = elapsed.truncatingRemainder(dividingBy: 5.6)
        if t < 1 { return (0, "START UPRIGHT") }
        if t < 2.2 {
            let f = (t - 1) / 1.2
            return ((1 - cos(f * .pi)) / 2, step == 2 ? "TILT TO YOUR LEFT" : "TILT TOWARD THE SCREEN")
        }
        if t < 4.5 { return (1, "HOLD THIS POSE · THEN SAVE") }
        let f = (t - 4.5) / 1.1
        return ((1 + cos(f * .pi)) / 2, "REPLAYING…")
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: 1, y: size.height / 286)
            let size = CGSize(width: size.width, height: 286)
            let origin = CGPoint(x: size.width * (step == 3 ? 0.47 : 0.53), y: 210)
            let length: CGFloat = 120
            let sign: Double = step == 2 ? -1 : 1
            let angle = step == 1 ? 0 : sign * .pi / 4 * phase.amount
            let goalAngle = step == 1 ? 0 : sign * .pi / 4
            let target = CGPoint(x: origin.x + sin(goalAngle) * length, y: origin.y - cos(goalAngle) * length)
            let tip = CGPoint(x: origin.x + sin(angle) * length, y: origin.y - cos(angle) * length)

            // Neutral axis and fixed wrist pivot make rotation visibly distinct from translation.
            var neutral = Path()
            neutral.move(to: origin); neutral.addLine(to: CGPoint(x: origin.x, y: origin.y - length - 20))
            context.stroke(neutral, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            if step != 1 {
                var goalContext = context
                goalContext.translateBy(x: origin.x, y: origin.y)
                goalContext.rotate(by: .radians(goalAngle))
                let outline = Path(roundedRect: CGRect(x: -12, y: -length, width: 24, height: length + 12), cornerRadius: 6)
                goalContext.stroke(outline, with: .color(cyan.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                context.draw(Text("HOLD HERE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(cyan),
                             at: CGPoint(x: target.x + (step == 2 ? -24 : 22), y: target.y - 23))
                drawArrow(context: &context, from: CGPoint(x: origin.x, y: origin.y - length - 14),
                          to: CGPoint(x: target.x, y: target.y - 14))
            }

            // Arm and hand remain anchored while the handle tips about the wrist.
            let arm = Path(roundedRect: CGRect(x: origin.x - 15, y: origin.y + 15, width: 30, height: 42), cornerRadius: 6)
            context.fill(arm, with: .color(.white.opacity(0.13)))
            var gripContext = context
            gripContext.translateBy(x: origin.x, y: origin.y)
            gripContext.rotate(by: .radians(angle))
            let handle = Path(roundedRect: CGRect(x: -10, y: -length, width: 20, height: length + 8), cornerRadius: 10)
            gripContext.fill(handle, with: .color(cyan.opacity(0.20)))
            gripContext.stroke(handle, with: .color(cyan), lineWidth: 2)
            // Small earbud symbol inside the imaginary grip, with the top marked separately.
            gripContext.fill(Path(ellipseIn: CGRect(x: -7, y: -68, width: 20, height: 14)), with: .color(.white))
            gripContext.fill(Path(roundedRect: CGRect(x: 1, y: -60, width: 6, height: 23), cornerRadius: 3), with: .color(.white))
            let palm = Path(roundedRect: CGRect(x: -25, y: -26, width: 48, height: 43), cornerRadius: 7)
            gripContext.fill(palm, with: .color(Color(red: 0.26, green: 0.33, blue: 0.40)))
            gripContext.stroke(palm, with: .color(.white.opacity(0.55)), lineWidth: 1.5)
            for y in [-21, -11, -1] {
                let finger = Path(roundedRect: CGRect(x: -10, y: y, width: 33, height: 8), cornerRadius: 4)
                gripContext.fill(finger, with: .color(Color(red: 0.34, green: 0.43, blue: 0.51)))
            }
            gripContext.fill(Path(ellipseIn: CGRect(x: -28, y: -26, width: 19, height: 31)), with: .color(Color(red: 0.4, green: 0.49, blue: 0.57)))
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)), with: .color(cyan))
            context.fill(Path(ellipseIn: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6)), with: .color(.white))

            if step == 3 {
                let screen = CGRect(x: size.width - 111, y: 99, width: 61, height: 47)
                context.stroke(Path(roundedRect: screen, cornerRadius: 5), with: .color(.white.opacity(0.65)), lineWidth: 2)
                var base = Path(); base.move(to: CGPoint(x: screen.minX - 8, y: screen.maxY + 5)); base.addLine(to: CGPoint(x: screen.maxX + 8, y: screen.maxY + 5))
                context.stroke(base, with: .color(.white.opacity(0.65)), lineWidth: 3)
                context.draw(Text("YOUR MAC").font(.system(size: 10, weight: .bold)).foregroundColor(.gray), at: CGPoint(x: screen.midX, y: screen.maxY + 24))
                let head = Path(ellipseIn: CGRect(x: 57, y: 91, width: 27, height: 32))
                context.fill(head, with: .color(.white.opacity(0.3)))
                context.fill(Path(roundedRect: CGRect(x: 45, y: 127, width: 48, height: 58), cornerRadius: 18), with: .color(.white.opacity(0.18)))
                context.draw(Text("YOU").font(.system(size: 10, weight: .bold)).foregroundColor(.gray), at: CGPoint(x: 70, y: 205))
            } else {
                context.draw(Text(step == 2 ? "← YOUR LEFT" : "TOP ↑").font(.system(size: 12, weight: .semibold)).foregroundColor(cyan),
                             at: CGPoint(x: step == 2 ? 98 : origin.x, y: step == 2 ? 159 : 65))
            }
            context.draw(Text(phase.text).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(WiiTheme.ink),
                         at: CGPoint(x: size.width / 2, y: 271))
        }
        .accessibilityLabel(step == 1 ? "Hold your imaginary handle upright in a fixed grip." : step == 2 ? "From your point of view, the top leans 45 degrees left with the AirPod fixed in your grip. Your forearm can move too." : "Side view: you are on the left and your Mac is on the right. From upright, the top leans 45 degrees toward your Mac.")
    }

    private func drawArrow(context: inout GraphicsContext, from a: CGPoint, to b: CGPoint) {
        var path = Path()
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 20)
        path.move(to: a); path.addQuadCurve(to: b, control: control)
        context.stroke(path, with: .color(cyan.opacity(0.65)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let angle = atan2(b.y - control.y, b.x - control.x)
        var arrow = Path()
        arrow.move(to: CGPoint(x: b.x - 9 * cos(angle - 0.5), y: b.y - 9 * sin(angle - 0.5)))
        arrow.addLine(to: b)
        arrow.addLine(to: CGPoint(x: b.x - 9 * cos(angle + 0.5), y: b.y - 9 * sin(angle + 0.5)))
        context.stroke(arrow, with: .color(cyan), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
