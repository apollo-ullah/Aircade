import SwiftUI
import AppKit
import SceneKit

@main
struct AircadeApp: App {
    @StateObject private var motion = MotionModel()
    var body: some Scene {
        WindowGroup("Aircade Sports") {
            ContentView(motion: motion)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(.light)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    motion.startControllerSession()
                    if CommandLine.arguments.contains("--tennis-preview") { motion.selectSport(.tennis) }
                    if CommandLine.arguments.contains("--calibration-preview") || CommandLine.arguments.contains("--simple-calibration-preview") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            var previews: [(Int, NSWindow, NSView)] = []
                            let simple = CommandLine.arguments.contains("--simple-calibration-preview")
                            for step in 1...(simple ? 4 : 6) {
                                let detailedPanel = CalibrationGuidePanel(step: min(step, 5), status: "Synthetic UI preview", isLive: step != 6,
                                    activeSource: "Left", tiltDegrees: step == 1 ? nil : step == 3 ? 0 : step == 5 ? 26 : 30,
                                    poseHint: step == 6 ? "macOS is sending Right motion. Your Left calibration is paused. Choose which earbud to use." : step == 5 ? "UI PREVIEW · synthetic data. Test the blade, then return upright to save." : "UI PREVIEW · synthetic data. Steady pose, ready to continue.", poseReady: step < 5,
                                    previewTime: 3.2, rotationSpeed: 0.12,
                                    liveOrientation: step == 5 ? simd_quatf(angle: 0.45, axis: SIMD3<Float>(0, 0, 1)) : nil,
                                    sourceWarning: step == 6 ? "Selected: Left · macOS reporting: Right" : nil,
                                    adoptSourceTitle: step == 6 ? "Use Right instead & restart" : nil,
                                    restart: {}, useSaved: {})
                                    .environment(\.colorScheme, .light)
                                let panel = simple ? AnyView(SimpleCalibrationPanel(step: min(step, 3), source: step == 2 ? "Right" : "Left", isLive: step != 4,
                                    message: "UI PREVIEW • synthetic data. Click to save this angle.",
                                    sourceWarning: step == 4 ? "Selected: Left · macOS reporting: Right" : nil,
                                    switchTitle: step == 4 ? "Calibrate Right AirPod instead" : nil, previewTime: 3.2)) : AnyView(detailedPanel)
                                let host = NSHostingView(rootView: panel)
                                let size = host.fittingSize
                                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                                window.appearance = NSAppearance(named: .aqua)
                                window.contentView = host
                                window.center()
                                window.makeKeyAndOrderFront(nil)
                                previews.append((step, window, host))
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                for (step, window, host) in previews {
                                    host.layoutSubtreeIfNeeded()
                                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                                        host.cacheDisplay(in: host.bounds, to: bitmap)
                                        if let data = bitmap.representation(using: .png, properties: [:]) {
                                            try? data.write(to: motion.logDirectory.appendingPathComponent("\(simple ? "simple-calibration" : "calibration")-step-\(step).png"))
                                        }
                                    }
                                    window.orderOut(nil)
                                }
                                NSApp.terminate(nil)
                            }
                        }
                    }
                    if CommandLine.arguments.contains("--simple-calibration") {
                        motion.showLab(true)
                        motion.start()
                        motion.openCalibrationWhenReady = true
                    } else if CommandLine.arguments.contains("--live-test") { motion.start() }
                    if CommandLine.arguments.contains("--multiplayer") { motion.showMultiplayer(true) }
                    if CommandLine.arguments.contains("--duel-smoke") { DuelSmoke.run(motion) }
                    if CommandLine.arguments.contains("--tennis-smoke") { TennisSmoke.run(motion) }
                    if CommandLine.arguments.contains("--scripted-repro") { ScriptedGameCheck.run(motion, reproduce: true) }
                    if CommandLine.arguments.contains("--scripted-game-test") { ScriptedGameCheck.run(motion) }
                    if CommandLine.arguments.contains("--scripted-demo") { motion.startScripted(.perfectRun) }
                    if CommandLine.arguments.contains("--scripted-setup-preview") { ScriptedGameCheck.previewSetup(motion) }
                    if CommandLine.arguments.contains("--game-smoke-test") { GameSmoke.run(motion) }
                    if CommandLine.arguments.contains("--smoke-test") {
                        motion.showLab(true)
                        motion.start(demo: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            let view = SCNView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
                            view.scene = motion.scene.scene
                            let image = view.snapshot()
                            if let tiff = image.tiffRepresentation,
                               let bitmap = NSBitmapImageRep(data: tiff),
                               let data = bitmap.representation(using: .png, properties: [:]) {
                                try? data.write(to: motion.logDirectory.appendingPathComponent("scene-smoke.png"))
                            }
                            let passed = motion.samples > 60 && motion.calibrated && motion.simulated && motion.arena.hits > 0
                            print("SMOKE \(passed ? "PASS" : "FAIL"): \(motion.samples) simulated samples; no hardware proof")
                            let report = "Smoke test: \(passed ? "PASS" : "FAIL")\nSimulated samples: \(motion.samples)\nArena cuts: \(motion.arena.hits)\nHardware verified: false\n"
                            try? report.write(to: motion.logDirectory.appendingPathComponent("smoke-result.txt"), atomically: true, encoding: .utf8)
                            if let content = NSApp.windows.first?.contentView,
                               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                                content.cacheDisplay(in: content.bounds, to: bitmap)
                                if let png = bitmap.representation(using: .png, properties: [:]) {
                                    try? png.write(to: motion.logDirectory.appendingPathComponent("ui-smoke.png"))
                                }
                            }
                            motion.stop()
                            NSApp.terminate(nil)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    if motion.showingMultiplayer { motion.multiplayer.close() }
                    motion.shutdownControllerSession(); motion.stop(); motion.camera.stop()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    if !CommandLine.arguments.contains("--scripted-repro") && !CommandLine.arguments.contains("--scripted-game-test") && !CommandLine.arguments.contains("--duel-smoke") && !CommandLine.arguments.contains("--tennis-smoke") {
                        motion.game.pause("Paused while Aircade was in the background.")
                        motion.tennis.pause("Paused while Aircade was in the background.")
                        if motion.showingMultiplayer { motion.multiplayer.pause("Paused while Aircade was in the background.") }
                    }
                }
        }
        .defaultSize(width: 1340, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Recenter Controller") {
                    if motion.showingMultiplayer { motion.multiplayer.pause("Player 1 recentered. Hold both controllers upright, then resume.") }
                    motion.recenterSelectedController()
                }.keyboardShortcut("r", modifiers: [])
                Button("Play / Pause") {
                    if motion.showingMultiplayer {
                        let duel = motion.multiplayer
                        if duel.match.phase == .paused { duel.resume() }
                        else if duel.match.phase == .lobby || duel.match.phase == .results { duel.start() }
                        else { duel.pause() }
                    }
                    else if motion.showingLab { motion.arena.launchAttack() }
                    else if motion.selectedSport == .tennis {
                        if motion.tennis.state.phase == .paused { motion.tennis.resume() }
                        else if motion.tennis.state.phase == .menu || motion.tennis.state.phase == .results { motion.tennis.start(demo: motion.activeInputSimulated) }
                        else { motion.tennis.pause() }
                    } else if motion.game.state.phase == .paused { motion.game.resume() }
                    else if motion.game.state.phase == .menu || motion.game.state.phase == .results { motion.game.start(demo: motion.activeInputSimulated) }
                    else { motion.game.pause() }
                }.keyboardShortcut(.space, modifiers: [])
                Button("Stop Tracking") { motion.stop() }.keyboardShortcut(".")
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var motion: MotionModel
    var body: some View {
        Group {
            if motion.showingMultiplayer { MultiplayerView(motion: motion, duel: motion.multiplayer) }
            else if motion.showingLab { ArenaLayout(motion: motion, arena: motion.arena, camera: motion.camera) }
            else if motion.selectedSport == .tennis { TennisView(motion: motion, game: motion.tennis, players: motion.players) }
            else { NeonRushView(motion: motion, game: motion.game, players: motion.players) }
        }
    }
}

