import SwiftUI

/// Earbud identity is separate from the hand holding it and from tilt direction.
struct EarbudIdentityCard: View {
    let source: String
    let purpose: String
    let isLive: Bool
    var compact = false
    var detail: String? = nil
    private var known: Bool { source == "Left" || source == "Right" }
    private var demo: Bool { source == "Simulated" || source == "Scripted" }
    private var name: String { known ? "\(source.uppercased()) AIRPOD" : demo ? (source == "Scripted" ? "SCRIPTED SABER" : "DEMO INPUT") : "NO AIRPOD YET" }
    private var mark: String { known ? String(source.prefix(1)) : demo ? "▶" : "?" }
    private var tint: Color { isLive ? Color(red: 0.35, green: 0.93, blue: 0.91) : .orange }
    var body: some View {
        HStack(spacing: 12) {
            Text(mark).font(.system(size: compact ? 19 : 30, weight: .black, design: .rounded))
                .frame(width: compact ? 34 : 52, height: compact ? 34 : 52)
                .foregroundStyle(.black).background(tint, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(purpose).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                Text(name).font(.system(size: compact ? 13 : 21, weight: .bold, design: .rounded)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if !compact && known {
                    Text("Hold the earbud marked \(mark). Either hand is fine.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !compact { Spacer(minLength: 8) }
            VStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(isLive ? "LIVE" : known ? "PAUSED" : "WAITING").font(.system(size: 9, weight: .bold, design: .monospaced))
            }.foregroundStyle(tint)
        }.padding(compact ? 10 : 14)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct ControllerIdentityBadge: View {
    @ObservedObject var motion: MotionModel
    var compact = true
    var body: some View {
        EarbudIdentityCard(source: motion.scriptedScenario == nil ? motion.source : "Scripted",
            purpose: motion.scriptedScenario != nil ? "AUTOMATED TEST" : motion.simulated ? "SIMULATED CONTROLLER" : motion.hasFreshMotion ? "ACTIVE CONTROLLER" : "SELECTED CONTROLLER",
            isLive: motion.hasFreshMotion, compact: compact,
            detail: motion.sourceMismatch ? "\(motion.incomingSource) is reporting · open setup" : nil)
    }
}
