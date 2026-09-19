import SwiftUI
import AppKit

struct PlayerChannelView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Players & scores", systemImage: "person.crop.circle")
                    .font(WiiTheme.display(34)).foregroundStyle(WiiTheme.accentDeep)
                VStack(alignment: .leading, spacing: 14) {
                    Text(players.player?.nickname ?? "Guest player").font(WiiTheme.display(24))
                    Text("Jump into any game. Guest records stay on this Mac; a badge profile carries your scores between visits.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(players.player == nil ? "Sign in with a badge" : "Edit player profile") { players.showingSignIn = true }
                            .buttonStyle(WiiButtonStyle(primary: true)).disabled(!players.profilesAvailable)
                        if players.player != nil {
                            Button("Play as guest") { players.selectGuest() }.buttonStyle(WiiButtonStyle())
                        }
                    }
                    if !players.profilesAvailable {
                        Text("Badge profiles are offline. You can still play and set records on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(24).wiiPanel()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Best on this Mac").font(WiiTheme.display(22))
                    HStack(spacing: 50) {
                        record("Neon Rush · \(motion.game.difficulty.rawValue)", score: motion.game.bestScore)
                        record("Tennis", score: motion.tennis.bestScore)
                    }
                    Text("Demo and scripted runs don’t count toward records.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
                if players.profilesAvailable {
                    HStack {
                        Button("View leaderboard") { NSWorkspace.shared.open(players.leaderboardURL) }.buttonStyle(WiiButtonStyle())
                        if !players.saveStatus.isEmpty { Text(players.saveStatus).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.padding(32).frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
        }.foregroundStyle(WiiTheme.ink)
            .sheet(isPresented: $players.showingSignIn, onDismiss: {
                if restoreCamera && motion.useCamera { motion.startCamera() }
                restoreCamera = false
            }) { BadgeSignInView(players: players) }
            .onChange(of: players.showingSignIn) {
                if players.showingSignIn { restoreCamera = motion.camera.running; motion.camera.stop() }
            }
    }

    private func record(_ title: String, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(WiiTheme.display(14, .semibold)).foregroundStyle(.secondary)
            Text(score.formatted()).font(WiiTheme.display(36)).monospacedDigit()
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
                }.padding(24).wiiPanel()
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
                }.padding(24).wiiPanel()
                HStack {
                    Button("Practice arena") { open(.lab) }
                    Button("Scripted game tests") { open(.scripts) }
                    Button("Open diagnostics") { motion.revealLogs() }
                }.buttonStyle(WiiButtonStyle())
            }.padding(32).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }.foregroundStyle(WiiTheme.ink)
    }
}
