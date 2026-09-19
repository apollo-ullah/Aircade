import SwiftUI

struct CalibrationSheet: View {
    @ObservedObject var motion: MotionModel
    var body: some View {
        CalibrationGuidePanel(
            step: motion.calibrationStep,
            status: motion.sampleAge < 0.25 ? motion.calibrationMessage : "Waiting for fresh AirPod motion…",
            isLive: motion.running && !motion.simulated && motion.sampleAge < 0.25,
            capture: { motion.captureGripPose() },
            cancel: { motion.cancelGripCalibration() }
        )
    }
}

struct CalibrationGuidePanel: View {
    let step: Int
    let status: String
    let isLive: Bool
    var previewTime: Double? = nil
    var capture: () -> Void = {}
    var cancel: () -> Void = {}
    @State private var animationStart = Date()
    private let cyan = Color(red: 0.35, green: 0.93, blue: 0.91)
    private var title: String {
        step == 1 ? "Hold your hand upright" : step == 2 ? "Tip the top toward YOUR LEFT" : "Tip the top toward your screen"
    }
    private var instruction: String {
        step == 1 ? "Pinch the AirPod comfortably. Keep that same pinch for all three poses." :
        step == 2 ? "Keep your wrist in place. Lean the top left, like the animation, then hold it there." :
        "First return upright. Then lean the top away from your chest, toward your Mac, and hold."
    }
    private var buttonTitle: String {
        step == 1 ? "I'm upright — save pose" : step == 2 ? "I'm tilted left — save pose" : "I'm tilted toward the screen — finish"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AIRCADE / GRIP SETUP").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(cyan)
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { index in
                    HStack(spacing: 7) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index).circle\(index == step ? ".fill" : "")")
                        Text(index == 1 ? "Upright" : index == 2 ? "Left tilt" : "Toward screen")
                    }.font(.system(size: 12, weight: index == step ? .semibold : .regular))
                        .foregroundStyle(index <= step ? cyan : .secondary)
                    if index < 3 { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(instruction).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 88, alignment: .topLeading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.035, green: 0.065, blue: 0.10))
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    GripAnimation(step: step, elapsed: previewTime ?? context.date.timeIntervalSince(animationStart))
                }
                Text(step == 3 ? "SIDE VIEW · YOU → YOUR MAC" : "YOUR VIEW · AS IF LOOKING AT YOUR OWN HAND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(cyan.opacity(0.9)).padding(16)
            }.frame(height: 286)

            HStack {
                Label(step == 1 ? "The dot marks the top of your imaginary handle." : "Dashed outline = the pose to hold when you press save.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Replay") { animationStart = Date() }.font(.caption)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.draw").foregroundStyle(cyan)
                Text("Rotate your wrist. Don't slide your whole hand sideways, and don't turn the AirPod inside your fingers.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text(status).font(.caption).foregroundStyle(isLive ? Color.secondary : Color.orange)
                .frame(minHeight: 28, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Move → hold still → save\nYou control when the pose is captured.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(buttonTitle, action: capture)
                    .buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
                    .controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    .disabled(!isLive)
            }
        }
        .padding(26)
        .frame(width: 700)
        .background(Color(red: 0.035, green: 0.045, blue: 0.07))
        .preferredColorScheme(.dark)
        .onChange(of: step) { animationStart = Date() }
    }
}

/// Drawn from the user's point of view for left tilt, and explicitly from the side for forward tilt.
/// This is an instruction animation, not a live reconstruction of the user's hand.
struct GripAnimation: View {
    let step: Int
    let elapsed: Double
    private let cyan = Color(red: 0.35, green: 0.93, blue: 0.91)

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
                let outline = Path(roundedRect: CGRect(x: -12, y: -length, width: 24, height: length + 12), cornerRadius: 12)
                goalContext.stroke(outline, with: .color(cyan.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                context.draw(Text("HOLD HERE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(cyan),
                             at: CGPoint(x: target.x + (step == 2 ? -24 : 22), y: target.y - 23))
                drawArrow(context: &context, from: CGPoint(x: origin.x, y: origin.y - length - 14),
                          to: CGPoint(x: target.x, y: target.y - 14))
            }

            // Arm and hand remain anchored while the handle tips about the wrist.
            let arm = Path(roundedRect: CGRect(x: origin.x - 15, y: origin.y + 15, width: 30, height: 42), cornerRadius: 12)
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
            let palm = Path(roundedRect: CGRect(x: -25, y: -26, width: 48, height: 43), cornerRadius: 16)
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
            context.draw(Text(phase.text).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.8)),
                         at: CGPoint(x: size.width / 2, y: 271))
        }
        .accessibilityLabel(step == 1 ? "Hold upright, with your wrist still." : step == 2 ? "From your point of view, the top leans 45 degrees left while the wrist stays in place." : "Side view: you are on the left and your Mac is on the right. From upright, the top leans 45 degrees toward your Mac.")
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
