import SwiftUI
import MotionCore

struct MultiplayerView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var duel: MultiplayerModel
    @State private var setup = false
    private let accent = GameIdentity.duel.accent

    var body: some View {
        ZStack {
            SaberView(controller: duel.scene.court).ignoresSafeArea()
            if duel.match.phase == .lobby { lobby }
            else {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 24) {
                        player(.one, color: WiiTheme.accent)
                        Spacer(minLength: 12)
                        VStack(spacing: 7) {
                            Text("SABER DUEL").font(WiiTheme.display(11)).tracking(2)
                            Text(String(format: "%d:%02d", Int(ceil(duel.match.remaining)) / 60, Int(ceil(duel.match.remaining)) % 60))
                                .font(WiiTheme.display(34)).monospacedDigit()
                            MotionButton { duel.pause() } label: {
                                Label("Pause", systemImage: "pause.fill").font(WiiTheme.display(12)).padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.white.opacity(0.12), in: Capsule())
                            }.buttonStyle(.plain).accessibilityLabel("Pause duel")
                        }.foregroundStyle(.white).gameReadout()
                        Spacer(minLength: 12)
                        player(.two, color: Color(red: 1, green: 0.67, blue: 0.32))
                    }.padding(24)
                        .allowsHitTesting(duel.match.phase == .playing || duel.match.phase == .countdown)
                    Spacer()
                    if !duel.feedback.isEmpty && duel.match.phase == .playing {
                        Text(duel.feedback).font(WiiTheme.display(34))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 4).padding(24)
                            .allowsHitTesting(false)
                    }
                    HStack(spacing: 18) {
                        Label("Blue attacks right", systemImage: "arrow.right").foregroundStyle(WiiTheme.accent)
                        Spacer()
                        if duel.scripted { Text("DEMO · SIMULATED CONTROLLERS").foregroundStyle(.yellow) }
                        else { Text("Cross blades to block  ·  Space to pause") }
                        Spacer()
                        Label("Orange attacks left", systemImage: "arrow.left").foregroundStyle(Color.orange)
                    }.font(WiiTheme.display(12, .semibold)).foregroundStyle(.white)
                        .padding(22).background(.black.opacity(0.55))
                }
                if duel.match.phase == .countdown {
                    GameCountdown(value: duel.match.countdown, title: "READY YOUR BLADES",
                                  hint: duel.match.recovering ? "Waiting for both controllers…" : "Blue attacks right. Orange attacks left.")
                }
                if duel.match.phase == .playing && duel.match.recovering {
                    Label("Waiting for controller… Match clock held.", systemImage: "gamecontroller")
                        .font(WiiTheme.display(16)).padding(22).wiiPanel(radius: 20)
                }
                if duel.match.phase == .paused { paused }
                if duel.match.phase == .results { results }
            }
        }.foregroundStyle(WiiTheme.ink).tint(accent)
            .sheet(isPresented: $setup) { ControllerSetupView(motion: motion, done: { setup = false }) }
            .onChange(of: setup) { if setup { duel.pause("Controller setup is open.") } }
    }

    private func player(_ slot: PlayerSlot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PLAYER \(slot.rawValue + 1) · \(slot == .one ? "BLUE" : "ORANGE")")
                .font(WiiTheme.display(11)).tracking(1).foregroundStyle(color)
            Text(duel.name(slot)).font(WiiTheme.display(18)).lineLimit(1)
            HStack(spacing: 7) {
                ForEach(0..<5) { index in
                    Image(systemName: index < duel.match.health[slot.rawValue] ? "heart.fill" : "heart")
                        .font(.system(size: 21)).foregroundStyle(index < duel.match.health[slot.rawValue] ? color : .white.opacity(0.3))
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(duel.match.health[slot.rawValue]) of 5 health")
        }.frame(width: 220, alignment: .leading).foregroundStyle(.white).gameReadout()
    }

    private var lobby: some View {
        GameLobby(identity: .duel) {
            HStack {
                GameMetric(value: "2", label: "PLAYERS")
                GameMetric(value: "5", label: "HEALTH EACH")
                GameMetric(value: "60", label: "SECONDS")
            }.padding(.vertical, 3)
            GameRule(symbol: "burst.fill", title: "Attack their target",
                     detail: "Blue swings right. Orange swings left. Each hit takes one health.", color: accent)
            GameRule(symbol: "shield.lefthalf.filled", title: "Cross blades to block",
                     detail: "Protect your target. Most health at the buzzer wins.", color: accent)
        } options: {
            HStack {
                Text("Bring a rival").font(WiiTheme.display(22))
                Spacer(); Image(systemName: "person.2.fill").foregroundStyle(accent)
            }
            Text("One AirPod + one iPhone. Pick who plays blue, then get both controllers ready.")
                .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            VStack(spacing: 10) {
                ForEach(PlayerSlot.allCases, id: \.self) { slot in
                    HStack(spacing: 13) {
                        Text("\(slot.rawValue + 1)").font(WiiTheme.display(20))
                            .frame(width: 44, height: 44).foregroundStyle(.white)
                            .background(slot == .one ? WiiTheme.accentDeep : Color(red: 0.8, green: 0.43, blue: 0.16), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(duel.name(slot)).font(WiiTheme.display(15))
                            Label(duel.ready[slot.rawValue] ? "Ready to play" : "Connect & recenter", systemImage: duel.ready[slot.rawValue] ? "checkmark.circle.fill" : "circle.dotted")
                                .font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Text(slot == .one ? "BLUE" : "ORANGE").font(WiiTheme.display(10)).foregroundStyle(WiiTheme.inkSoft)
                    }.padding(14).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WiiTheme.hairline, lineWidth: 1))
                }
            }
            if !duel.scripted && !motion.controllers.phoneHost.connected {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Pair your iPhone", systemImage: "iphone").font(WiiTheme.display(13))
                    Text("Open Aircade Controller, select this Mac, and enter:")
                        .font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
                    Text(duel.code.isEmpty ? "Starting…" : duel.code)
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(5).textSelection(.enabled)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            }
            MotionButton { setup = true } label: {
                HStack {
                    Label("Set up & assign controllers", systemImage: "gamecontroller.fill")
                    Spacer(); Image(systemName: "chevron.right")
                }.font(WiiTheme.display(13)).foregroundStyle(accent).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            MotionButton {
                if duel.bothReady { duel.start() } else { setup = true }
            } label: {
                GamePrimaryAction(title: duel.bothReady ? "Start duel" : "Connect players", symbol: duel.bothReady ? "play.fill" : "gamecontroller.fill", accent: accent)
            }.buttonStyle(GameActionStyle())
            MotionButton {
                duel.setScripted(!duel.scripted)
                if duel.scripted { duel.tick(); duel.start() }
            } label: {
                Label(duel.scripted ? "Use real controllers" : "Watch a demo duel", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(WiiButtonStyle())
            Text("One AirPods pair provides one player.")
                .font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft).frame(maxWidth: .infinity)
        }
    }

    private var paused: some View {
        GameOverlay {
            Image(systemName: "pause.circle.fill").font(.system(size: 40)).foregroundStyle(accent)
            Text("Time out").font(WiiTheme.display(36))
            Text(duel.match.pauseReason).multilineTextAlignment(.center).foregroundStyle(WiiTheme.inkSoft)
            HStack(spacing: 20) {
                readiness(.one)
                readiness(.two)
            }
            MotionButton { duel.resume() } label: { GamePrimaryAction(title: "Resume duel", accent: accent) }
                .buttonStyle(GameActionStyle()).disabled(!duel.bothReady)
            HStack(spacing: 16) {
                MotionButton("Controller setup") { setup = true }
                MotionButton("Back to lobby") { duel.lobby() }
            }.buttonStyle(WiiButtonStyle())
        }
    }
    private func readiness(_ slot: PlayerSlot) -> some View {
        Label("\(slot == .one ? "Blue" : "Orange") · \(duel.ready[slot.rawValue] ? "Ready" : "Waiting")",
              systemImage: duel.ready[slot.rawValue] ? "checkmark.circle.fill" : "circle.dotted")
            .font(WiiTheme.display(13)).foregroundStyle(WiiTheme.inkSoft)
    }
    private var results: some View {
        GameOverlay {
            Image(systemName: duel.match.winner == nil ? "equal.circle.fill" : "trophy.fill")
                .font(.system(size: 52)).foregroundStyle(duel.match.winner == .two ? .orange : accent)
            Text(duel.match.winner.map { $0 == .one ? "Blue wins!" : "Orange wins!" } ?? "It’s a draw!")
                .font(WiiTheme.display(44))
            Text(duel.match.winner.map { "\(duel.name($0)) takes the arena." } ?? "Evenly matched. Settle it with a rematch.")
                .font(WiiTheme.body(15)).foregroundStyle(WiiTheme.inkSoft)
            HStack(spacing: 24) {
                GameMetric(value: "\(duel.match.health[0]) / 5", label: "BLUE HEALTH")
                GameMetric(value: "\(duel.match.health[1]) / 5", label: "ORANGE HEALTH")
            }.padding(20).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            if duel.scripted { Text("Demo duel · simulated controllers").font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft) }
            MotionButton { duel.start() } label: { GamePrimaryAction(title: "Rematch", accent: accent) }
                .buttonStyle(GameActionStyle()).disabled(!duel.bothReady)
            HStack(spacing: 16) {
                MotionButton("Back to lobby") { duel.lobby() }
                MotionButton("Back to Aircade") { NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.home) }
                if !duel.bothReady { MotionButton("Controller setup") { setup = true } }
            }.buttonStyle(WiiButtonStyle())
        }
    }
}
