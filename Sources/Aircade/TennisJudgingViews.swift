import SwiftUI
import AppKit

/// Uses the existing controller session; this card never starts a second sensor stream.
struct TennisHandoffCard: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var controllers: ControllerSession
    let ready: Bool
    let openSetup: () -> Void

    private var isPhone: Bool { controllers.soloDevice == .phone }
    private var canRecenter: Bool {
        if !isPhone { return motion.hasFreshMotion && motion.calibrationStep == 0 }
        guard let sample = controllers.snapshot(for: .phone) else { return false }
        return sample.age(at: controllers.clock()) < 0.25
    }
    private var identity: String {
        if isPhone { return "iPhone" }
        return motion.controllerName
    }
    private var gripStatus: String {
        if motion.activeInputSimulated { return "Simulated input · use a real controller for judging" }
        if !isPhone && motion.sourceMismatch { return motion.controllerLabel }
        if !ready { return controllers.readiness(for: controllers.soloDevice) }
        if isPhone { return "Fresh motion · centered" }
        return motion.hasGripCalibration ? "Fresh motion · saved grip · centered" : "Fresh motion · preset grip · centered"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 13) {
                GripIllustration(isPhone: isPhone, source: motion.source)
                    .frame(width: 82, height: 90)
                VStack(alignment: .leading, spacing: 5) {
                    Label(identity, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(WiiTheme.display(17)).foregroundStyle(ready ? GameIdentity.tennis.accent : .orange)
                    Text(isPhone ? "Portrait. Screen toward you. Top edge up." : "Use the marked earbud and the grip you calibrated.")
                        .font(WiiTheme.body(12, .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(isPhone ? "Hold upright, recenter, then swing." : "Keep it fixed in your fingers. Hold upright, then recenter.")
                        .font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Text(gripStatus).font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                MotionButton("Recenter") { controllers.recenter(controllers.soloDevice) }
                    .buttonStyle(WiiButtonStyle()).disabled(!canRecenter)
                MotionButton(action: openSetup) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(WiiButtonStyle()).accessibilityLabel("Controller setup")
            }
        }
        .padding(15).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WiiTheme.hairline, lineWidth: 1))
    }
}

/// An illustrative reminder, not a photograph or evidence of a calibrated pose.
private struct GripIllustration: View {
    let isPhone: Bool
    let source: String
    private var marker: String { source == "Left" ? "L" : source == "Right" ? "R" : "?" }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(GameIdentity.tennis.accent.opacity(0.09))
                if isPhone {
                    Image(systemName: "iphone").font(.system(size: 42, weight: .regular))
                        .foregroundStyle(GameIdentity.tennis.accent)
                } else {
                    // Stem and earbud with a finger/thumb pinch. The mapping comes from
                    // the user's calibration, not the orientation of this illustration.
                    Capsule().fill(.white).frame(width: 15, height: 41).offset(x: -1, y: 8)
                    Ellipse().fill(.white).frame(width: 34, height: 22).offset(x: -6, y: -14)
                    Ellipse().fill(GameIdentity.tennis.accent.opacity(0.65)).frame(width: 10, height: 12).offset(x: -16, y: -14)
                    Capsule().fill(Color(red: 0.88, green: 0.71, blue: 0.54)).frame(width: 32, height: 13).rotationEffect(.degrees(-20)).offset(x: -16, y: 16)
                    Capsule().fill(Color(red: 0.94, green: 0.79, blue: 0.63)).frame(width: 29, height: 13).rotationEffect(.degrees(15)).offset(x: 14, y: 22)
                    Text(marker).font(WiiTheme.display(12)).foregroundStyle(GameIdentity.tennis.accent).offset(x: 24, y: -21)
                }
            }.frame(height: 70)
            Text("ILLUSTRATION").font(.system(size: 8, weight: .semibold)).foregroundStyle(WiiTheme.inkSoft)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(isPhone ? "Illustration of an upright iPhone" : "Illustration of an AirPod held by its stem. Match your own calibrated grip.")
    }
}

/// Latest response and applied shot are separate facts; a response may be reused
/// or superseded before the next contact. No model reasoning is invented here.
struct TennisRivalEvidencePanel: View {
    let status: TennisOpponentStatus
    @State private var expanded = false

    private var comparisonURL: URL? {
        Bundle.main.url(forResource: "DecisionComparison", withExtension: "html")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MotionButton { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("AI shot decisions").font(WiiTheme.display(13))
                    Text(status.stateLabel).font(WiiTheme.body(11, .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(GameIdentity.tennis.accent.opacity(0.10), in: Capsule())
                    Spacer(minLength: 8)
                    Text(status.appliedCandidateID.map { "Applied: \($0)" } ?? "No model shot applied yet")
                        .font(WiiTheme.body(11)).lineLimit(1)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Model chooses the shot; game handles movement and contact.")
                            .font(WiiTheme.body(12, .semibold))
                        Text("Astra and Jev receive the same state fields and five legal shots. This is tactical play.")
                            .font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                        if let comparisonURL {
                            Button("Open recorded Astra / Jev comparison") { NSWorkspace.shared.open(comparisonURL) }
                                .font(WiiTheme.body(11, .semibold))
                                .accessibilityHint("Opens recorded API results with every attempt and failure included. Gameplay pauses when the app loses focus.")
                        }
                        if let story = Bundle.main.url(forResource: "CodexDevelopmentStory", withExtension: "html") {
                            Button("How Codex helped fix the comparison") { NSWorkspace.shared.open(story) }
                                .font(WiiTheme.body(11, .semibold))
                        }
                        Divider()
                        evidenceRow("Input sent", status.inputSummary ?? "No input recorded yet")
                        evidenceRow("Latest response", status.selectedCandidateID ?? "Waiting for a valid decision")
                        evidenceRow("Applied on court", status.appliedCandidateID ?? "No model shot applied yet")
                        HStack(spacing: 18) {
                            Text(status.requestLatencyMS.map { String(format: "Request: %.0f ms", $0) } ?? "Request time: unavailable")
                            Text(status.planAgeSeconds.map { String(format: "Plan age at event: %.1f s", $0) } ?? "Plan age: unavailable")
                        }.font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                        if let elapsed = status.appliedObservationToShotMS {
                            Text(String(format: "Input observed → shot applied: %.0f ms", elapsed))
                                .font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                        }
                        Text("\(status.provider.uppercased()) · \(status.modelVersion) · \(status.decision)")
                            .font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                        DisclosureGroup("Observation and decision IDs") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest input: \(status.observationID ?? "—")")
                                Text("Latest decision: \(status.decisionID ?? "—")")
                                Text("Applied input: \(status.appliedObservationID ?? "—")")
                                Text("Applied decision: \(status.appliedDecisionID ?? "—")")
                            }.font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                        }.font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
        }.padding(13).frame(maxWidth: 640)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WiiTheme.hairline, lineWidth: 1))
            .foregroundStyle(WiiTheme.ink)
    }

    private func evidenceRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(WiiTheme.body(11, .semibold)).frame(width: 100, alignment: .leading)
            Text(detail).font(WiiTheme.body(11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
