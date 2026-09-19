import SwiftUI
import Combine
import simd

/// Root container. Owns navigation, the bottom bar, and the cursor overlay.
struct WiiShell: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject private var menu: ControllerMenu
    @State private var window: NSWindow?
    @State private var route: Route
    // MotionModel publishes every sensor frame. Preserve this publisher when
    // ContentView reconstructs the shell, or updates can keep postponing its tick.
    @State private var pointerClock = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    init(motion: MotionModel) {
        self.motion = motion
        self.menu = motion.menu
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
        if !flags.isDisjoint(with: ["--tennis-preview", "--tennis-smoke", "--ai-challenge-preview"]) { return .tennis }
        return .home
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
            .coordinateSpace(name: "controllerMenu")
            .environment(\.controllerMenu, menu)
            .background(MenuWindowReader { window = $0 })
            .onPreferenceChange(ControllerMenuFrames.self) { menu.setTargets($0) }
            .overlay { if menu.active { WiiCursorView(pointer: menu.pointer, menu: menu, size: geo.size) } }
            .onContinuousHover { phase in
                guard case let .active(location) = phase else { return }
                menu.mouse(CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height))
            }
            .onAppear { menu.size = geo.size }
            .onChange(of: geo.size) { menu.size = geo.size; menu.reset() }
        }
            .background(WiiTheme.stage)
            .onChange(of: motion.controllers.menuDevice) { menu.reset(); feedPointer() }
            .onReceive(pointerClock) { _ in feedPointer() }
            .onReceive(NotificationCenter.default.publisher(for: .wiiPointerFlick)) { _ in
                if window?.attachedSheet == nil && NSApp.isActive { menu.clickHovered() }
            }
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
        let inMenus: Bool
        let phase: String
        switch route {
        case .neonRush:
            phase = motion.game.state.phase.rawValue
            inMenus = [.menu, .paused, .results].contains(motion.game.state.phase)
        case .tennis:
            phase = motion.tennis.displayPhase.rawValue
            inMenus = [.menu, .paused, .results].contains(motion.tennis.displayPhase)
        case .duel:
            phase = String(describing: motion.multiplayer.match.phase)
            inMenus = [.lobby, .paused, .results].contains(motion.multiplayer.match.phase)
        case .lab: phase = "practice"; inMenus = false
        default: phase = "menu"; inMenus = true
        }
        let foreground = NSApp.isActive && window?.isKeyWindow == true && window?.attachedSheet == nil
        menu.update(sample: motion.controllers.snapshot(for: menuInputDevice),
                    time: ProcessInfo.processInfo.systemUptime, context: "\(route)-\(phase)", enabled: inMenus && foreground)
    }

    private var menuInputDevice: ControllerDevice {
        let selected = motion.controllers.menuDevice
        let time = ProcessInfo.processInfo.systemUptime
        if let snapshot = motion.controllers.snapshot(for: selected), snapshot.ready, snapshot.age(at: time) < 1 { return selected }
        let alternative: ControllerDevice = selected == .airPod ? .phone : .airPod
        return motion.controllers.snapshot(for: alternative)?.isFresh(at: time) == true ? alternative : selected
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .home:
            ChannelGrid() { open($0) }
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
        menu.reset()
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
            MotionButton(id: "settings") { open(.settings) } label: {
                Text("air").font(WiiTheme.display(14, .bold)).italic()
            }
            .buttonStyle(WiiButtonStyle())
            .accessibilityLabel("Aircade settings")

            if route != .home {
                MotionButton("Back to menu") { open(.home) }
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
        if menu.active { return "\(motion.controllers.name(for: menuInputDevice)) · tilt to point · hold 1 second to select" }
        if route == .home { return motion.running ? motion.status : "Start AirPods in Controllers to point through menus" }
        if route == .lab { return motion.controllers.readiness(for: .airPod) }
        if route == .duel {
            if motion.multiplayer.scripted { return "Scripted duel · simulated controllers" }
            return "Blue: \(motion.multiplayer.name(.one)) · Orange: \(motion.multiplayer.name(.two))"
        }
        return motion.controllers.readiness(for: motion.controllers.soloDevice)
    }
}
