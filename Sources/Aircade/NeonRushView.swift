import SwiftUI
import MotionCore

private let rushLime = WiiTheme.accentDeep
private let rushCream = WiiTheme.ink

struct NeonRushView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var game: ArcadeGame
    @ObservedObject var players: PlayerSession
    @State private var restoreCamera = false
    @State private var showingSetup = false
    @State private var showHowTo = false
    @State private var showingScripts = false

    var body: some View {
        ZStack {
            SaberView(controller: motion.scene).ignoresSafeArea()
            if game.state.phase == .menu { ready }
            else {
                VStack(spacing: 0) {
                    hud
                    Spacer()
                    if !game.feedback.isEmpty && game.state.phase == .playing {
                        VStack(spacing: 5) {
                            Text(game.feedback).font(.system(size: 23, weight: .bold, design: .default)).italic()
                            if game.feedbackPoints > 0 { Text("+\(game.feedbackPoints)").font(.system(size: 32, weight: .bold, design: .default)) }
                        }.foregroundStyle(game.feedbackGood ? .white : .yellow).shadow(color: .black.opacity(0.8), radius: 4, y: 2)
                            .padding(.bottom, 34).allowsHitTesting(false)
                    }
                    playFooter
                }
                if game.state.phase == .countdown { countdown }
                if game.state.phase == .paused { pauseCard }
                if game.state.phase == .results { results }
            }
        }
        .foregroundStyle(rushCream)
        .background(WiiTheme.stageMid).tint(rushLime)
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
        .sheet(isPresented: $showingSetup) {
            ControllerSetupView(motion: motion, done: { showingSetup = false })
        }
        .sheet(isPresented: $showingScripts) {
            ScriptedControllerSetup(motion: motion, done: { showingScripts = false })
        }
        .onChange(of: showingScripts) {
            if showingScripts { game.pause("Scripted test setup is open.") }
        }
        .onAppear { players.refreshLeaderboard(game.difficulty.rawValue) }
        .onChange(of: game.difficulty) { game.refreshBest(); players.refreshLeaderboard(game.difficulty.rawValue) }
        .onChange(of: showingSetup) {
            if showingSetup { game.pause("Controller setup is open.") }
        }
    }

    private var ready: some View {
        GameLobby(identity: .rush) {
            HStack {
                GameMetric(value: "60", label: "SECONDS")
                GameMetric(value: "3", label: "ROUNDS")
                GameMetric(value: "×4", label: "MAX MULTIPLIER")
            }.padding(.vertical, 3)
            GameRule(symbol: "sparkle", title: "Slice green. Follow blue.",
                     detail: "Sweep through green blocks; cut blue arrows in their direction.", color: Color(red: 0.19, green: 0.52, blue: 0.37))
            GameRule(symbol: "xmark", title: "Keep clear of red",
                     detail: "Hazards and missed cuts cost energy and reset your combo.", color: Color(red: 0.76, green: 0.27, blue: 0.29))
        } options: {
            HStack {
                Text("Pick your pace").font(WiiTheme.display(22))
                Spacer(); Image(systemName: "bolt.fill").foregroundStyle(rushLime)
            }
            Text("Three rounds. One personal best to beat.")
                .font(WiiTheme.body(13)).foregroundStyle(WiiTheme.inkSoft)
            VStack(spacing: 10) {
                ForEach(RushDifficulty.allCases, id: \.self) { difficulty in
                    MotionButton { game.difficulty = difficulty } label: {
                        GameOption(title: difficulty.rawValue,
                                   detail: difficulty == .chill ? "7 energy · generous timing · any direction" : "5 energy · faster cuts · follow the arrows",
                                   symbol: difficulty == .chill ? "sun.max.fill" : "bolt.fill",
                                   selected: game.difficulty == difficulty)
                    }.buttonStyle(GameActionStyle())
                }
            }
            HStack(spacing: 6) {
                ForEach(["Ignite", "Flow", "Overdrive"], id: \.self) { round in
                    Text(round).font(WiiTheme.display(11, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(rushLime.opacity(0.07), in: Capsule())
                }
            }.foregroundStyle(rushLime).accessibilityLabel("Three rounds: Ignite, Flow, Overdrive")
            Divider()
            MotionButton { showingSetup = true } label: {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.inputReady ? "Controller ready" : "Connect a controller").font(WiiTheme.display(14))
                        Text(game.inputReady ? motion.activeControllerName : "AirPod or iPhone").font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.foregroundStyle(rushLime).padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain)
            MotionButton(id: "start-neon-rush") {
                if game.inputReady { game.start(demo: motion.activeInputSimulated) }
                else { showingSetup = true }
            } label: {
                GamePrimaryAction(title: game.inputReady ? "Let’s play" : "Connect & play", symbol: game.inputReady ? "play.fill" : "gamecontroller.fill")
            }.buttonStyle(GameActionStyle())
            HStack {
                MotionButton("How to play") { showHowTo = true }
                Spacer()
                MotionButton {
                    motion.start(demo: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { game.start(demo: true) }
                } label: { Label("Watch demo", systemImage: "play.rectangle") }
            }.buttonStyle(WiiButtonStyle())
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(rushLime)
                Text("Best  \((players.player == nil ? game.bestScore : players.bests[game.difficulty.rawValue, default: 0]).formatted())").font(WiiTheme.display(13))
                Spacer()
                Text(players.player?.nickname ?? "On this Mac").font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            }
            if let standing = players.standings[game.difficulty.rawValue] {
                Text(standing.challenge).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            }
        }
        .sheet(isPresented: $showHowTo) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Find your flow").font(WiiTheme.display(30))
                GameRule(symbol: "gamecontroller.fill", title: "01 · Get ready", detail: "Connect your controller, hold it upright, then press R to recenter.")
                GameRule(symbol: "sparkle", title: "02 · Wait, then sweep", detail: "Let blocks reach your blade before cutting. Green accepts any direction.")
                GameRule(symbol: "arrow.down", title: "03 · Follow the arrow", detail: "Cut blue blocks in the direction shown. Keep your blade away from red hazards.")
                GameRule(symbol: "bolt.fill", title: "04 · Build your multiplier", detail: "Every five consecutive cuts increases your multiplier, up to ×4.")
                MotionButton { showHowTo = false } label: { GamePrimaryAction(title: "Got it", symbol: "checkmark") }.buttonStyle(GameActionStyle())
            }.padding(32).frame(width: 510).background(WiiTheme.stage).foregroundStyle(WiiTheme.ink)
        }
    }
    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(game.isDemo ? "DEMO SCORE" : "\(players.player?.nickname ?? "Player") · SCORE").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(game.state.score.formatted()).font(WiiTheme.display(38)).monospacedDigit()
                    Text("×\(game.state.multiplier)").font(.system(size: 24, weight: .bold)).foregroundStyle(Color(red: 0.55, green: 0.88, blue: 1))
                }
                Text("\(game.state.combo) consecutive cuts").font(.system(size: 12))
            }.frame(width: 205, alignment: .leading).gameReadout()
            Spacer()
            VStack(spacing: 4) {
                Text(game.state.roundName).font(.system(size: 12, weight: .semibold)).tracking(1)
                Text(String(format: "%d:%02d", Int(ceil(game.state.remaining)) / 60, Int(ceil(game.state.remaining)) % 60))
                    .font(WiiTheme.display(34, .semibold)).monospacedDigit()
                HStack(spacing: 5) {
                    ForEach(0..<3) { round in
                        Capsule().fill(game.state.elapsed >= Double(round * 20) ? WiiTheme.accent : .white.opacity(0.2))
                            .frame(width: 35, height: 4)
                    }
                }.accessibilityLabel("Round \(min(3, Int(game.state.elapsed / 20) + 1)) of 3")
            }.gameReadout()
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 20) {
                    Text("ENERGY").font(.system(size: 12, weight: .semibold)).tracking(1)
                    MotionButton { game.pause() } label: { Image(systemName: "pause.fill").frame(width: 40, height: 36).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)) }
                        .buttonStyle(.plain).accessibilityLabel("Pause game")
                }
                HStack(spacing: 7) {
                    ForEach(0..<game.state.difficulty.lives, id: \.self) { i in
                        Circle().fill(i < game.state.lives ? Color(red: 0.56, green: 0.88, blue: 0.26) : .black.opacity(0.45))
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                            .frame(width: 18, height: 18)
                    }
                }
            }.gameReadout()
        }.foregroundStyle(.white).padding(24)
            .allowsHitTesting(game.state.phase == .playing || game.state.phase == .countdown)
    }
    private var playFooter: some View {
        HStack(spacing: 16) {
            Text("Neon Rush").font(WiiTheme.display(16))
            if game.isDemo { Text(motion.scriptedScenario == nil ? "DEMO · NO HIGH SCORE" : "SCRIPTED · NO HIGH SCORE").font(.system(size: 11, weight: .bold)).foregroundStyle(.yellow) }
            Spacer()
            if let script = motion.scriptedScenario {
                MotionButton("Change test") { showingScripts = true }.buttonStyle(.bordered).help(script.rawValue)
            }
            Label(motion.activeControllerName, systemImage: "gamecontroller.fill").font(WiiTheme.body(12, .semibold))
            Text("Ⓡ Recenter    ␣ Pause").font(.system(size: 13, weight: .medium))
            MotionButton { game.sound.toggle() } label: { Image(systemName: game.sound ? "speaker.wave.2" : "speaker.slash").frame(width: 36, height: 36) }
                .buttonStyle(.plain).accessibilityLabel(game.sound ? "Mute sound" : "Enable sound")
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }
    private var countdown: some View {
        GameCountdown(value: game.state.countdown, title: "FIND YOUR STARTING POSE", hint: "Sweep through the blocks. Keep clear of red.")
    }
    private var pauseCard: some View {
        overlayCard {
            Image(systemName: "pause.circle.fill").font(.system(size: 40)).foregroundStyle(rushLime)
            Text("Take a breather").font(WiiTheme.display(36))
            Text(game.pauseReason).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Label(game.inputReady ? "\(motion.activeControllerName) ready" : "Waiting for \(motion.activeControllerName)", systemImage: game.inputReady ? "checkmark.circle.fill" : "airpodspro")
                .foregroundStyle(game.inputReady ? rushLime : .orange).font(.callout)
            actionButton("Back to the game") { game.resume() }.disabled(!game.inputReady)
            HStack(spacing: 22) {
                MotionButton("Controller setup") { showingSetup = true }
                MotionButton("Scripted test") { showingScripts = true }
                MotionButton("End run") { game.leave() }
            }.buttonStyle(WiiButtonStyle())
        }
    }
    private var results: some View {
        overlayCard {
            Text(game.state.completed ? "RUN COMPLETE" : "OUT OF ENERGY").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(rushLime)
            HStack(alignment: .center, spacing: 28) {
                Text(game.state.completed ? game.state.rank : "↻").font(WiiTheme.display(78)).foregroundStyle(rushLime)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.state.score.formatted()).font(WiiTheme.display(52)).monospacedDigit()
                    Text(resultScoreCaption)
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(game.newRecord ? rushLime : .secondary)
                }
            }
            HStack(spacing: 34) {
                menuStat("\(game.state.cuts)", "CUTS")
                menuStat("\(game.state.bestCombo)", "BEST COMBO")
                menuStat("\(game.state.accuracy)%", "ACCURACY")
            }.padding(.vertical, 6)
            Text(game.state.completed ? "You found your flow. Can you beat it?" : "Keep your cuts deliberate. The next run is yours.")
                .font(.callout).foregroundStyle(.secondary)
            RankProgressCard(players: players, runID: game.runID)
            Text(players.saveStatus).font(.caption).foregroundStyle(.secondary)
            actionButton("Play again") { game.start(demo: motion.activeInputSimulated) }.disabled(!game.inputReady)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MotionButton("Back to Aircade") { NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.home) }
                MotionButton("Next player") { game.leave(); players.nextPlayer() }
                MotionButton("Leaderboard") {
                    players.selectLeaderboard(game.state.difficulty.rawValue)
                    NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.profile)
                }
                if motion.scriptedScenario != nil { MotionButton("Change scripted test") { showingScripts = true } }
                if !game.inputReady { MotionButton("Connect controller") { showingSetup = true } }
            }.buttonStyle(WiiButtonStyle())
        }
    }
    private var resultScoreCaption: String {
        if game.isDemo {
            return motion.scriptedScenario == nil ? "DEMO RUN · SCORE NOT SAVED" : "SCRIPTED RUN · SCORE NOT SAVED"
        }
        if let best = players.bests[game.state.difficulty.rawValue] {
            return "\(game.state.difficulty.rawValue.uppercased()) · YOUR BEST \(best.formatted())"
        }
        return "\(game.state.difficulty.rawValue.uppercased()) · BEST ON THIS MAC \(game.bestScore.formatted())"
    }
    private func overlayCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GameOverlay(content: content)
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        MotionButton(action: action) { GamePrimaryAction(title: title) }.buttonStyle(GameActionStyle())
    }
    private func menuStat(_ value: String, _ label: String) -> some View {
        GameMetric(value: value, label: label)
    }

}

