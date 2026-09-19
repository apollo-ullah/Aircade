import AppKit
import MotionCore
import SwiftUI

struct TennisView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var game: TennisGame
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false
    @State private var showingSetup = false
    private let courtBlue = SportsTheme.blue

    var body: some View {
        ZStack {
            SaberView(controller: motion.scene).ignoresSafeArea()
            if game.state.phase == .menu { menu }
            else {
                VStack(spacing: 0) {
                    hud
                    Spacer()
                    if !game.feedback.isEmpty && game.state.phase == .playing {
                        VStack(spacing: 5) {
                            Text(game.feedback).font(.system(size: 24, weight: .bold)).italic()
                            if game.feedbackPoints > 0 { Text("+\(game.feedbackPoints)").font(.system(size: 30, weight: .bold)) }
                        }.foregroundStyle(game.feedbackGood ? .white : .yellow)
                            .shadow(color: .black.opacity(0.7), radius: 3, y: 1).padding(.bottom, 34)
                    }
                    footer
                }
                if game.state.phase == .countdown { countdown }
                if game.state.phase == .paused { pauseCard }
                if game.state.phase == .results { results }
            }
        }
        .foregroundStyle(SportsTheme.ink).background(SportsTheme.paper).tint(courtBlue)
        .sheet(isPresented: $players.showingSignIn, onDismiss: {
            if restoreCamera && motion.useCamera { motion.startCamera() }
            restoreCamera = false
        }) { BadgeSignInView(players: players) }
        .onChange(of: players.showingSignIn) {
            if players.showingSignIn {
                game.pause("Player sign-in is open.")
                restoreCamera = motion.camera.running
                motion.camera.stop()
            }
        }
        .sheet(isPresented: $showingSetup) { ControllerSetupView(motion: motion, done: { showingSetup = false }) }
        .onChange(of: showingSetup) { if showingSetup { game.pause("Controller setup is open.") } }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("aircade").foregroundStyle(courtBlue).font(.system(size: 34, weight: .medium)).tracking(-1)
                Rectangle().fill(courtBlue.opacity(0.25)).frame(width: 1, height: 30)
                Button("Neon Rush") { motion.selectSport(.neonRush) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Text("Tennis").fontWeight(.bold).foregroundStyle(courtBlue)
                Spacer()
                if let player = players.player {
                    Button { players.showingSignIn = true } label: { Label(player.nickname, systemImage: "person.crop.circle.fill") }.buttonStyle(SportsButtonStyle())
                    Button("Log out") { players.logout() }.buttonStyle(SportsButtonStyle())
                } else {
                    Button("Scan badge") { players.showingSignIn = true }.buttonStyle(SportsButtonStyle())
                }
                Button { NSWorkspace.shared.open(players.leaderboardURL) } label: { Image(systemName: "trophy") }.help("Open leaderboard")
                ControllerIdentityBadge(motion: motion)
                Button { showingSetup = true } label: { Label("Controller", systemImage: "airpodspro") }.buttonStyle(SportsButtonStyle())
            }.padding(.horizontal, 34).padding(.vertical, 20).background(.white.opacity(0.96))

            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("RALLY CHALLENGE", systemImage: "figure.tennis")
                        .font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(courtBlue)
                    Text("Tennis").font(.system(size: 52, weight: .bold)).tracking(-2)
                    Text("Keep the rally alive for 60 seconds.").font(.system(size: 19, weight: .medium))
                    Text("Your player automatically runs to the incoming ball. Swing your AirPod like a racket when it reaches you; your rival adapts its return plan between points.")
                        .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4)
                    HStack(spacing: 34) {
                        stat("60", "SECONDS")
                        stat("5", "BALLS")
                        stat(game.opponentStatus.fallbackUsed ? "LOCAL" : "AI", "RIVAL")
                    }.padding(.vertical, 8)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        rule("1", "WATCH", "Track the yellow ball as it clears the net.")
                        rule("2", "SWING", "Meet it near your racket with a deliberate stroke.")
                        rule("3", "RALLY", "Watch the rival move into position and answer your shot.")
                    }
                    Button {
                        if players.player == nil { players.showingSignIn = true }
                        else if game.inputReady { game.start() }
                        else { showingSetup = true }
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill").font(.title2)
                            Text(players.player == nil ? "Scan badge to play" : game.inputReady ? "Start rally" : "Connect your controller")
                            Spacer(); Image(systemName: "chevron.right")
                        }.font(.system(size: 18, weight: .bold)).padding(.vertical, 6)
                    }.buttonStyle(SportsButtonStyle(primary: true))
                }.padding(24).frame(width: 450).sportsPanel()

                VStack(alignment: .trailing, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(players.player?.nickname ?? "Guest", systemImage: "person.crop.circle.fill").fontWeight(.semibold)
                        Text("TENNIS HIGH SCORE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                        Text((players.player == nil ? game.bestScore : players.bests["Tennis", default: 0]).formatted())
                            .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(courtBlue)
                        Text(players.player == nil ? "Best on this Mac" : "Saved to your badge profile").font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(width: 300, alignment: .leading).sportsPanel()
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MODEL OPPONENT").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(courtBlue)
                        Text("A local policy keeps every rally responsive. When Baseten is configured, its candidate scores shape the next return plan.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(game.opponentStatus.label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(game.opponentStatus.fallbackUsed ? .orange : .green)
                    }.padding(20).frame(width: 300).sportsPanel()
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(24)
            Spacer(minLength: 0)
            HStack {
                Label(game.inputReady ? "\(motion.controllerName) ready" : "Connect AirPods to get started", systemImage: game.inputReady ? "checkmark.circle.fill" : "airpodspro")
                Spacer(); Text("Ⓡ  Recenter")
            }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 34).padding(.vertical, 16).background(.white.opacity(0.96))
        }
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(players.player?.nickname ?? "Player") · SCORE").font(.system(size: 12, weight: .semibold))
                Text(game.state.score.formatted()).font(.system(size: 38, weight: .semibold)).monospacedDigit()
                Text("Rally \(game.state.rally) · Best \(game.state.longestRally)").font(.system(size: 12))
            }.frame(width: 215, alignment: .leading).scoreboard()
            Spacer()
            VStack(spacing: 4) {
                Text("RALLY CHALLENGE").font(.system(size: 11, weight: .semibold)).tracking(1)
                Text(String(format: "%d:%02d", Int(ceil(game.state.remaining)) / 60, Int(ceil(game.state.remaining)) % 60))
                    .font(.system(size: 34, weight: .medium)).monospacedDigit()
                ProgressView(value: game.state.remaining, total: TennisMatch.duration).tint(.white).frame(width: 116)
            }.scoreboard()
            Spacer()
            VStack(alignment: .trailing, spacing: 9) {
                HStack { Text("BALLS").font(.system(size: 12, weight: .semibold)).tracking(1); Button { game.pause() } label: { Image(systemName: "pause.fill") }.buttonStyle(.plain) }
                HStack(spacing: 7) {
                    ForEach(0..<TennisMatch.startingBalls, id: \.self) { index in
                        Circle().fill(index < game.state.ballsLeft ? Color.yellow : .black.opacity(0.45)).frame(width: 18, height: 18)
                    }
                }
            }.scoreboard()
        }.foregroundStyle(.white).padding(24)
    }

    private var footer: some View {
        HStack {
            Text("Tennis").font(.system(size: 17, weight: .semibold)).italic()
            Text(game.opponentStatus.label).font(.system(size: 10, weight: .bold)).foregroundStyle(game.opponentStatus.fallbackUsed ? .yellow : .green)
            Spacer(); ControllerIdentityBadge(motion: motion)
            Text("Ⓡ Recenter    ␣ Pause").font(.system(size: 13, weight: .medium))
            Button { game.sound.toggle() } label: { Image(systemName: game.sound ? "speaker.wave.2" : "speaker.slash") }.buttonStyle(.plain)
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }

    private var countdown: some View {
        VStack(spacing: 10) {
            Text("READY YOUR RACKET").font(.system(size: 14, weight: .semibold)).tracking(2).foregroundStyle(.white)
            Text("\(max(1, Int(ceil(game.state.countdown))))").font(.system(size: 130, weight: .bold)).italic().foregroundStyle(.yellow)
            Text("Swing when the ball reaches you.").foregroundStyle(.white)
        }.shadow(color: .black.opacity(0.6), radius: 2, y: 1).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.25))
    }

    private var pauseCard: some View {
        card {
            Text("Match paused").font(.system(size: 42, weight: .bold)).italic()
            Text(game.pauseReason).foregroundStyle(.secondary)
            Label(game.inputReady ? "\(motion.controllerName) ready" : "Waiting for \(motion.controllerName)", systemImage: game.inputReady ? "checkmark.circle.fill" : "airpodspro")
                .foregroundStyle(game.inputReady ? courtBlue : .orange)
            actionButton("Back to the court") { game.resume() }.disabled(!game.inputReady)
            HStack(spacing: 22) { Button("Controller setup") { showingSetup = true }; Button("End run") { game.leave() } }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private var results: some View {
        card {
            Text(game.state.completed ? "TIME" : "GAME OVER").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(courtBlue)
            HStack(spacing: 28) {
                Text(game.state.completed ? game.state.rank : "↻").font(.system(size: 78, weight: .bold)).italic().foregroundStyle(courtBlue)
                VStack(alignment: .leading) {
                    Text(game.state.score.formatted()).font(.system(size: 52, weight: .bold)).monospacedDigit()
                    Text(players.bests["Tennis"].map { "YOUR BEST \($0.formatted())" } ?? "SAVING TO YOUR PROFILE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 36) {
                stat("\(game.state.returns)", "RETURNS")
                stat("\(game.state.longestRally)", "BEST RALLY")
                stat("\(game.state.accuracy)%", "ACCURACY")
            }
            Text(players.saveStatus).font(.caption).foregroundStyle(.secondary)
            actionButton("Play again") { game.start() }.disabled(!game.inputReady)
            HStack(spacing: 24) {
                Button("Back to Aircade") { game.leave() }
                Button("Next player") { game.leave(); players.nextPlayer() }
                Button("Leaderboard") { NSWorkspace.shared.open(players.leaderboardURL) }
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            courtBlue.opacity(0.22)
            VStack(spacing: 22, content: content).padding(38).frame(width: 600).sportsPanel()
        }
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .bold, design: .monospaced)).padding(18).foregroundStyle(.white).background(courtBlue, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit(); Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary) }
    }
    private func rule(_ number: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Text(number).font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36).foregroundStyle(courtBlue).background(courtBlue.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