struct ArenaLayout: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var arena: TrainingArena
    @ObservedObject var camera: HandTracker
    @State private var panel = 0
    private let cyan = SportsTheme.blue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 28) {
                        stat("SCORE", "\(arena.score)")
                        stat("CUTS", "\(arena.hits)")
                        stat("PARRIES", "\(arena.parries)")
                        stat("COMBO", "×\(arena.combo)")
                        Spacer()
                        Text(motion.simulated ? "SIMULATION" : motion.useCamera ? "AIRPOD + CAMERA" : "AIRPOD ROTATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(motion.simulated ? .orange : cyan)
                    }.padding(20)
                    ZStack(alignment: .topLeading) {
                        SaberView(controller: motion.scene)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(arena.mode.rawValue.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(cyan)
                            Text(arena.message).font(.system(size: 26, weight: .bold, design: .default))
                            Text(arena.detail).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
                        }.padding(22).allowsHitTesting(false)
                        if !arena.inputReady {
                            VStack {
                                Spacer()
                                Text(inputHint).font(.callout.weight(.medium)).padding(12)
                                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                                    .padding(.bottom, 25)
                            }.frame(maxWidth: .infinity).allowsHitTesting(false)
                        }
                        VStack {
                            Spacer()
                            HStack {
                                Text(arena.lastEvent).foregroundStyle(cyan)
                                Spacer()
                                Text(String(format: "%.1f Hz · %@ · %.1f rad/s", motion.frequency, motion.source, motion.speed))
                            }.font(.system(size: 11, design: .monospaced)).padding(18)
                        }.allowsHitTesting(false)
                    }.frame(minHeight: 370)
                    HStack {
                        Button("Recenter  [R]") { motion.recenter() }.disabled(!motion.running || motion.sampleAge > 0.5)
                        if arena.mode == .parry {
                            Button("Launch attack  [Space]") { arena.launchAttack() }
                                .buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
                                .disabled(arena.attackInProgress || !arena.inputReady)
                        }
                        Button("Reset arena") { arena.reset() }
                        Spacer()
                        Toggle("Sound", isOn: $arena.sound).toggleStyle(.checkbox)
                    }.padding(18).background(.white.opacity(0.025))
                }
                Divider()
                VStack(spacing: 0) {
                    Picker("Panel", selection: $panel) {
                        Text("Play & calibrate").tag(0)
                        Text("Diagnostics").tag(1)
                    }.pickerStyle(.segmented).padding(16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if panel == 0 { playPanel } else { diagnostics }
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }.frame(width: 390)
            }
        }.background(SportsTheme.paper)
        .sheet(isPresented: Binding(get: { motion.calibrationStep > 0 }, set: { showing in
            if !showing && motion.calibrationStep > 0 { motion.cancelGripCalibration() }
        })) {
            CalibrationSheet(motion: motion).interactiveDismissDisabled()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AIRCADE").font(.system(size: 24, weight: .bold, design: .default)).tracking(4)
                Text("TRAINING ARENA   /   PROTOTYPE 02").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            ControllerIdentityBadge(motion: motion)
            Text(motion.status).font(.caption).lineLimit(2).frame(maxWidth: 260, alignment: .leading)
            Button(motion.running && !motion.simulated ? "Restart AirPods" : "Start AirPods") { motion.start() }
                .buttonStyle(.borderedProminent).tint(cyan).foregroundStyle(.black)
            Button("Stop") { motion.stop() }.disabled(!motion.running)
            Button("Back to Aircade") { motion.showLab(false) }
        }.padding(20)
    }
    private var inputHint: String {
        if !motion.running { return "Start AirPods, or use the demo to test the arena" }
        if motion.calibrationStep > 0 { return "Complete the grip setup window" }
        if motion.sampleAge > 0.5 { return "Waiting for fresh AirPod motion" }
        if !motion.calibrated { return "Hold the grip upright and press R to recenter" }
        if motion.useCamera && camera.point == nil { return "Show your controller hand to the camera" }
        return "Waiting for tracking"
    }
    @ViewBuilder private var playPanel: some View {
        section("01  /  CHOOSE YOUR TEST") {
            Picker("Mode", selection: $arena.mode) {
                ForEach(TrainingArena.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if arena.mode == .block {
                Picker("Slash direction", selection: $arena.cutDirection) {
                    ForEach(["Any", "Left", "Right", "Down"], id: \.self) { Text($0) }
                }
                Text("Cross the block to cut it. Direction and cutting angle affect the result. Targets respawn automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("A green ghost shows the required guard. Intercept the orange attack at the ghost with the correct blade angle. Press Space to begin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        section("02  /  MAP YOUR GRIP") {
            ControllerSourceStatus(motion: motion)
            Text(motion.calibrationMessage).font(.callout)
            if motion.calibrationStep == 0 {
                Button(motion.calibrationButtonTitle) { motion.beginGripCalibration() }
                    .disabled(!motion.hasFreshMotion || motion.simulated)
            } else {
                Text("Follow the animated setup window.").font(.caption).foregroundStyle(cyan)
            }
            DisclosureGroup("Manual mapping & smoothing") {
                VStack(spacing: 10) {
                    Picker("Grip axes", selection: $motion.grip) {
                        Text("Native").tag(0); Text("Tilt +90°").tag(1)
                        Text("Tilt −90°").tag(2); Text("Reverse").tag(3)
                        if motion.hasGripCalibration { Text("Measured grip").tag(4) }
                    }
                    HStack {
                        Text("Smoothing").font(.caption)
                        Slider(value: $motion.smoothing, in: 0...0.15)
                        Text(String(format: "%.0f ms", motion.smoothing * 1000)).font(.caption.monospacedDigit()).frame(width: 45)
                    }
                }.padding(.top, 8)
            }.font(.caption)
            Text("Keep the earbud fixed in your grip. Recenter sets the starting pose; grip calibration sets the movement axes.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        section("03  /  MOVE YOUR HAND WITH CAMERA") {
            Toggle("Enable hand position", isOn: $motion.useCamera)
            Text("AirPod = blade angle. Webcam = sideways/up-down hand position. No depth tracking.")
                .font(.caption).foregroundStyle(.secondary)
            if motion.useCamera {
                Picker("Camera", selection: $camera.selectedID) {
                    ForEach(camera.devices) { Text($0.name).tag($0.id) }
                }.disabled(camera.running)
                HStack {
                    Button(camera.running ? "Restart camera" : "Start camera") { motion.startCamera() }
                    Button("Refresh") { camera.refreshDevices() }.disabled(camera.running)
                }
                HandPreview(tracker: camera)
                Text(camera.status).font(.caption).foregroundStyle(camera.point == nil ? .orange : cyan)
                HStack {
                    Toggle("Mirror", isOn: $camera.mirrored).toggleStyle(.checkbox)
                    Picker("Acquire", selection: $camera.handSelection) {
                        Text("Right of preview").tag(0); Text("Left of preview").tag(1)
                    }.font(.caption)
                }
                HStack {
                    Text("Travel").font(.caption)
                    Slider(value: $motion.cameraGain, in: 2...9)
                    Text(String(format: "%.1f×", motion.cameraGain)).font(.caption.monospacedDigit())
                }
                Text("Keep one hand clearly visible; loosen a closed fist if tracking drops. Press R with the hand centred. Reacquisition establishes a new centre to prevent jump hits.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        Button("Run arena demo · simulated input") { motion.start(demo: true) }.font(.caption)
    }
    @ViewBuilder private var diagnostics: some View {
        section("SENSOR HEALTH") {
            HStack {
                stat("RATE", String(format: "%.1f Hz", motion.frequency))
                Spacer()
                stat("SOURCE", motion.source)
            }
            Text("\(motion.samples) samples · \(motion.gaps) gaps · \(motion.switches) source switches").font(.caption)
            Text("Permission: \(motion.authorization)").font(.caption)
            Text(motion.sampleAge.isFinite ? String(format: "Last sample %.0f ms ago", motion.sampleAge * 1000) : "No samples").font(.caption).foregroundStyle(.secondary)
            vector("Yaw / pitch / roll", motion.attitude, unit: "°")
            vector("Angular velocity · x / y / z", motion.rotation, unit: "rad/s")
            vector("Acceleration · x / y / z", motion.acceleration, unit: "g")
            Sparkline(values: motion.speedHistory).stroke(cyan, lineWidth: 2).frame(height: 40)
            Text("Angular speed · 0–10 rad/s").font(.caption2).foregroundStyle(.secondary)
        }
        section("TWO-MINUTE HARDWARE TEST") {
            Picker("Condition", selection: $motion.condition) {
                ForEach(["Handheld — left", "Handheld — right", "Both worn", "One worn / one held", "Other earbud in case"], id: \.self) { Text($0) }
            }.disabled(motion.testing)
            ProgressView(value: min(120, motion.testProgress), total: 120).tint(cyan)
            Text(String(format: "%.0f / 120 s · %.0f° / 30°", motion.testProgress, motion.testAngle)).font(.caption.monospacedDigit())
            Text(motion.testMessage).font(.caption)
            HStack {
                Button("Begin test") { motion.beginTrial() }
                    .disabled(!motion.running || motion.simulated || motion.sampleAge > 0.5 || motion.testing)
                if motion.testing { Button("Cancel") { motion.cancelTrial() } }
            }
        }
        section("EVENTS & LOGS") {
            Button("Open logs in Finder") { motion.revealLogs() }
            Text("Cuts, glances, parries and damage are written as events to the motion CSV. Camera images are never written to disk.")
                .font(.caption2).foregroundStyle(.secondary)
            if !motion.logError.isEmpty { Text(motion.logError).foregroundStyle(.red) }
            ForEach(Array(motion.events.enumerated()), id: \.offset) { _, event in
                Text(event).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(cyan)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .default)).monospacedDigit()
        }
    }
    private func vector(_ title: String, _ value: SIMD3<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%7.2f %7.2f %7.2f %@", value.x, value.y, value.z, unit)).font(.system(size: 11, design: .monospaced))
        }
    }
}

struct Sparkline: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (i, value) in values.enumerated() {
            let point = CGPoint(x: rect.width * Double(i) / Double(values.count - 1), y: rect.height * (1 - min(10, max(0, value)) / 10))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
