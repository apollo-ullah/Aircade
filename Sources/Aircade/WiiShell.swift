import SwiftUI
import simd

/// Root container. Owns navigation, the bottom bar, and the cursor overlay.
struct WiiShell: View {
    @ObservedObject var motion: MotionModel
    @StateObject private var pointer = PointerModel()
    @State private var route: Route
    @State private var previousPointerSample: ControllerSnapshot?
    private let pointerClock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(motion: MotionModel) {
        self.motion = motion
        _route = State(initialValue: WiiShell.initialRoute(arguments: CommandLine.arguments))
    }

    /// Command-line launches bypass the channel grid; the smoke and scripted
    /// checks drive the app headless and must land directly on their screen.
    static func initialRoute(arguments: [String]) -> Route {
        let flags = Set(arguments)
        if !flags.isDisjoint(with: ["--game-smoke-test", "--scripted-game-test",
                                    "--scripted-repro", "--scripted-demo"]) { return .neonRush }
        if !flags.isDisjoint(with: ["--smoke-test", "--simple-calibration",
                                    "--live-test"]) { return .lab }
        if !flags.isDisjoint(with: ["--multiplayer", "--duel-smoke"]) { return .duel }
        if !flags.isDisjoint(with: ["--tennis-preview", "--tennis-smoke"]) { return .tennis }
        return .home
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { if route == .home { WiiCursorView(pointer: pointer, size: geo.size) } }
                    .onContinuousHover { phase in
                        guard case let .active(location) = phase, route == .home else { return }
                        pointer.ingestMouse(CGPoint(x: location.x / geo.size.width,
                                                    y: location.y / geo.size.height))
                    }
            }
            bottomBar
        }
            .background(WiiTheme.stage)
            .onChange(of: motion.controllers.revision) { feedPointer() }
            .onChange(of: motion.controllers.menuDevice) { previousPointerSample = nil; pointer.recenter(); feedPointer() }
            .onReceive(pointerClock) { _ in feedPointer() }
            .onReceive(NotificationCenter.default.publisher(for: .wiiRouteRequest)) { note in
                if let requested = note.object as? Route { open(requested) }
            }
            .onChange(of: motion.scriptedScenario) {
                if motion.scriptedScenario != nil, route != .neonRush { open(.neonRush) }
            }
            .onAppear {
                // A command-line smoke harness may already have prepared the game.
                activate(route, initial: true)
                if route == .home { WiiAudio.shared.startMusic() }
            }
    }

    private func feedPointer() {
        guard route == .home else { return }
        let time = ProcessInfo.processInfo.systemUptime
        guard let sample = motion.controllers.snapshot(for: motion.controllers.menuDevice), sample.ready else {
            _ = pointer.ingestMotion(orientation: simd_quatf(), sampleAge: .infinity, speed: 0, time: time)
            previousPointerSample = nil; return
        }
        var speed = 0.0
        if let previous = previousPointerSample, previous.controllerID == sample.controllerID,
           previous.sessionID == sample.sessionID, sample.capturedAt > previous.capturedAt {
            let dot = min(1, abs(simd_dot(previous.orientation.vector, sample.orientation.vector)))
            speed = Double(2 * acos(dot)) / (sample.capturedAt - previous.capturedAt)
        }
        let selected = pointer.ingestMotion(orientation: sample.orientation, sampleAge: sample.age(at: time), speed: speed, time: time)
        previousPointerSample = sample
        if selected { NotificationCenter.default.post(name: .wiiPointerFlick, object: nil) }
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .home:
            ChannelGrid(pointer: pointer) { open($0) }
        case .neonRush:
            NeonRushView(motion: motion, game: motion.game, players: motion.players)
        case .tennis:
            TennisView(motion: motion, game: motion.tennis, players: motion.players)
        case .lab:
            ArenaLayout(motion: motion, arena: motion.arena, camera: motion.camera)
        case .duel:
            MultiplayerView(motion: motion, duel: motion.multiplayer)
        case .avatar, .profile:
            PlayerChannelView(motion: motion, players: motion.players)
        case .controller:
            ControllerSetupView(motion: motion, done: { open(.home) })
        case .scripts:
            ScriptedControllerSetup(motion: motion, done: { open(.neonRush) })
        case .settings:
            ArcadeSettingsView(motion: motion, open: open)
        }
    }

    private func open(_ next: Route) {
        guard next != route else { return }
        WiiAudio.shared.play(next == .home ? .close : .open)
        if next == .home { WiiAudio.shared.startMusic() } else { WiiAudio.shared.stopMusic() }
        pointer.recenter(); previousPointerSample = nil
        // Script setup starts the production game before asking the shell to show it.
        if next == .neonRush && motion.scriptedScenario != nil { motion.shellRoute = next }
        else { activate(next) }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { route = next }
    }

    private func activate(_ next: Route, initial: Bool = false) {
        motion.shellRoute = next
        if initial && next != .home { return }
        if motion.scriptedScenario != nil && next != .neonRush { motion.stop() }
        if motion.showingMultiplayer { motion.showMultiplayer(false, notify: false) }
        if motion.showingLab { motion.showLab(false, notify: false) }
        motion.game.leave(); motion.tennis.leave()
        motion.game.enabled = false; motion.tennis.enabled = false; motion.arena.enabled = false
        switch next {
        case .neonRush: motion.selectSport(.neonRush, notify: false)
        case .tennis: motion.selectSport(.tennis, notify: false)
        case .duel: motion.showMultiplayer(true, notify: false)
        case .lab: motion.showLab(true, notify: false)
        default: break
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { open(.settings) } label: {
                Text("air").font(WiiTheme.display(14, .bold)).italic()
            }
            .buttonStyle(WiiButtonStyle())
            .accessibilityLabel("Aircade settings")

            if route != .home {
                Button("Back to menu") { open(.home) }
                    .buttonStyle(WiiButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Text(statusText)
                .font(WiiTheme.body(11))
                .foregroundStyle(WiiTheme.inkSoft)

            Spacer()
            Text(Date.now, format: .dateTime.hour().minute())
                .font(WiiTheme.display(17, .semibold))
                .foregroundStyle(WiiTheme.ink)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(WiiTheme.barFill)
        .overlay(alignment: .top) { Rectangle().fill(WiiTheme.hairline).frame(height: 1) }
    }

    private var statusText: String {
        if route == .home && pointer.source == .motion { return "\(motion.controllers.name(for: motion.controllers.menuDevice)) pointing · flick to select" }
        if route == .home { return "Mouse control · connect an AirPod or iPhone to point" }
        return motion.controllers.readiness(for: motion.controllers.soloDevice)
    }
}
