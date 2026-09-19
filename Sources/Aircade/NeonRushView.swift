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
                        }.foregroundStyle(game.feedbackGood ? rushLime : .red)
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
        .onChange(of: game.difficulty) { game.refreshBest() }
        .onChange(of: showingSetup) {
            if showingSetup { game.pause("Controller setup is open.") }
        }
    }

    private var ready: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Label("CHOOSE YOUR CHALLENGE", systemImage: "figure.fencing")
                    .font(WiiTheme.display(11, .bold)).tracking(2).foregroundStyle(rushLime)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("Neon").foregroundStyle(WiiTheme.ink)
                    Text("Rush").foregroundStyle(rushLime).italic()
                }.font(WiiTheme.display(50)).tracking(-3)
                Text("A little swing. A whole lot of play.")
                    .font(WiiTheme.display(18, .medium))
                Text("Slice the blocks. Dodge the red.\nFind your rhythm in a 60-second challenge.")
                    .font(WiiTheme.body(14)).foregroundStyle(.secondary).lineSpacing(4)
                HStack(spacing: 32) {
                    menuStat("60", "SECONDS")
                    menuStat("3", "ROUNDS")
                    menuStat("×4", "MAX COMBO")
                }.padding(.vertical, 7)
                Divider()
                Text("Pick your pace").font(WiiTheme.display(15, .semibold))
                HStack(spacing: 10) {
                    ForEach(RushDifficulty.allCases, id: \.self) { difficulty in
                        Button { game.difficulty = difficulty } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: difficulty == .chill ? "sun.max.fill" : "bolt.fill")
                                    Text(difficulty.rawValue)
                                    Spacer(minLength: 0)
                                    if game.difficulty == difficulty { Image(systemName: "checkmark.circle.fill") }
                                }.font(WiiTheme.display(15, .bold))
                                Text(difficulty == .chill ? "Find your flow" : "Turn up the challenge").font(WiiTheme.body(11))
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(game.difficulty == difficulty ? .white : WiiTheme.ink)
                                .background(game.difficulty == difficulty ? rushLime : Color.white, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(rushLime.opacity(0.35), lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }
                Button {
                    if game.inputReady { game.start(demo: motion.activeInputSimulated) }
                    else { showingSetup = true }
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill").font(.title2)
                        Text(game.inputReady ? (players.player == nil ? "Play as guest" : "Let’s play!") : "Connect your controller")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(WiiTheme.display(18)).padding(.vertical, 6)
                }.buttonStyle(WiiButtonStyle(primary: true))
                HStack {
                    Button("How to play") { showHowTo.toggle() }
                    Spacer()
                    Button { motion.start(demo: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { game.start(demo: true) }
                    } label: { Label("Watch demo", systemImage: "play.rectangle") }
                }.buttonStyle(.plain).font(WiiTheme.body(13, .medium)).foregroundStyle(rushLime)
            }.padding(24).frame(width: 430).wiiPanel()

            VStack(alignment: .trailing, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(Color.orange)
                    Text("Best on this Mac")
                    Text(game.bestScore.formatted()).fontWeight(.bold).foregroundStyle(rushLime)
                }.font(WiiTheme.body(14)).padding(14).wiiPanel()
                Spacer()
                if showHowTo { howToCard }
                else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Every swing counts.").font(WiiTheme.display(20))
                        rule("✦", "SLICE", "Green blocks build your combo.", Color(red: 0.24, green: 0.63, blue: 0.18))
                        rule("→", "FOLLOW", "Blue arrows show the cut direction.", rushLime)
                        rule("×", "AVOID", "Red hazards cost one energy.", .red)
                    }.padding(22).frame(width: 300).wiiPanel()
                }
                Button { showingSetup = true } label: {
                    ActiveControllerBadge(motion: motion, controllers: motion.controllers)
                        .padding(12).wiiPanel()
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func playerScores(_ player: BadgePlayer) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(rushLime)
                Text(player.nickname).fontWeight(.semibold).lineLimit(1)
            }
            Text("YOUR HIGH SCORES").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            HStack(spacing: 30) {
                scoreLabel("Arcade", players.bests["Arcade"])
                scoreLabel("Chill", players.bests["Chill"])
            }
            Text("Saved to your badge profile").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 14, design: .default)).padding(16).frame(width: 300, alignment: .leading).wiiPanel()
    }
    private func scoreLabel(_ difficulty: String, _ score: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(difficulty.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(score.map { $0.formatted() } ?? "—").font(.title3.bold()).monospacedDigit().foregroundStyle(rushLime)
        }
    }
    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FIND YOUR FLOW").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(rushLime)
            Text("1. Connect and calibrate in Controller setup.\n\n2. Wait for blocks to reach you, then sweep your blade through them.\n\n3. Cut in the arrow's direction. Keep your blade away from red × blocks.\n\n4. Five clean cuts increase your multiplier. A miss, wrong cut, or hazard breaks your combo.")
                .font(.callout).foregroundStyle(WiiTheme.ink.opacity(0.75))
            Button("Got it") { showHowTo = false }.buttonStyle(.bordered)
        }.padding(24).frame(maxWidth: 360).wiiPanel()
    }
    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(game.isDemo ? "DEMO SCORE" : "\(players.player?.nickname ?? "Player") · SCORE").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(game.state.score.formatted()).font(.system(size: 38, weight: .semibold)).monospacedDigit()
                    Text("×\(game.state.multiplier)").font(.system(size: 24, weight: .bold)).foregroundStyle(Color(red: 0.55, green: 0.88, blue: 1))
                }
                Text("\(game.state.combo) consecutive cuts").font(.system(size: 12))
            }.frame(width: 205, alignment: .leading).wiiReadout()
            Spacer()
            VStack(spacing: 4) {
                Text(game.state.roundName).font(.system(size: 12, weight: .semibold)).tracking(1)
                Text(String(format: "%d:%02d", Int(ceil(game.state.remaining)) / 60, Int(ceil(game.state.remaining)) % 60))
                    .font(.system(size: 34, weight: .medium)).monospacedDigit()
                ProgressView(value: game.state.remaining, total: 60).tint(.white).frame(width: 116)
            }.wiiReadout()
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 20) {
                    Text("ENERGY").font(.system(size: 12, weight: .semibold)).tracking(1)
                    Button { game.pause() } label: { Image(systemName: "pause.fill").padding(5) }
                        .buttonStyle(.plain).accessibilityLabel("Pause game")
                }
                HStack(spacing: 7) {
                    ForEach(0..<game.state.difficulty.lives, id: \.self) { i in
                        Circle().fill(i < game.state.lives ? Color(red: 0.56, green: 0.88, blue: 0.26) : .black.opacity(0.45))
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                            .frame(width: 18, height: 18)
                    }
                }
            }.wiiReadout()
        }.foregroundStyle(.white).padding(24)
            .allowsHitTesting(game.state.phase == .playing || game.state.phase == .countdown)
    }
    private var playFooter: some View {
        HStack(spacing: 16) {
            Text("Neon Rush").font(.system(size: 17, weight: .semibold)).italic()
            if game.isDemo { Text(motion.scriptedScenario == nil ? "DEMO · NO HIGH SCORE" : "SCRIPTED · NO HIGH SCORE").font(.system(size: 11, weight: .bold)).foregroundStyle(.yellow) }
            Spacer()
            if let script = motion.scriptedScenario {
                Button("Change test") { showingScripts = true }.buttonStyle(.bordered).help(script.rawValue)
            }
            ActiveControllerBadge(motion: motion, controllers: motion.controllers)
            Text("Ⓡ Recenter    ␣ Pause").font(.system(size: 13, weight: .medium))
            Button { game.sound.toggle() } label: { Image(systemName: game.sound ? "speaker.wave.2" : "speaker.slash") }
                .buttonStyle(.plain).accessibilityLabel(game.sound ? "Mute sound" : "Enable sound")
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
    }
    private var countdown: some View {
        VStack(spacing: 10) {
            Text("GET INTO POSITION").font(.system(size: 14, weight: .semibold)).tracking(2).foregroundStyle(.white)
            Text("\(max(1, Int(ceil(game.state.countdown))))").font(.system(size: 130, weight: .bold, design: .default)).italic().foregroundStyle(rushLime)
            Text("Sweep through the blocks. Avoid red.").foregroundStyle(.white)
        }.shadow(color: .black.opacity(0.6), radius: 2, y: 1).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.25)).allowsHitTesting(false)
    }
    private var pauseCard: some View {
        overlayCard {
            Text("Taking a break?").font(.system(size: 42, weight: .bold, design: .default)).italic()
            Text(game.pauseReason).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Label(game.inputReady ? "\(motion.activeControllerName) ready" : "Waiting for \(motion.activeControllerName)", systemImage: game.inputReady ? "checkmark.circle.fill" : "airpodspro")
                .foregroundStyle(game.inputReady ? rushLime : .orange).font(.callout)
            actionButton("Back to the game") { game.resume() }.disabled(!game.inputReady)
            HStack(spacing: 22) {
                Button("Controller setup") { showingSetup = true }
                Button("Scripted test") { showingScripts = true }
                Button("End run") { game.leave() }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
        }
    }
    private var results: some View {
        overlayCard {
            Text(game.state.completed ? "RUN COMPLETE" : "OUT OF ENERGY").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(rushLime)
            HStack(alignment: .center, spacing: 28) {
                Text(game.state.completed ? game.state.rank : "↻").font(.system(size: 90, weight: .bold, design: .default)).italic().foregroundStyle(rushLime)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.state.score.formatted()).font(.system(size: 54, weight: .bold, design: .default)).monospacedDigit()
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
            Text(players.saveStatus).font(.caption).foregroundStyle(.secondary)
            actionButton("Play again") { game.start(demo: motion.activeInputSimulated) }.disabled(!game.inputReady)
            HStack(spacing: 24) {
                Button("Back to Aircade") { NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.home) }
                Button("Next player") { game.leave(); players.nextPlayer() }
                Button("Leaderboard") { NSWorkspace.shared.open(players.leaderboardURL) }
                if motion.scriptedScenario != nil { Button("Change scripted test") { showingScripts = true } }
                if !game.inputReady { Button("Connect controller") { showingSetup = true } }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
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
    private func overlayCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            WiiTheme.accentDeep.opacity(0.22)
            VStack(spacing: 22, content: content).padding(38).frame(width: 600)
                .wiiPanel()
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(rushLime.opacity(0.15)))
        }
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.system(size: 13, weight: .bold, design: .monospaced)).padding(18)
                .foregroundStyle(.white).background(rushLime, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private var brand: some View { Text("aircade").foregroundStyle(WiiTheme.accentDeep).font(.system(size: 34, weight: .medium, design: .default)).tracking(-1).padding(.trailing, 12) }
    private var connectionPill: some View {
        ActiveControllerBadge(motion: motion, controllers: motion.controllers)
    }
    private func menuStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .bold, design: .default)).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
        }
    }
    private func rule(_ symbol: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Text(symbol).font(.system(size: 26, weight: .bold)).frame(width: 43, height: 43)
                .foregroundStyle(color).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
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
                Spacer(); Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ControllerSelectionPanel(motion: motion, controllers: motion.controllers, duel: motion.showingMultiplayer)
                    if motion.showingMultiplayer || motion.controllers.soloDevice == .airPod {
                    setupStep("01", "Connect your AirPods") {
                        Text("Turn off Automatic Ear Detection. Hold one earbud in a consistent grip.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(motion.running && !motion.simulated ? "Reconnect AirPods" : "Start AirPods") { motion.start() }.buttonStyle(.borderedProminent).tint(rushLime).foregroundStyle(.black)
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
                            Button(motion.calibrationButtonTitle) { motion.beginGripCalibration() }
                                .disabled(!motion.hasFreshMotion || motion.simulated)
                            Button("Recenter [R]") { motion.recenter() }.disabled(!motion.hasFreshMotion)
                        }
                    }
                    setupStep("03", "Add hand movement · optional") {
                        Toggle("Webcam hand position", isOn: $motion.useCamera)
                        Text("Move your hand sideways and up/down. AirPods still control blade angle.").font(.caption).foregroundStyle(.secondary)
                        if motion.useCamera {
                            Picker("Camera", selection: $camera.selectedID) { ForEach(camera.devices) { Text($0.name).tag($0.id) } }.disabled(camera.running)
                            HStack {
                                Button(camera.running ? "Restart camera" : "Start camera") { motion.startCamera() }
                                Button("Refresh") { camera.refreshDevices() }.disabled(camera.running)
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
                    Button("Open test lab & diagnostics") { done(); motion.showLab(true) }.buttonStyle(.plain).foregroundStyle(rushLime)
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
                    Button("Use \(motion.incomingSource) AirPod instead") { motion.adoptIncomingSource() }
                }
            }
        }.foregroundStyle(motion.sourceMismatch ? Color.orange : Color(red: 0.35, green: 0.93, blue: 0.91))
    }
}
