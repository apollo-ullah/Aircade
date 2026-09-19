import SwiftUI

struct BadgeSignInView: View {
    @ObservedObject var players: PlayerSession
    @StateObject private var scanner = HandTracker()
    @State private var code = ""
    @State private var nickname = ""
    @State private var isPublic = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(players.player == nil ? "Scan your badge" : "Your player profile").font(.title2.bold())
                Spacer()
                Button("Cancel") { players.showingSignIn = false }.disabled(players.busy)
            }
            if let player = players.player {
                Label("Badge recognized", systemImage: "checkmark.circle.fill").foregroundStyle(SportsTheme.green)
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR HIGH SCORES").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(SportsTheme.blue)
                    HStack(spacing: 36) {
                        profileBest("Arcade", players.bests["Arcade"])
                        profileBest("Chill", players.bests["Chill"])
                        profileBest("Tennis", players.bests["Tennis"])
                    }
                    Text("These scores are saved to this badge profile in MongoDB.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).sportsPanel()
                if players.suggestedName != nil { Text("Read from your badge — please confirm the spelling.").font(.caption).foregroundStyle(SportsTheme.blue) }
                TextField("Name or nickname (2–24 characters)", text: $nickname).textFieldStyle(.roundedBorder)
                Toggle("Show my nickname and scores on the public leaderboard", isOn: $isPublic)
                Text("Your badge QR is never shown publicly. Anyone viewing the leaderboard can see opted-in nicknames and results.").font(.caption).foregroundStyle(.secondary)
                Button("Save profile & return to game") { players.saveProfile(nickname: nickname, isPublic: isPublic) }
                    .buttonStyle(SportsButtonStyle(primary: true)).disabled(players.busy || nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || nickname.count > 24)
                Button("Scan a different badge") { players.player = nil; players.suggestedName = nil; code = "" }
                Text("Player ID: \(player.id.prefix(8))").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Show the QR code and the name beneath it. We’ll suggest your name for confirmation; returning players keep their saved name.")
                Picker("Camera", selection: $scanner.selectedID) { ForEach(scanner.devices) { Text($0.name).tag($0.id) } }.disabled(scanner.running)
                HandPreview(tracker: scanner).frame(height: 150)
                HStack {
                    Button("Start camera") { scanner.start() }.disabled(scanner.running || players.busy)
                    Button("Stop camera") { scanner.stop() }.disabled(!scanner.running)
                }
                Text(scanner.status).font(.caption).foregroundStyle(.secondary)
                Divider()
                SecureField("Or enter / paste badge code", text: $code).textFieldStyle(.roundedBorder)
                    .onSubmit { players.signIn(code) }
                Button("Use badge code") { players.signIn(code) }.disabled(players.busy || code.isEmpty)
                Text("The full QR text is treated as a private identifier, not opened as a link. Name recognition stays on this Mac; only the name you confirm is saved. No email is needed.").font(.caption).foregroundStyle(.secondary)
            }
            if players.busy { ProgressView().controlSize(.small) }
            Text(players.message).font(.callout).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 580).background(SportsTheme.paper).preferredColorScheme(.light)
            .onAppear {
                scanner.scanBadges = true
                scanner.status = "Camera off · ready to scan a badge"
                scanner.onBadge = { value, name in
                    guard !players.busy, players.player == nil else { return }
                    scanner.stop(); code = ""; players.signIn(value, suggestedName: name)
                }
                nickname = players.suggestedName ?? players.player?.nickname ?? ""; isPublic = players.player?.isPublic ?? false
            }
            .onChange(of: players.player?.id) {
                nickname = players.suggestedName ?? players.player?.nickname ?? ""; isPublic = players.player?.isPublic ?? false
                if players.player != nil { scanner.stop(); code = "" }
            }
            .onDisappear { scanner.stop(); scanner.onBadge = nil; code = "" }
    }

    private func profileBest(_ difficulty: String, _ score: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(difficulty.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(score.map { $0.formatted() } ?? "—").font(.title2.bold()).monospacedDigit()
        }.frame(minWidth: 110, alignment: .leading)
    }
}