struct ControllerSetupView: View {
    @ObservedObject var motion: MotionModel
    var done: () -> Void
    var body: some View {
        ControllerSetupContent(motion: motion, camera: motion.camera, done: done)
            .sheet(isPresented: Binding(get: { motion.calibrationStep > 0 }, set: { showing in
                if !showing && motion.calibrationStep > 0 { motion.cancelGripCalibration() }
            })) { CalibrationSheet(motion: motion).interactiveDismissDisabled() }
    }
}
private struct ControllerSetupContent: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var camera: HandTracker
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("YOUR CONTROLLER").font(.system(size: 22, weight: .bold, design: .default))
                Spacer(); MotionButton("Done", action: done).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ControllerSelectionPanel(motion: motion, controllers: motion.controllers, duel: motion.showingMultiplayer)
                    if motion.showingMultiplayer || motion.controllers.soloDevice == .airPod {
                    setupStep("01", "Connect your AirPods") {
                        Text("Turn off Automatic Ear Detection. Hold one earbud in a consistent grip.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            MotionButton(motion.running && !motion.simulated ? "Reconnect AirPods" : "Start AirPods") { motion.start() }.buttonStyle(.borderedProminent).tint(rushLime).foregroundStyle(.black)
                            Text(motion.status).font(.caption)
                        }
                        if motion.running && !motion.simulated {
                            Text("Permission: \(motion.authorization) · \(motion.samples) samples · \(Int(motion.frequency)) Hz")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ControllerSourceStatus(motion: motion)
                        if motion.waitingForMotion {
                            Text("Bluetooth can be connected while the motion stream is idle. In Mac Bluetooth settings, disconnect and reconnect your AirPods, briefly wear them, then click Reconnect AirPods above. Keep Automatic Ear Detection off for handheld play.")
                                .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        } else if motion.samples > 0 && motion.hasFreshMotion && !motion.simulated {
                            Label("Receiving \(motion.source) AirPod motion. Recenter your grip, then press Done to play.", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(rushLime)
                        }
                    }
                    setupStep("02", "Calibrate and test your grip") {
                        Text(motion.hasGripCalibration ? "Grip saved for your \(motion.controllerName). Recalibrate if it has moved in your fingers." : "Follow the animated guide so left, right, and forward feel natural.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            MotionButton(motion.calibrationButtonTitle) { motion.beginGripCalibration() }
                                .disabled(!motion.hasFreshMotion || motion.simulated)
                            MotionButton("Recenter [R]") { motion.recenter() }.disabled(!motion.hasFreshMotion)
                        }
                    }
                    setupStep("03", "Add hand movement · optional") {
                        Toggle("Webcam hand position", isOn: $motion.useCamera)
                        Text("Move your hand sideways and up/down. AirPods still control blade angle.").font(.caption).foregroundStyle(.secondary)
                        if motion.useCamera {
                            Picker("Camera", selection: $camera.selectedID) { ForEach(camera.devices) { Text($0.name).tag($0.id) } }.disabled(camera.running)
                            HStack {
                                MotionButton(camera.running ? "Restart camera" : "Start camera") { motion.startCamera() }
                                MotionButton("Refresh") { camera.refreshDevices() }.disabled(camera.running)
                            }
                            HandPreview(tracker: camera)
                            Text(camera.status).font(.caption)
                            HStack {
                                Toggle("Mirror", isOn: $camera.mirrored).toggleStyle(.checkbox)
                                Picker("Hand", selection: $camera.handSelection) {
                                    Text("Right of preview").tag(0); Text("Left of preview").tag(1)
                                }
                            }
                            HStack { Text("Travel").font(.caption); Slider(value: $motion.cameraGain, in: 2...9) }
                        }
                    }
                    Text("Keep the earbud secure. Use comfortable wrist or forearm tilts. R recenters your grip; a tracking interruption pauses the game.").font(.caption).foregroundStyle(.secondary)
                    }
                    MotionButton("Open test lab & diagnostics") { done(); motion.showLab(true) }.buttonStyle(.plain).foregroundStyle(rushLime)
                }
            }
        }.padding(26).frame(width: 610, height: 690).background(WiiTheme.stageMid).preferredColorScheme(.light).tint(rushLime)
    }
    private func setupStep<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(number).foregroundStyle(rushLime).font(.system(size: 12, weight: .bold, design: .monospaced)); Text(title).font(.headline) }
            content()
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).wiiPanel()
    }
}

/// Shared source identity and explicit handover in both game setup and the lab.
struct ControllerSourceStatus: View {
    @ObservedObject var motion: MotionModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ControllerIdentityBadge(motion: motion, compact: false)
            if motion.sourceMismatch {
                Text("\(motion.controllerLabel). macOS changed the sensor. Hold the selected earbud, or explicitly choose the new one. Calibration restarts when you switch.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                if motion.canAdoptIncomingSource {
                    MotionButton("Use \(motion.incomingSource) AirPod instead") { motion.adoptIncomingSource() }
                }
            }
        }.foregroundStyle(motion.sourceMismatch ? Color.orange : WiiTheme.ink)
    }
}
