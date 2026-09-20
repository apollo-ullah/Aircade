import AppKit
import MotionCore
import SwiftUI

struct TennisView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var game: TennisGame
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false
    @State private var showingSetup = false
    @State private var showingCodexPrompt = false
    @State private var showingSensorEvidence = false
    @State private var pendingRallyAfterIdentity = false
    @State private var identityApproved = false
    private let courtBlue = GameIdentity.tennis.accent
    private var canStartRally: Bool { game.opponentReady || motion.activeInputSimulated }

    var body: some View {
        ZStack {
            SaberView(controller: motion.scene).ignoresSafeArea()
            if game.codexPractice && (game.state.phase == .playing || game.state.phase == .countdown) {
                directOpponentSurface
            }
            if game.state.phase == .menu { menu }
            else {
                VStack(spacing: 0) {
                    hud
                    if !game.codexPractice && (game.state.phase == .playing || game.state.phase == .countdown) {
                        TennisRivalEvidencePanel(status: game.opponentStatus).padding(.horizontal, 24)
                    }
                    Spacer()
                    if game.state.phase == .playing && game.state.returns == 0 {
                        Label("Swing as the ball reaches your racket. Your player runs automatically.", systemImage: "figure.tennis")
                            .font(WiiTheme.body(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.black.opacity(0.65), in: Capsule()).padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
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
        .foregroundStyle(WiiTheme.ink).background(WiiTheme.stageMid).tint(courtBlue)
        .onAppear {
            players.refreshLeaderboard("Tennis")
            if !game.codexPractice { game.prepareOpponent() }
        }
        .sheet(isPresented: $players.showingSignIn, onDismiss: {
            if restoreCamera && motion.useCamera { motion.startCamera() }
            restoreCamera = false
            if pendingRallyAfterIdentity {
                let shouldStart = identityApproved
                pendingRallyAfterIdentity = false
                identityApproved = false
                if shouldStart { game.start(demo: false) }
            }
        }) {
            BadgeSignInView(players: players, runPrompt: pendingRallyAfterIdentity,
                            onReady: pendingRallyAfterIdentity ? { identityApproved = true } : nil)
        }
        .onChange(of: players.showingSignIn) {
            if players.showingSignIn {
                game.pause("Player sign-in is open.")
                restoreCamera = motion.camera.running
                motion.camera.stop()
            }
        }
        .sheet(isPresented: $showingSetup) { ControllerSetupView(motion: motion, done: { showingSetup = false }) }
        .onChange(of: showingSetup) {
            if showingSetup { game.pause("Controller setup is open.") }
            else { game.prepareOpponent() }
        }
        .sheet(isPresented: $showingCodexPrompt) { CodexOpponentPrompt() }
        .sheet(isPresented: $showingSensorEvidence, onDismiss: { game.dismissOpponentInspector() }) {
            SensorEvidenceView(motion: motion)
        }
    }

    private var menu: some View {
        GameLobby(identity: .tennis) {
            HStack {
                GameMetric(value: "60", label: "SECONDS")
                GameMetric(value: "5", label: "BALLS")
                GameMetric(value: "1", label: "REAL CONTROLLER")
            }.padding(.vertical, 3)
            TennisHandoffCard(motion: motion, controllers: motion.controllers, ready: game.liveReady,
                              openSetup: { showingSetup = true })
            GameRule(symbol: "figure.tennis", title: "You swing. Your player runs.",
                     detail: "Swing when the ball reaches your racket.", color: courtBlue)
            MotionButton(action: openSensorEvidence) {
                Label("How it works · sensor to racket", systemImage: "waveform.path")
                    .font(WiiTheme.body(13, .semibold)).foregroundStyle(courtBlue)
            }.buttonStyle(.plain)
        } options: {
            HStack {
                Text("Choose your rival").font(WiiTheme.display(22))
                Spacer()
                Image(systemName: "figure.tennis").foregroundStyle(courtBlue)
            }
            VStack(spacing: 10) {
                MotionButton { game.selectTacticalOpponent("astra") } label: {
                    GameOption(title: "Astra · OpenAI API", detail: "Chooses the shot · game moves the rival", symbol: "sparkles",
                               selected: !game.codexPractice && game.tacticalProvider == "astra", accent: courtBlue)
                }
                MotionButton { game.selectTacticalOpponent("jev") } label: {
                    GameOption(title: "Jev", detail: "Same state, shots and movement assistance", symbol: "bolt.fill",
                               selected: !game.codexPractice && game.tacticalProvider == "jev", accent: courtBlue)
                }
                MotionButton { game.selectTacticalOpponent("baseten") } label: {
                    GameOption(title: "Baseten", detail: "Tactical rival · normal speed", symbol: "figure.tennis",
                               selected: !game.codexPractice && game.tacticalProvider == "baseten", accent: courtBlue)
                }
                MotionButton { game.selectCodexOpponent(); showingCodexPrompt = true } label: {
                    GameOption(title: "Codex · computer use", detail: "Screen controls · slower play · unranked", symbol: "cursorarrow.motionlines",
                               selected: game.codexPractice, accent: courtBlue)
                }
            }.buttonStyle(GameActionStyle())
            if game.codexPractice {
                Text("Codex watches the screen, moves the rival and presses swing. Early swings are buffered. This mode does not call the OpenAI API from the game.")
                    .font(WiiTheme.body(11)).foregroundStyle(WiiTheme.inkSoft)
                MotionButton("Copy instructions for Codex") { showingCodexPrompt = true }
                    .buttonStyle(.plain).foregroundStyle(courtBlue).font(WiiTheme.body(12, .semibold))
            }
            HStack(spacing: 8) {
                Image(systemName: canStartRally ? "checkmark.circle.fill" : "clock")
                Text(motion.activeInputSimulated ? "Demo ready · score not saved" : game.codexPractice ? "Practice ready · invite Codex to play" : game.opponentStatus.label)
                    .fixedSize(horizontal: false, vertical: true)
            }.font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            MotionButton(id: "start-tennis") {
                if !game.liveReady { showingSetup = true }
                else if !canStartRally { game.prepareOpponent() }
                else if motion.activeInputSimulated { game.start(demo: true) }
                else {
                    identityApproved = false
                    pendingRallyAfterIdentity = true
                    players.showingSignIn = true
                }
            } label: {
                GamePrimaryAction(title: !game.liveReady ? "Set up controller" : !canStartRally ? "Prepare rival · retry" : motion.activeInputSimulated ? "Start demo rally" : "Start rally",
                                  symbol: game.liveReady ? "play.fill" : "gamecontroller.fill", accent: courtBlue)
            }.buttonStyle(GameActionStyle())
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(courtBlue)
                Text("Best  \((players.player == nil ? game.bestScore : players.bests["Tennis", default: 0]).formatted())").font(WiiTheme.display(13))
                Spacer()
                MotionButton(players.player?.nickname ?? "Guest") { players.showingSignIn = true }
                    .buttonStyle(.plain).font(WiiTheme.body(12)).foregroundStyle(courtBlue).disabled(!players.profilesAvailable)
            }
            if let standing = players.standings["Tennis"] {
                Text(standing.challenge).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            }
            if !game.codexPractice { TennisRivalEvidencePanel(status: game.opponentStatus) }
        }
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(players.player?.nickname ?? "Player") · SCORE").font(.system(size: 12, weight: .semibold))
                Text(game.state.score.formatted()).font(WiiTheme.display(38)).monospacedDigit()
                Text("\(game.state.rally) rally  /  \(game.state.longestRally) best").font(.system(size: 12))
            }.frame(width: 215, alignment: .leading).gameReadout()
            Spacer()
            VStack(spacing: 4) {
                Text("RALLY CHALLENGE").font(.system(size: 11, weight: .semibold)).tracking(1)
                Text(String(format: "%d:%02d", Int(ceil(game.state.remaining)) / 60, Int(ceil(game.state.remaining)) % 60))
                    .font(WiiTheme.display(34, .semibold)).monospacedDigit()
                ProgressView(value: game.state.remaining, total: TennisMatch.duration).tint(.white).frame(width: 116)
            }.gameReadout()
            Spacer()
            VStack(alignment: .trailing, spacing: 9) {
                HStack {
                    if game.manualOpponentEnabled {
                        MotionButton("RIVAL SWING") { game.swingOpponent() }
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .foregroundStyle(.black)
                            .accessibilityLabel("Swing opponent racket")
                    }
                    Text("BALLS").font(.system(size: 12, weight: .semibold)).tracking(1)
                    MotionButton { game.pause() } label: { Image(systemName: "pause.fill").frame(width: 40, height: 36).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).accessibilityLabel("Pause tennis")
                }
                HStack(spacing: 7) {
                    ForEach(0..<TennisMatch.startingBalls, id: \.self) { index in
                        Circle().fill(index < game.state.ballsLeft ? Color.yellow : .black.opacity(0.45)).frame(width: 18, height: 18)
                    }
                }
            }.gameReadout()
        }.foregroundStyle(.white).padding(24)
            .allowsHitTesting(game.state.phase == .playing || game.state.phase == .countdown)
    }

    private var directOpponentSurface: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let normalized = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                            game.moveOpponent(to: Float((normalized - 0.5) * 9.2))
                        }
                )
                .accessibilityLabel("Opponent court control")
                .accessibilityHint("Drag horizontally to move the opponent. Use Swing opponent racket to hit.")
        }
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack {
            Text("Tennis").font(WiiTheme.display(16))
            Text(game.codexPractice ? "COMPUTER USE · Slower play · Buffered swings · Unranked" : game.isDemo ? "SIMULATED INPUT · SCORE NOT SAVED" : "\(game.tacticalProvider.uppercased()) · MODEL SHOT / GAME MOVEMENT").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer(); Label(motion.activeControllerName, systemImage: "gamecontroller.fill").font(WiiTheme.body(12, .semibold))
            MotionButton(action: openSensorEvidence) { Label("How it works", systemImage: "waveform.path") }
                .buttonStyle(.plain).font(WiiTheme.body(12, .semibold))
            MotionButton { game.sound.toggle() } label: { Image(systemName: game.sound ? "speaker.wave.2" : "speaker.slash").frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel(game.sound ? "Mute sound" : "Enable sound")
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }

    private var countdown: some View {
        GameCountdown(value: game.state.countdown, title: "READY YOUR RACKET", hint: "Swing when the ball reaches you.")
    }

    private var pauseCard: some View {
        card {
            Image(systemName: "pause.circle.fill").font(.system(size: 40)).foregroundStyle(courtBlue)
            Text("Match paused").font(WiiTheme.display(36))
            Text(game.pauseReason).foregroundStyle(WiiTheme.inkSoft).multilineTextAlignment(.center)
            TennisHandoffCard(motion: motion, controllers: motion.controllers, ready: game.liveReady,
                              openSetup: { showingSetup = true })
            if !game.codexPractice { TennisRivalEvidencePanel(status: game.opponentStatus) }
            actionButton("Resume rally") { game.resume() }.disabled(!game.liveReady)
            HStack(spacing: 22) { MotionButton("Controller setup") { showingSetup = true }; MotionButton("End run") { game.leave() } }
                .buttonStyle(WiiButtonStyle())
        }
    }

    private var results: some View {
        card {
            Text(game.state.completed ? "TIME" : "GAME OVER").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(courtBlue)
            HStack(spacing: 28) {
                Text(game.state.completed ? game.state.rank : "↻").font(WiiTheme.display(78)).foregroundStyle(courtBlue)
                VStack(alignment: .leading) {
                    Text(game.state.score.formatted()).font(WiiTheme.display(52)).monospacedDigit()
                    Text(game.codexPractice ? "COMPUTER-USE PRACTICE · NOT SAVED" : game.isDemo ? "SIMULATED RUN · NOT SAVED" : players.bests["Tennis"].map { "YOUR BEST \($0.formatted())" } ?? "BEST ON THIS MAC \(game.bestScore.formatted())")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 36) {
                stat("\(game.state.returns)", "RETURNS")
                stat("\(game.state.longestRally)", "BEST RALLY")
                stat("\(game.state.accuracy)%", "ACCURACY")
            }
            RankProgressCard(players: players, runID: game.runID)
            Text(game.state.assistedOpponent ? "Practice run — score not saved." : players.saveStatus).font(.caption).foregroundStyle(.secondary)
            Text("Same controller · same rival · ready for another round").font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            if !game.codexPractice { TennisRivalEvidencePanel(status: game.opponentStatus) }
            actionButton("Replay rally") { game.start(demo: motion.activeInputSimulated) }.disabled(!game.liveReady || !canStartRally)
            if !game.liveReady {
                TennisHandoffCard(motion: motion, controllers: motion.controllers, ready: false,
                                  openSetup: { showingSetup = true })
            }
            if !canStartRally {
                MotionButton("Reconnect model rival") { game.prepareOpponent() }.buttonStyle(WiiButtonStyle())
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MotionButton("Back to Aircade") { NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.home) }
                MotionButton("Next player") { game.leave(); players.nextPlayer() }
                if !game.liveReady { MotionButton("Connect controller") { showingSetup = true } }
                MotionButton("Leaderboard") { NSWorkspace.shared.open(players.leaderboardURL(for: "Tennis")) }
            }.buttonStyle(WiiButtonStyle())
        }
    }

    private func card<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GameOverlay(content: content)
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        MotionButton(action: action) { GamePrimaryAction(title: title, accent: courtBlue) }.buttonStyle(GameActionStyle())
    }
    private func stat(_ value: String, _ label: String) -> some View {
        GameMetric(value: value, label: label)
    }

    private func openSensorEvidence() {
        game.suspendOpponentForInspector()
        showingSensorEvidence = true
    }

}

