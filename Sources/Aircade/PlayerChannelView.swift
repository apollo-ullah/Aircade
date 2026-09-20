import SwiftUI

struct PlayerChannelView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false
    private var mode: String { players.leaderboardMode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Climb the leaderboard", systemImage: "trophy.fill").font(WiiTheme.display(30))
                        Text("Scan. Swing. Set the score to beat.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    MotionButton(players.player == nil ? "Scan hacker badge" : players.player!.nickname) { players.showingSignIn = true }
                        .buttonStyle(WiiButtonStyle(primary: true)).disabled(!players.profilesAvailable)
                    if players.player != nil { MotionButton("Guest") { players.selectGuest() }.buttonStyle(WiiButtonStyle()) }
                }
                if !players.profilesAvailable {
                    Label("Badge station is offline. Guest play and this Mac’s records still work.", systemImage: "wifi.slash")
                        .font(.callout).foregroundStyle(.secondary)
                } else if players.player == nil {
                    Text("Scan your badge to keep your personal scores. Choose to join the public board when you confirm your nickname.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    ForEach(["Arcade", "Chill", "Tennis"], id: \.self) { board in
                        MotionButton(board == "Tennis" ? board : "Neon Rush · \(board)") { players.selectLeaderboard(board) }
                            .buttonStyle(WiiButtonStyle(primary: mode == board))
                    }
                }
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
                        MotionButton("Play again", action: play).buttonStyle(WiiButtonStyle(primary: true))
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
                            MotionButton("Play a round", action: play).buttonStyle(WiiButtonStyle(primary: true))
                        }.padding(30).frame(maxWidth: .infinity)
                    }
                    HStack {
                        Text(players.leaderboardStatus[mode] ?? "").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        MotionButton("Refresh") { players.refreshLeaderboard(mode) }.buttonStyle(.plain)
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
    @ObservedObject private var audioOutput = AudioOutput.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Make it your arcade", systemImage: "slider.horizontal.3")
                    .font(WiiTheme.display(34)).foregroundStyle(WiiTheme.accentDeep)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sound").font(WiiTheme.display(22))
                    HStack {
                        Text("Audio output")
                        ForEach(AudioOutputPreference.allCases) { preference in
                            MotionButton(preference.title) { audioOutput.select(preference) }
                                .buttonStyle(WiiButtonStyle(primary: audioOutput.preference == preference))
                        }
                    }
                    HStack {
                        Label(audioOutput.status, systemImage: "speaker.wave.2.fill").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        MotionButton("Test sound") { audioOutput.refresh(); GameAudio.shared.play("Glass") }
                            .buttonStyle(WiiButtonStyle())
                    }
                    Text("Music and effects use this output. Your AirPods stay connected as controllers.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Menu music and sounds", isOn: $menuSound).controllerAction { menuSound.toggle() }
                        .onChange(of: menuSound) {
                            WiiAudio.shared.enabled = menuSound
                            if !menuSound { WiiAudio.shared.stopMusic() }
                        }
                    Toggle("Neon Rush effects", isOn: $motion.game.sound).controllerAction { motion.game.sound.toggle() }
                    Toggle("Tennis effects", isOn: $motion.tennis.sound).controllerAction { motion.tennis.sound.toggle() }
                    Toggle("Practice effects", isOn: $motion.arena.sound).controllerAction { motion.arena.sound.toggle() }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Menu pointer").font(WiiTheme.display(22))
                    HStack {
                        Text("Point with")
                        ForEach(ControllerDevice.allCases) { device in
                            MotionButton(motion.controllers.name(for: device)) { motion.controllers.selectMenu(device) }
                                .buttonStyle(WiiButtonStyle(primary: motion.controllers.menuDevice == device))
                        }
                    }
                    Text("Lean left/right to move sideways. Tip toward the screen to move down; away to move up. Hold over a button for one second until the ring fills. Move away before selecting it again.")
                        .foregroundStyle(.secondary)
                    HStack {
                        MotionButton("Recenter pointer") { motion.controllers.recenter(motion.controllers.menuDevice) }
                        MotionButton("Controller setup") { open(.controller) }
                    }.buttonStyle(WiiButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                HStack {
                    MotionButton("Practice arena") { open(.lab) }
                    MotionButton("Scripted game tests") { open(.scripts) }
                    MotionButton("Open diagnostics") { motion.revealLogs() }
                }.buttonStyle(WiiButtonStyle())
            }.padding(32).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }.foregroundStyle(WiiTheme.ink)
    }
}
