import SwiftUI
import MotionCore

struct MultiplayerView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var duel: MultiplayerModel
    @State private var setup = false
    var body: some View {
        ZStack {
            SaberView(controller: duel.scene.court).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { motion.showMultiplayer(false) } label: { Label("Aircade", systemImage: "chevron.left") }
                        .buttonStyle(SportsButtonStyle())
                    Text("Saber Duel").font(.system(size: 26, weight: .bold)).italic()
                    if duel.scripted { Text("SCRIPTED DEMO").font(.caption.bold()).foregroundStyle(.orange) }
                    Spacer()
                    if duel.match.phase != .lobby {
                        Text(String(format: "%d:%02d", Int(ceil(duel.match.remaining)) / 60, Int(ceil(duel.match.remaining)) % 60))
                            .font(.system(size: 28, weight: .bold)).monospacedDigit()
                        if duel.match.phase == .playing || duel.match.phase == .countdown {
                            Button("Pause") { duel.pause() }.buttonStyle(SportsButtonStyle())
                        }
                    }
                }.padding(22).background(.white.opacity(0.96))
                HStack(alignment: .top) {
                    player(.one, name: duel.localName, color: SportsTheme.blue)
                    Spacer()
                    player(.two, name: duel.scripted ? "Scripted orange" : "iPhone", color: .orange)
                }.padding(24)
                Spacer()
                if !duel.feedback.isEmpty {
                    Text(duel.feedback).font(.system(size: 38, weight: .heavy)).italic()
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 3).padding()
                }
                HStack {
                    Text("Swing through the other player’s target. Cross blades to block.")
                    Spacer()
                    Text("5 health · 60 seconds")
                }.font(.callout.weight(.semibold)).padding(20).background(.white.opacity(0.96))
            }
            if duel.match.phase == .lobby { lobby }
            if duel.match.phase == .countdown {
                VStack(spacing: 10) {
                    Text("HOLD YOUR STARTING POSE").font(.headline)
                    Text("\(max(1, Int(ceil(duel.match.countdown))))").font(.system(size: 120, weight: .heavy))
                    Text(duel.match.recovering ? "Waiting for both controllers…" : "Blue attacks right. Orange attacks left.")
                }.foregroundStyle(.white).shadow(color: .black, radius: 4).allowsHitTesting(false)
            }
            if duel.match.phase == .playing && duel.match.recovering {
                Text("Waiting for controller… Match clock held.").padding(20).sportsPanel()
            }
            if duel.match.phase == .paused { paused }
            if duel.match.phase == .results { results }
        }.foregroundStyle(SportsTheme.ink).tint(SportsTheme.blue)
            .sheet(isPresented: $setup) { ControllerSetupView(motion: motion, done: { setup = false }) }
            .onChange(of: setup) { if setup { duel.pause("Player 1 controller setup is open.") } }
    }
    private func player(_ slot: PlayerSlot, name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PLAYER \(slot.rawValue + 1) · \(slot == .one ? "BLUE" : "ORANGE")").font(.caption.bold()).foregroundStyle(color)
            Text(name).font(.title3.bold())
            HStack(spacing: 5) {
                ForEach(0..<5) { index in
                    Image(systemName: index < duel.match.health[slot.rawValue] ? "heart.fill" : "heart")
                        .foregroundStyle(color)
                }
            }
            Label(duel.ready[slot.rawValue] ? "Ready" : "Waiting for motion", systemImage: duel.ready[slot.rawValue] ? "checkmark.circle.fill" : "circle.dotted")
                .font(.caption).foregroundStyle(duel.ready[slot.rawValue] ? SportsTheme.green : .secondary)
        }.padding(18).frame(minWidth: 210, alignment: .leading).sportsPanel()
    }
    private var lobby: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("BETTER WITH A RIVAL", systemImage: "person.2.fill").font(.caption.bold()).foregroundStyle(SportsTheme.blue)
            Text("Your couch. Your arena.").font(.system(size: 32, weight: .bold)).italic()
            Text("Two independent controllers. One shared screen.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("1 · AirPod", systemImage: "airpodspro").font(.title3.bold()).foregroundStyle(SportsTheme.blue)
                    Text("Hold the earbud named above. Your existing grip calibration works here.").font(.callout)
                    Button("Set up player 1") { setup = true }.buttonStyle(SportsButtonStyle())
                }.frame(width: 225)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("2 · iPhone", systemImage: "iphone").font(.title3.bold()).foregroundStyle(.orange)
                    Text("Open Aircade Controller, select this Mac, and enter:").font(.callout)
                    Text(duel.code).font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(5).textSelection(.enabled)
                    Text(duel.phoneStatus).font(.caption).foregroundStyle(.secondary)
                    Text(duel.networkStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Pair a different phone") { duel.forgetPhone() }.buttonStyle(.plain).font(.caption).foregroundStyle(SportsTheme.blue)
                }.frame(width: 255)
            }.fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Hold the iPhone upright, screen facing you. Tap Recenter on the phone. Tilt its top edge to aim the orange saber.").font(.callout)
            Button { duel.start() } label: {
                HStack { Text(duel.bothReady ? "Start duel" : "Waiting for both controllers"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.headline)
            }.buttonStyle(SportsButtonStyle(primary: true)).disabled(!duel.bothReady)
            HStack {
                Button(duel.scripted ? "Use real controllers" : "Watch scripted duel") {
                    duel.setScripted(!duel.scripted)
                    if duel.scripted { duel.tick(); duel.start() }
                }.buttonStyle(.plain).foregroundStyle(SportsTheme.blue)
                Spacer()
                Text("One AirPods pair = one player").foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(28).frame(width: 590).sportsPanel()
    }
    private var paused: some View {
        VStack(spacing: 20) {
            Text("Time out.").font(.system(size: 40, weight: .bold)).italic()
            Text(duel.match.pauseReason).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Resume duel") { duel.resume() }.buttonStyle(SportsButtonStyle(primary: true)).disabled(!duel.bothReady)
            HStack(spacing: 24) {
                Button("Player 1 setup") { setup = true }
                Button("Back to lobby") { duel.lobby() }
            }.buttonStyle(.plain).foregroundStyle(SportsTheme.blue)
        }.padding(35).frame(width: 520).sportsPanel()
    }
    private var results: some View {
        VStack(spacing: 18) {
            Image(systemName: "trophy.fill").font(.system(size: 52)).foregroundStyle(.orange)
            Text(duel.match.winner.map { $0 == .one ? "Blue wins!" : "Orange wins!" } ?? "It’s a draw!")
                .font(.system(size: 44, weight: .bold)).italic()
            Text("Blue \(duel.match.health[0]) — \(duel.match.health[1]) Orange").font(.title2)
            if duel.scripted { Text("Scripted inputs · hardware not verified").font(.caption).foregroundStyle(.secondary) }
            Button("Rematch") { duel.start() }.buttonStyle(SportsButtonStyle(primary: true)).disabled(!duel.bothReady)
            Button("Back to lobby") { duel.lobby() }.buttonStyle(.plain).foregroundStyle(SportsTheme.blue)
        }.padding(36).frame(width: 440).sportsPanel()
    }
}