private struct CodexOpponentPrompt: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private let prompt = """
    Play the far-side opponent in the Tennis game currently visible in the Aircade window. Use computer control on that same window and continue until the match ends.

    Act immediately during play. Do not narrate, explain, or wait between actions. Inspect the screen frequently and prioritize mouse actions over messages.

    Controls:
    • Drag horizontally anywhere on the open court to move the far-side character left or right.
    • Track the yellow ball. When it travels toward the far side, drag the opponent to the ball's projected horizontal arrival position as early as possible.
    • Click RIVAL SWING as soon as the ball is traveling toward the far side. Early swings are buffered, so do not wait for exact contact.
    • Keep repositioning while the ball is in flight. React to every rally until the result screen appears.

    The human controls the near racket with an AirPod or iPhone. Control only the far opponent. If a menu is visible, wait for the human to start the rally. If the match is paused or finished, stop and report that briefly.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Play against Codex").font(.title.bold())
                    Text("Copy this into your Codex task, then return here and start the rally.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MotionButton { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(WiiButtonStyle())
            }

            ScrollView {
                Text(prompt)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .frame(height: 360)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))

            MotionButton {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(prompt, forType: .string)
                copied = true
            } label: {
                Label(copied ? "Copied — paste into Codex" : "Copy Codex prompt",
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WiiButtonStyle(primary: true))
        }
        .padding(26)
        .frame(width: 680, height: 560)
        .background(WiiTheme.stage)
    }
}
