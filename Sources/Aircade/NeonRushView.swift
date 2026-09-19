import SwiftUI
import MotionCore

private let rushLime = Color(red: 0.76, green: 0.98, blue: 0.31)
private let rushCream = Color(red: 0.94, green: 0.95, blue: 0.88)

struct NeonRushView: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var game: ArcadeGame
    @State private var showingSetup = false
    @State private var showHowTo = false

    var body: some View {
        ZStack {
            SaberView(controller: motion.scene).ignoresSafeArea()
            if game.state.phase == .menu { menu }
            else {
                VStack(spacing: 0) {
                    hud
                    Spacer()
                    if !game.feedback.isEmpty && game.state.phase == .playing {
                        VStack(spacing: 5) {
                            Text(game.feedback).font(.system(size: 23, weight: .black, design: .rounded)).italic()
                            if game.feedbackPoints > 0 { Text("+\(game.feedbackPoints)").font(.system(size: 32, weight: .black, design: .rounded)) }
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
        .background(Color(red: 0.025, green: 0.035, blue: 0.045))
        .sheet(isPresented: $showingSetup) {
            ControllerSetupView(motion: motion, done: { showingSetup = false })
        }
        .onChange(of: game.difficulty) { game.refreshBest() }
        .onChange(of: showingSetup) {
            if showingSetup { game.pause("Controller setup is open.") }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                brand
                Text("THE POCKET ARCADE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.white.opacity(0.45))
                Spacer()
                connectionPill
                Button { showingSetup = true } label: { Label("Controller", systemImage: "airpodspro") }
                    .buttonStyle(.bordered).controlSize(.large)
            }.padding(.bottom, 22)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: geometry.size.height < 650 ? 12 : 16) {
                        HStack(spacing: 8) {
                            Circle().fill(rushLime).frame(width: 6, height: 6)
                            Text("GAME 01   /   SABER SURVIVAL").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                        }.foregroundStyle(rushLime)
                        Text("NEON\nRUSH.").font(.system(size: min(94, geometry.size.height * 0.14), weight: .black, design: .rounded))
                            .italic().tracking(-5).lineSpacing(-12).fixedSize(horizontal: false, vertical: true)
                        Text("Small controller. Big energy.").font(.system(size: 21, weight: .medium, design: .rounded))
                        Text("Slice the neon. Dodge the red.\nKeep your combo alive for 60 seconds.")
                            .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 18) {
                            menuStat("60", "SECONDS")
                            menuStat("03", "ROUNDS")
                            menuStat("×4", "MAX COMBO")
                        }.padding(.vertical, 7)
                        HStack(spacing: 8) {
                            ForEach(RushDifficulty.allCases, id: \.self) { difficulty in
                                Button { game.difficulty = difficulty } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(difficulty.rawValue.uppercased()).font(.system(size: 12, weight: .black, design: .monospaced))
                                        Text(difficulty == .chill ? "Room to find your flow" : "Arrows. Hazards. Faster.").font(.caption2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .foregroundStyle(game.difficulty == difficulty ? .black : rushCream)
                                        .background(game.difficulty == difficulty ? rushLime : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                        Button {
                            if game.inputReady { game.start(demo: motion.simulated) }
                            else { showingSetup = true }
                        } label: {
                            HStack {
                                Text(game.inputReady ? "LET'S PLAY" : "CONNECT YOUR CONTROLLER")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.font(.system(size: 14, weight: .black, design: .monospaced)).padding(18)
                                .foregroundStyle(.black).background(rushLime, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                        HStack {
                            Button("How to play") { showHowTo.toggle() }.buttonStyle(.plain)
                            Text("/").foregroundStyle(.secondary)
                            Button("Watch demo") {
                                motion.start(demo: true)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { game.start(demo: true) }
                            }.buttonStyle(.plain)
                            Spacer()
                            Text("BEST  \(game.bestScore.formatted())").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(rushLime)
                        }.font(.caption).foregroundStyle(.white.opacity(0.6))
                    }.frame(width: min(430, geometry.size.width * 0.45)).padding(28)
                        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 30)
                    VStack(alignment: .trailing) {
                        HStack(spacing: 6) {
                            Text(motion.simulated ? "SIMULATED CONTROLLER" : game.inputReady ? "YOUR SABER IS LIVE" : "YOUR AIRPODS. YOUR CONTROLLER.")
                                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                            Image(systemName: "arrow.down.left")
                        }.foregroundStyle(motion.simulated ? .orange : rushLime).padding(.top, 20)
                        Spacer()
                        if showHowTo { howToCard }
                        else {
                            VStack(alignment: .leading, spacing: 18) {
                                rule("✦", "SLICE", "Neon blocks build your combo.", rushLime)
                                rule("→", "FOLLOW", "Cyan arrows show the cut direction.", .cyan)
                                rule("×", "AVOID", "Red hazards cost one energy.", .red)
                            }.padding(22).background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: 335)
                        }
                    }.padding(.vertical, 20)
                }
            }
            HStack(spacing: 12) {
                Label(game.inputReady ? "Controller ready" : "Start AirPods in Controller setup", systemImage: game.inputReady ? "checkmark.circle.fill" : "circle")
                Text("·")
                Text("R to recenter")
                Spacer()
                Button("Open test lab") { motion.showLab(true) }.buttonStyle(.plain)
                Text("LOCAL PLAY / V0.3").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
            }.font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.top, 18)
        }.padding(30)
    }
    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FIND YOUR FLOW").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundStyle(rushLime)
            Text("1. Connect and calibrate in Controller setup.\n\n2. Wait for blocks to reach you, then sweep your blade through them.\n\n3. Cut in the arrow's direction. Keep your blade away from red × blocks.\n\n4. Five clean cuts increase your multiplier. A miss, wrong cut, or hazard breaks your combo.")
                .font(.callout).foregroundStyle(.white.opacity(0.75))
            Button("Got it") { showHowTo = false }.buttonStyle(.bordered)
        }.padding(24).frame(maxWidth: 360).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }
    private var hud: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SCORE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    Text(game.state.score.formatted()).font(.system(size: 39, weight: .black, design: .rounded)).monospacedDigit()
                }.frame(width: 170, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("×\(game.state.multiplier)").font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(rushLime)
                    Text("\(game.state.combo) COMBO").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 4) {
                    Text(game.state.roundName).font(.system(size: 12, weight: .black, design: .monospaced)).tracking(3).foregroundStyle(rushLime)
                    Text(String(format: "%d:%02d", Int(ceil(game.state.remaining)) / 60, Int(ceil(game.state.remaining)) % 60)).font(.system(size: 37, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("ENERGY").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(0..<game.state.difficulty.lives, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < game.state.lives ? rushLime : .white.opacity(0.1)).frame(width: 15, height: 21)
                        }
                    }
                }
                Button { game.pause() } label: { Image(systemName: "pause.fill").padding(10) }.buttonStyle(.bordered).padding(.leading, 14)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(rushLime).frame(width: g.size.width * game.state.remaining / 60)
                }
            }.frame(height: 3)
        }.padding(.horizontal, 28).padding(.vertical, 20)
            .background(LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(game.state.phase == .playing || game.state.phase == .countdown)
    }
    private var playFooter: some View {
        HStack {
            Text("NEON RUSH").font(.system(size: 12, weight: .black, design: .rounded)).italic().tracking(1)
            if game.isDemo { Text("DEMO · NO HIGH SCORE").foregroundStyle(.orange).font(.system(size: 10, weight: .bold, design: .monospaced)) }
            Spacer()
            Text("R  RECENTER     SPACE  PAUSE").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            Button { game.sound.toggle() } label: { Image(systemName: game.sound ? "speaker.wave.2" : "speaker.slash") }.buttonStyle(.plain)
        }.padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
    private var countdown: some View {
        VStack(spacing: 10) {
            Text("GET INTO POSITION").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3)
            Text("\(max(1, Int(ceil(game.state.countdown))))").font(.system(size: 130, weight: .black, design: .rounded)).italic().foregroundStyle(rushLime)
            Text("Sweep through neon. Avoid red.").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.25)).allowsHitTesting(false)
    }
    private var pauseCard: some View {
        overlayCard {
            Text("TAKE A BREATH.").font(.system(size: 42, weight: .black, design: .rounded)).italic()
            Text(game.pauseReason).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Label(game.inputReady ? "Controller ready" : "Waiting for controller", systemImage: game.inputReady ? "checkmark.circle.fill" : "airpodspro")
                .foregroundStyle(game.inputReady ? rushLime : .orange).font(.callout)
            actionButton("BACK TO THE RUSH") { game.resume() }.disabled(!game.inputReady)
            HStack(spacing: 22) {
                Button("Controller setup") { showingSetup = true }
                Button("End run") { game.leave() }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
        }
    }
    private var results: some View {
        overlayCard {
            Text(game.state.completed ? "RUN COMPLETE" : "OUT OF ENERGY").font(.system(size: 11, weight: .black, design: .monospaced)).tracking(3).foregroundStyle(rushLime)
            HStack(alignment: .center, spacing: 28) {
                Text(game.state.completed ? game.state.rank : "↻").font(.system(size: 90, weight: .black, design: .rounded)).italic().foregroundStyle(rushLime)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.state.score.formatted()).font(.system(size: 54, weight: .black, design: .rounded)).monospacedDigit()
                    Text(game.newRecord ? "NEW PERSONAL BEST" : game.isDemo ? "DEMO RUN · SCORE NOT SAVED" : "\(game.state.difficulty.rawValue.uppercased()) · BEST \(game.bestScore.formatted())")
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
            actionButton("ONE MORE RUN") { game.start(demo: motion.simulated) }.disabled(!game.inputReady)
            HStack(spacing: 24) {
                Button("Back to Aircade") { game.leave() }
                if !game.inputReady { Button("Connect controller") { showingSetup = true } }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
        }
    }
    private func overlayCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.65)
            VStack(spacing: 22, content: content).padding(38).frame(width: 600)
                .background(Color(red: 0.055, green: 0.065, blue: 0.075), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1)))
        }
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.system(size: 13, weight: .black, design: .monospaced)).padding(18)
                .foregroundStyle(.black).background(rushLime, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
    private var brand: some View { Text("aircade").font(.system(size: 26, weight: .black, design: .rounded)).tracking(-1).padding(.trailing, 12) }
    private var connectionPill: some View {
        HStack(spacing: 7) {
            Circle().fill(game.inputReady ? rushLime : .orange).frame(width: 6, height: 6)
            Text(motion.simulated ? "DEMO INPUT" : game.inputReady ? "CONNECTED" : "NOT CONNECTED").font(.system(size: 10, weight: .bold, design: .monospaced))
        }.padding(11).background(.black.opacity(0.5), in: Capsule())
    }
    private func menuStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
        }
    }
    private func rule(_ symbol: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Text(symbol).font(.system(size: 26, weight: .bold)).frame(width: 43, height: 43)
                .foregroundStyle(color).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .black, design: .monospaced)).tracking(1)
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
                Text("YOUR CONTROLLER").font(.system(size: 22, weight: .black, design: .rounded))
                Spacer(); Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    setupStep("01", "Connect your AirPods") {
                        Text("Turn off Automatic Ear Detection. Hold one earbud in a consistent grip.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Start AirPods") { motion.start() }.buttonStyle(.borderedProminent).tint(rushLime).foregroundStyle(.black)
                            Text(motion.status).font(.caption)
                        }
                    }
                    setupStep("02", "Match three poses") {
                        Text(motion.hasGripCalibration ? "Your grip is saved. Recalibrate if the earbud has moved in your fingers." : "Follow the animated guide so left, right, and forward feel natural.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(motion.hasGripCalibration ? "Recalibrate grip" : "Calibrate grip") { motion.beginGripCalibration() }
                                .disabled(!motion.running || motion.simulated || motion.sampleAge > 0.25)
                            Button("Recenter [R]") { motion.recenter() }.disabled(!motion.running || motion.sampleAge > 0.25)
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
                    Text("Keep the earbud secure. Start with controlled wrist movements. R recenters your grip; a tracking interruption pauses the game.").font(.caption).foregroundStyle(.secondary)
                    Button("Open test lab & diagnostics") { done(); motion.showLab(true) }.buttonStyle(.plain).foregroundStyle(rushLime)
                }
            }
        }.padding(26).frame(width: 610, height: 690).background(Color(red: 0.04, green: 0.05, blue: 0.065)).preferredColorScheme(.dark)
    }
    private func setupStep<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(number).foregroundStyle(rushLime).font(.system(size: 12, weight: .bold, design: .monospaced)); Text(title).font(.headline) }
            content()
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
}
