import SwiftUI
import AppKit

struct PlayerChannelView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false
    @State private var mode = "Arcade"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Climb the leaderboard", systemImage: "trophy.fill").font(WiiTheme.display(30))
                        Text("Scan. Swing. Set the score to beat.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(players.player == nil ? "Scan hacker badge" : players.player!.nickname) { players.showingSignIn = true }
                        .buttonStyle(WiiButtonStyle(primary: true)).disabled(!players.profilesAvailable)
                    if players.player != nil { Button("Guest") { players.selectGuest() }.buttonStyle(WiiButtonStyle()) }
                }
                if !players.profilesAvailable {
                    Label("Badge station is offline. Guest play and this Mac’s records still work.", systemImage: "wifi.slash")
                        .font(.callout).foregroundStyle(.secondary)
                } else if players.player == nil {
                    Text("Scan your badge to keep your personal scores. Choose to join the public board when you confirm your nickname.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Picker("Leaderboard", selection: $mode) {
                    Text("Neon Rush · Arcade").tag("Arcade")
                    Text("Neon Rush · Chill").tag("Chill")
                    Text("Tennis").tag("Tennis")
                }.pickerStyle(.segmented)
                if let standing = players.standings[mode] {
                    HStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(standing.rank.map { "#\($0)" } ?? (standing.isPublic ? "Unranked" : "Private"))
                                .font(WiiTheme.display(36)).foregroundStyle(WiiTheme.accentDeep)
                            Text(standing.personalBest.map { "Personal best \($0.formatted())" } ?? "Your first score starts here")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(standing.challenge).font(WiiTheme.display(16, .semibold))
                            if let next = standing.next, standing.personalBest != nil {
                                Text("\(next.pointsNeeded.formatted()) points above your best to take that spot.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Play again", action: play).buttonStyle(WiiButtonStyle(primary: true))
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("HALL OF FAME").font(WiiTheme.display(13)).tracking(2)
                        Spacer()
                        Text("\(players.leaderboards[mode]?.totalPlayers ?? 0) ranked players").font(.caption).foregroundStyle(.secondary)
                    }.padding(18)
                    Divider()
                    if let board = players.leaderboards[mode], !board.rows.isEmpty {
                        ForEach(Array(board.rows.prefix(12))) { row in
                            HStack(spacing: 16) {
                                Text("#\(row.rank)").font(WiiTheme.display(20)).foregroundStyle(row.rank <= 3 ? WiiTheme.accentDeep : WiiTheme.inkSoft).frame(width: 58)
                                Text(row.nickname).font(WiiTheme.display(17, .semibold)).lineLimit(1)
                                if row.rank == players.standings[mode]?.rank { Text("YOU").font(.caption.bold()).foregroundStyle(WiiTheme.accentDeep) }
                                Spacer()
                                Text("\(row.accuracy)% accuracy").font(.caption).foregroundStyle(.secondary)
                                Text(row.score.formatted()).font(WiiTheme.display(23)).monospacedDigit().frame(minWidth: 90, alignment: .trailing)
                            }.padding(.horizontal, 20).padding(.vertical, 12)
                                .background(row.rank == players.standings[mode]?.rank ? WiiTheme.accent.opacity(0.1) : Color.clear)
                            Divider()
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "flag.checkered").font(.system(size: 34)).foregroundStyle(WiiTheme.accentDeep)
                            Text(players.leaderboardStatus[mode] ?? "Loading leaderboard…").foregroundStyle(.secondary)
                            Button("Play a round", action: play).buttonStyle(WiiButtonStyle(primary: true))
                        }.padding(30).frame(maxWidth: .infinity)
                    }
                    HStack {
                        Text(players.leaderboardStatus[mode] ?? "").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") { players.refreshLeaderboard(mode) }.buttonStyle(.plain)
                        Button("Open score display") { NSWorkspace.shared.open(players.leaderboardURL(for: mode)) }.buttonStyle(.plain).disabled(!players.profilesAvailable)
                    }.padding(18)
                }.wiiPanel()
                HStack(spacing: 28) {
                    Label("This Mac", systemImage: "desktopcomputer").font(.headline)
                    Text("Neon Rush · \(motion.game.difficulty.rawValue): \(motion.game.bestScore.formatted())")
                    Text("Tennis: \(motion.tennis.bestScore.formatted())")
                    Spacer()
                }.font(.callout).foregroundStyle(.secondary)
                Text("One best score per player per game. Earlier scores win ties. Demo runs never enter the board.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.foregroundStyle(WiiTheme.ink)
            .task(id: mode + (players.player?.id ?? "guest")) {
                while !Task.isCancelled {
                    players.refreshLeaderboard(mode)
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                }
            }
            .sheet(isPresented: $players.showingSignIn, onDismiss: {
                if restoreCamera && motion.useCamera { motion.startCamera() }
                restoreCamera = false
                players.refreshLeaderboard(mode)
            }) { BadgeSignInView(players: players) }
            .onChange(of: players.showingSignIn) {
                if players.showingSignIn { restoreCamera = motion.camera.running; motion.camera.stop() }
            }
    }
    private func play() {
        if mode != "Tennis" { motion.game.difficulty = mode == "Chill" ? .chill : .arcade; motion.game.refreshBest() }
        NotificationCenter.default.post(name: .wiiRouteRequest, object: mode == "Tennis" ? Route.tennis : Route.neonRush)
    }
}

