import SwiftUI

/// Root container. Owns navigation, the bottom bar, and the cursor overlay.
struct WiiShell: View {
    @ObservedObject var motion: MotionModel
    @StateObject private var pointer = PointerModel()
    @State private var route: Route

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
        if flags.contains("--multiplayer") { return .duel }
        if flags.contains("--tennis-preview") { return .tennis }
        return .home
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
            .background(WiiTheme.stage)
            .overlay(WiiCursorView(pointer: pointer, size: geo.size))
            .onContinuousHover { phase in
                guard case let .active(location) = phase else { return }
                pointer.ingestMouse(CGPoint(x: location.x / geo.size.width,
                                            y: location.y / geo.size.height))
            }
            .onChange(of: motion.quaternion) { _ in feedPointer() }
            .onChange(of: motion.sampleAge) { _ in feedPointer() }
            .onReceive(NotificationCenter.default.publisher(for: .wiiRouteRequest)) { note in
                if let requested = note.object as? Route { open(requested) }
            }
            .onAppear {
                if route == .lab { motion.showLab(true, notify: false) }
                if route == .tennis { motion.selectSport(.tennis) }
            }
        }
    }

    private func feedPointer() {
        let selected = pointer.ingestMotion(orientation: motion.saber,
                                            sampleAge: motion.sampleAge,
                                            speed: motion.speed,
                                            time: ProcessInfo.processInfo.systemUptime)
        guard selected, route == .home else { return }
        // Hover state lives in the grid; it opens on its own button action, so
        // a flick only needs to forward a click at the current point.
        NotificationCenter.default.post(name: .wiiPointerFlick, object: nil)
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
            ComingSoonChannel(title: "Saber Duel", back: { open(.home) })
        case .avatar:
            ComingSoonChannel(title: "Avatar Channel", back: { open(.home) })
        case .controller:
            ControllerSetupView(motion: motion, done: { open(.home) })
        case .scripts:
            ScriptedControllerSetup(motion: motion, done: { open(.home) })
        case .settings:
            ComingSoonChannel(title: "Settings", back: { open(.home) })
        }
    }

    private func open(_ next: Route) {
        // Entering or leaving a channel pauses a running game, matching how the
        // existing sheets already behave.
        if next != .neonRush { motion.game.pause("Aircade menu is open.") }
        if next != .tennis { motion.tennis.pause("Aircade menu is open.") }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { route = next }
        let wantLab = next == .lab
        if motion.showingLab != wantLab { motion.showLab(wantLab, notify: false) }
        if !wantLab {
            if next == .tennis { motion.selectSport(.tennis) }
            else if next == .neonRush { motion.selectSport(.neonRush) }
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
        if pointer.source == .motion { return "\(motion.controllerName) pointing · flick to select" }
        if motion.running { return "\(motion.controllerName) connected · pointing paused" }
        return "Mouse control · connect a controller to point"
    }
}

/// Placeholder for channels whose screens land in later plans.
struct ComingSoonChannel: View {
    var title: String
    var back: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(WiiTheme.display(34))
            Text("This channel is not built yet.")
                .font(WiiTheme.body(14)).foregroundStyle(WiiTheme.inkSoft)
            Button("Back to menu", action: back).buttonStyle(WiiButtonStyle(primary: true))
        }
        .padding(44).wiiPanel()
    }
}
