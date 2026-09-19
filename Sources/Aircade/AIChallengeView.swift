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
                        Text("\((game.exhibition ? "Jev" : game.playerName))  \(game.match.humanPoints) : \(game.match.aiPoints)  \(game.manual ? "Manual" : game.opponentName)").font(.title.bold())
                        Text("\(game.exhibition ? "AI EXHIBITION" : game.provider == "jev" ? "STATE CONTROL" : "SCREEN CONTROL") · 8-SECOND FLIGHTS").font(.caption.bold())
                    }.wiiReadout()
                    Spacer()
                    Text("\(Int(ceil(game.match.remaining)))s").font(.largeTitle.monospacedDigit()).wiiReadout()
                    MotionButton { game.pause("Take a breath.") } label: { Image(systemName: "pause.fill") }.buttonStyle(WiiButtonStyle())
                }.foregroundStyle(.white)
                Spacer()
                HStack(alignment: .bottom) {
                    if let partner = game.partner {
                        VStack(alignment: .leading) {
                            Text("JEV · STATE CONTROL").font(.headline)
                            Text(partner.status)
                            Text("\(partner.latencyMS) ms · \(game.match.humanReturns) returns")
                            Text(partner.lastAction).font(.caption)
                        }.padding(16).frame(width: 250).wiiPanel()
                    }
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
        VStack(spacing: 12) {
            Text(game.match.phase == .results ? game.winner : game.match.phase == .paused ? "Match paused" : "Choose your opponent").font(.largeTitle.bold())
            if game.match.phase == .results {
                Text("\(game.match.humanPoints) — \(game.match.aiPoints)").font(.system(size: 52, weight: .bold))
                Text("\(game.match.humanReturns) \(game.exhibition ? "Jev" : "human") returns · \(game.match.aiReturns) opponent returns")
                Text(game.scoreMessage).font(.caption)
                if game.simulated { Text("Simulated controller run").font(.caption).foregroundStyle(.orange) }
            } else if game.match.phase == .paused {
                Text(game.pauseReason).multilineTextAlignment(.center)
            } else {
                Text(game.exhibition ? "Watch Astra and Jev operate independent rackets. Different observation interfaces; this is an exhibition, not a model intelligence ranking." : "\(game.opponentName) controls its own racket. It can miss. Swing your AirPod or iPhone to return the ball.").multilineTextAlignment(.center)
                Text("60 seconds. Each miss gives the other player a point. Serves alternate. Highest score wins.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Both sides use 8-second flights. Badge scores rank separately by model on this Mac.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if game.match.phase == .menu {
                HStack {
                    MotionButton("Astra · screen") { game.connect(provider: "astra") }
                    MotionButton("Jev · state") { game.connect(provider: "jev") }
                    MotionButton("GLM · tactical") { tennis.leave() }
                }.buttonStyle(WiiButtonStyle())
                Text("Astra sees images. Jev receives measured positions. GLM's rally mode uses assisted interception.").font(.caption).multilineTextAlignment(.center)
                MotionButton("Watch Astra vs Jev") { game.connect(provider: "astra", exhibition: true) }.buttonStyle(WiiButtonStyle())
            }
            Text(game.status).font(.caption)
            MotionButton(game.match.phase == .paused ? "Resume match" : game.match.phase == .results ? "Rematch" : "Start challenge") {
                if game.match.phase == .paused { tennis.resume() }
                else { game.start(playerName: players.player?.nickname ?? "Guest", simulated: motion.activeInputSimulated, playerID: players.player?.id, publicProfile: players.player?.isPublic ?? false) }
            }.buttonStyle(WiiButtonStyle(primary: true)).disabled(!game.readyToStart || (!game.exhibition && !tennis.liveReady))
            HStack {
                MotionButton("Controller setup", action: setup)
                MotionButton("Reconnect arena") { game.connect(manual: game.manual, provider: game.provider, exhibition: game.exhibition) }
                MotionButton("Back") { tennis.leave() }
            }.buttonStyle(WiiButtonStyle())
            if game.match.phase == .results {
                AIChallengeBoard(scores: game.scores, provider: game.provider, playerID: game.playerID)
                MotionButton("Next player") { tennis.leave(); players.nextPlayer() }.buttonStyle(WiiButtonStyle())
            }
            if game.match.phase == .menu && !game.exhibition {
                MotionButton(game.manual ? "Use Astra" : "Manual opponent rehearsal") { game.connect(manual: !game.manual) }.buttonStyle(.plain).font(.caption)
                if game.manual, let url = game.manualURL {
                    MotionButton("Open opponent controls") { NSWorkspace.shared.open(url) }.buttonStyle(WiiButtonStyle())
                }
            }
        }.padding(24).frame(width: 590).wiiPanel()
    }
}

private struct AIChallengeBoard: View {
    @ObservedObject var scores: AIChallengeScores
    let provider: String
    let playerID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(provider.uppercased()) · THIS MAC · 8-SECOND FLIGHTS").font(.caption.bold())
            if let index = scores.leaders(provider: provider).firstIndex(where: { $0.playerID == playerID }) { Text("Your badge ranks #\(index + 1)").font(.headline) }
            ForEach(Array(scores.leaders(provider: provider).prefix(3).enumerated()), id: \.element.id) { index, row in
                Text("#\(index + 1)  \(row.nickname)   \(row.human)–\(row.opponent)")
            }
            if scores.leaders(provider: provider).isEmpty { Text("Complete an uninterrupted badge run to set the first score.").font(.caption) }
            if let error = scores.error { Text(error).foregroundStyle(.orange).font(.caption) }
        }
    }
}
