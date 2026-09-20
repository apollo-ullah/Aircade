import SwiftUI

struct BadgeSignInView: View {
    @ObservedObject var players: PlayerSession
    var runPrompt = false
    var onReady: (() -> Void)? = nil
    @StateObject private var scanner = HandTracker()
    @State private var code = ""
    @State private var nickname = ""
    @State private var isPublic = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let player = players.player { profile(player) }
            else { scannerContent }
        }
        .frame(width: players.player == nil ? 820 : 680)
        .background(WiiTheme.stage)
        .preferredColorScheme(.light)
        .onAppear(perform: prepareScanner)
        .onChange(of: scanner.selectedID) {
            if scanner.running { scanner.start() }
        }
        .onChange(of: players.player?.id) {
            nickname = players.suggestedName ?? players.player?.nickname ?? ""
            isPublic = players.player?.isPublic ?? false
            if players.player != nil { scanner.stop(); code = "" }
        }
        .onDisappear { scanner.stop(); scanner.onBadge = nil; code = "" }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: players.player == nil ? "qrcode.viewfinder" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(WiiTheme.accentFill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(runPrompt ? (players.player == nil ? "Scan your badge for this rally" : "Who’s playing this rally?") : (players.player == nil ? "Scan your hacker badge" : "Your player profile"))
                    .font(WiiTheme.display(24))
                Text(players.player == nil ? "Put this score on the shared leaderboard." : "Confirm the player before starting.")
                    .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            }
            Spacer()
            Button {
                players.showingSignIn = false
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(WiiButtonStyle())
            .disabled(players.busy)
        }
        .padding(.horizontal, 26).padding(.vertical, 20)
    }

    private var scannerContent: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    HandPreview(tracker: scanner).frame(height: 300)
                    Label(scanner.running ? "LIVE SCANNER" : "CAMERA", systemImage: scanner.running ? "dot.radiowaves.left.and.right" : "video.slash")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(scanner.running ? .white : WiiTheme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(scanner.running ? AnyShapeStyle(WiiTheme.accentDeep) : AnyShapeStyle(.white.opacity(0.9)), in: Capsule())
                        .padding(12)
                }
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(scanner.running ? WiiTheme.accent : WiiTheme.hairline, lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                if scanner.devices.count > 1 {
                    Picker("Camera", selection: $scanner.selectedID) {
                        ForEach(scanner.devices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 8) {
                    Circle().fill(scanner.running ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(scanner.status).font(WiiTheme.body(12, .semibold)).foregroundStyle(WiiTheme.inkSoft)
                    Spacer()
                    if !scanner.running {
                        Button("Retry camera") { scanner.start() }.buttonStyle(.plain)
                            .font(WiiTheme.body(12, .semibold)).foregroundStyle(WiiTheme.accentDeep)
                    }
                }
            }
            .frame(width: 450)

            VStack(alignment: .leading, spacing: 14) {
                instruction(number: "1", title: "Hold up your badge",
                            detail: "Place the QR code inside the camera frame. Recognition happens automatically.")
                instruction(number: "2", title: "Confirm your name",
                            detail: "Returning players keep their profile. New players choose a nickname once.")

                Divider().padding(.vertical, 2)
                Text("ENTER A CODE INSTEAD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(WiiTheme.accentDeep)
                SecureField("Paste badge code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { players.signIn(code) }
                Button("Use badge code") { players.signIn(code) }
                    .buttonStyle(WiiButtonStyle(primary: !code.isEmpty))
                    .disabled(players.busy || code.isEmpty)

                if players.busy { ProgressView("Finding your profile…").controlSize(.small) }
                Text(players.message).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if runPrompt { guestAction }
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        }
        .padding(26)
    }

    private func profile(_ player: BadgePlayer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Badge recognized").font(WiiTheme.display(17))
                    Text(player.nickname).font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
                }
                Spacer()
                if runPrompt, player.needsName != true, players.suggestedName == nil {
                    Button("Play as \(player.nickname)") {
                        onReady?()
                        players.showingSignIn = false
                    }
                    .buttonStyle(WiiButtonStyle(primary: true))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR HIGH SCORES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(WiiTheme.accentDeep)
                HStack(spacing: 28) {
                    profileBest("Arcade", players.bests["Arcade"])
                    profileBest("Chill", players.bests["Chill"])
                    profileBest("Tennis", players.bests["Tennis"])
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).wiiPanel(radius: 18)

            if players.suggestedName != nil {
                Text("We read this name from your badge. Confirm the spelling before playing.")
                    .font(WiiTheme.body(12, .semibold)).foregroundStyle(WiiTheme.accentDeep)
            }
            TextField("Name or nickname (2–24 characters)", text: $nickname).textFieldStyle(.roundedBorder)
            Toggle("Show my nickname and scores on the public leaderboard", isOn: $isPublic)
            Text("Only your confirmed nickname and opted-in results are public. The badge QR value is never displayed.")
                .font(.caption).foregroundStyle(WiiTheme.inkSoft)
            Button(runPrompt ? "Save profile & start rally" : "Save profile") {
                players.saveProfile(nickname: nickname, isPublic: isPublic, completion: { onReady?() })
            }
            .buttonStyle(WiiButtonStyle(primary: true))
            .disabled(players.busy || nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || nickname.count > 24)

            HStack {
                Button("Scan a different badge") {
                    players.player = nil; players.suggestedName = nil; code = ""
                    scanner.start()
                }
                .buttonStyle(.plain).foregroundStyle(WiiTheme.accentDeep)
                Spacer()
                if runPrompt { guestAction }
            }
            if players.busy { ProgressView().controlSize(.small) }
            Text(players.message).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
        }
        .padding(26)
    }

    private var guestAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onReady?()
                players.selectGuest()
            } label: {
                Label("Skip · play as guest", systemImage: "person.crop.circle.badge.xmark")
            }
            .buttonStyle(WiiButtonStyle())
            Text("Guest scores stay on this Mac.").font(.caption).foregroundStyle(WiiTheme.inkSoft)
        }
    }

    private func instruction(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(WiiTheme.display(12)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(WiiTheme.accentDeep, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(WiiTheme.display(14))
                Text(detail).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prepareScanner() {
        scanner.scanBadges = true
        scanner.status = "Starting badge scanner…"
        scanner.onBadge = { value, name in
            guard !players.busy, players.player == nil else { return }
            scanner.stop(); code = ""; players.signIn(value, suggestedName: name)
        }
        nickname = players.suggestedName ?? players.player?.nickname ?? ""
        isPublic = players.player?.isPublic ?? false
        if players.player == nil { scanner.start() }
    }

    private func profileBest(_ difficulty: String, _ score: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(difficulty.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(score.map { $0.formatted() } ?? "—").font(.title2.bold()).monospacedDigit()
        }.frame(minWidth: 110, alignment: .leading)
    }
}