struct RankProgressCard: View {
    @ObservedObject var players: PlayerSession
    let runID: String?
    var body: some View {
        if let progress = players.lastRankProgress, progress.runID == runID, progress.playerID == players.player?.id {
            HStack(spacing: 16) {
                Image(systemName: progress.placesClimbed > 0 ? "arrow.up.right" : "trophy.fill").font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.headline).font(WiiTheme.display(20))
                    Text(progress.standing.challenge).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let rank = progress.standing.rank { Text("#\(rank)").font(WiiTheme.display(32)) }
            }.foregroundStyle(WiiTheme.accentDeep).padding(16)
                .background(WiiTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
        }
    }
}

struct ArcadeSettingsView: View {
    @ObservedObject var motion: MotionModel
    var open: (Route) -> Void
    @State private var menuSound = WiiAudio.shared.enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Make it your arcade", systemImage: "slider.horizontal.3")
                    .font(WiiTheme.display(34)).foregroundStyle(WiiTheme.accentDeep)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sound").font(WiiTheme.display(22))
                    Toggle("Menu sounds", isOn: $menuSound)
                        .onChange(of: menuSound) {
                            WiiAudio.shared.enabled = menuSound
                            if !menuSound { WiiAudio.shared.stopMusic() }
                        }
                    Toggle("Neon Rush effects", isOn: $motion.game.sound)
                    Toggle("Tennis effects", isOn: $motion.tennis.sound)
                    Toggle("Practice effects", isOn: $motion.arena.sound)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Menu pointer").font(WiiTheme.display(22))
                    Picker("Point with", selection: Binding(get: { motion.controllers.menuDevice }, set: { motion.controllers.selectMenu($0) })) {
                        Text(motion.controllers.name(for: .airPod)).tag(ControllerDevice.airPod)
                        Text("iPhone").tag(ControllerDevice.phone)
                    }.pickerStyle(.segmented)
                    Text("Point to a channel and give a quick flick to open it. You can always use your mouse.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Recenter pointer") { motion.controllers.recenter(motion.controllers.menuDevice) }
                        Button("Controller setup") { open(.controller) }
                    }.buttonStyle(WiiButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                HStack {
                    Button("Practice arena") { open(.lab) }
                    Button("Scripted game tests") { open(.scripts) }
                    Button("Open diagnostics") { motion.revealLogs() }
                }.buttonStyle(WiiButtonStyle())
            }.padding(32).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }.foregroundStyle(WiiTheme.ink)
    }
}
