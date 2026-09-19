import AppKit
import MotionCore
import SwiftUI

struct AIChallengeView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var tennis: TennisGame
    @ObservedObject var game: AIChallengeGame
    @ObservedObject var players: PlayerSession
    var setup: () -> Void

    var body: some View {
        ZStack {
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("\(game.playerName)  \(game.match.humanPoints) : \(game.match.aiPoints)  \(game.manual ? "Manual" : "Astra")").font(.title.bold())
                        Text("SCREEN CONTROL · EXPERIMENTAL · 8-SECOND FLIGHTS").font(.caption.bold())
                    }.wiiReadout()
                    Spacer()
                    Text("\(Int(ceil(game.match.remaining)))s").font(.largeTitle.monospacedDigit()).wiiReadout()
                    MotionButton { game.pause("Take a breath.") } label: { Image(systemName: "pause.fill") }.buttonStyle(WiiButtonStyle())
                }.foregroundStyle(.white)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(game.status).font(.headline)
                        Text("\(game.latencyMS) ms decision · \(game.match.aiReturns) real returns").font(.caption)
                        Text(game.lastAction).font(.caption.monospaced()).lineLimit(2)
                        Text(String(format: "Last input age %.1fs · capture %.0fms", game.observationAge, game.captureMS)).font(.caption2)
                        if let image = game.lastObservation {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 230)
                            Text("Exact last screen sent to Astra").font(.caption2)
                        }
                    }.padding(16).frame(width: 280, alignment: .leading).wiiPanel()
                    Spacer()
                    ActiveControllerBadge(motion: motion, controllers: motion.controllers)
                }
            }.padding(24)
            if game.match.phase != .playing { card }
        }
    }
    private var card: some View {
        VStack(spacing: 18) {
            Text(game.match.phase == .results ? game.match.winner : game.match.phase == .paused ? "Match paused" : "Can you beat Astra?").font(.largeTitle.bold())
            if game.match.phase == .results {
                Text("\(game.match.humanPoints) — \(game.match.aiPoints)").font(.system(size: 52, weight: .bold))
                Text("\(game.match.humanReturns) human returns · \(game.match.aiReturns) opponent returns")
                Text("Experimental · 8-second flights · Not ranked").font(.caption)
                if game.simulated { Text("Simulated controller run").font(.caption).foregroundStyle(.orange) }
            } else if game.match.phase == .paused {
                Text(game.pauseReason).multilineTextAlignment(.center)
            } else {
                Text("Astra sees screenshots and uses mouse controls. It can miss. Swing your AirPod or iPhone to return the ball.").multilineTextAlignment(.center)
                Text("60 seconds. Each miss gives the other player a point. Serves alternate. Highest score wins.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Experimental speed: both sides use 8-second flights. Separate from the Tennis leaderboard.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text(game.status).font(.caption)
            MotionButton(game.match.phase == .paused ? "Resume match" : game.match.phase == .results ? "Rematch" : "Start challenge") {
                if game.match.phase == .paused { tennis.resume() }
                else { game.start(playerName: players.player?.nickname ?? "Guest", simulated: motion.activeInputSimulated, playerID: players.player?.id) }
            }.buttonStyle(WiiButtonStyle(primary: true)).disabled(!game.connected || !tennis.liveReady || game.status.hasPrefix("Unavailable") || game.status.hasSuffix("budget reached"))
            HStack {
                MotionButton("Controller setup", action: setup)
                MotionButton("Reconnect arena") { game.connect(manual: game.manual) }
                MotionButton("Back") { tennis.leave() }
            }.buttonStyle(WiiButtonStyle())
            if game.match.phase == .results {
                MotionButton("Next player") { tennis.leave(); players.nextPlayer() }.buttonStyle(WiiButtonStyle())
            }
            if game.match.phase == .menu {
                MotionButton(game.manual ? "Use Astra" : "Manual opponent rehearsal") { game.connect(manual: !game.manual) }.buttonStyle(.plain).font(.caption)
                if game.manual, let url = game.manualURL {
                    MotionButton("Open opponent controls") { NSWorkspace.shared.open(url) }.buttonStyle(WiiButtonStyle())
                }
            }
        }.padding(30).frame(width: 550).wiiPanel()
    }
}
