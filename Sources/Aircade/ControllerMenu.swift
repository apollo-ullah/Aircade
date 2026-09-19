import AppKit
import SwiftUI
import simd

struct ControllerMenuTarget: Equatable {
    let id: UUID
    var name = ""
    let frame: CGRect
    let enabled: Bool
    let action: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.enabled == rhs.enabled
    }
}

/// A button can fire once per visit. Loss, mouse input and navigation cancel the hold.
struct MenuDwell {
    var duration = 1.0
    private(set) var target: UUID?
    private(set) var progress = 0.0
    private var began: Double?
    private var fired = false
    mutating func update(target next: UUID?, time: Double, allowed: Bool) -> UUID? {
        guard allowed, time.isFinite, let next else { reset(); return nil }
        if next != target { target = next; began = time; fired = false; progress = 0 }
        guard let began, time >= began else { reset(); return nil }
        guard !fired else { return nil }
        progress = min(1, (time - began) / duration)
        if progress >= 1 { fired = true; return next }
        return nil
    }
    mutating func reset() { target = nil; began = nil; progress = 0; fired = false }
}

final class ControllerMenu: ObservableObject {
    let pointer = PointerModel()
    @Published private(set) var hovered: UUID?
    @Published private(set) var progress = 0.0
    @Published private(set) var active = false
    private(set) var targets: [ControllerMenuTarget] = []
    var size = CGSize.zero
    private var dwell = MenuDwell()
    private var context = ""
    private var readyAt: Double?
    private var armed = false
    private var entryPoint = CGPoint(x: 0.5, y: 0.5)
    private var sourceSession: UUID?
    private var lastMousePoint: CGPoint?
    private let playSound: (WiiAudio.Cue) -> Void
    init(playSound: @escaping (WiiAudio.Cue) -> Void = { WiiAudio.shared.play($0) }) { self.playSound = playSound }
    var diagnostics: [String: Any] {
        ["armed": armed, "readyAt": readyAt ?? -1, "context": context,
         "hovered": hovered?.uuidString ?? "", "progress": progress,
         "pointerSource": String(describing: pointer.source)]
    }

    func setTargets(_ targets: [ControllerMenuTarget]) { self.targets = targets }

    func update(sample: ControllerSnapshot?, time: Double, context: String, enabled: Bool) {
        if self.context != context || sourceSession != sample?.sessionID {
            self.context = context; sourceSession = sample?.sessionID
            reset(); entryPoint = pointer.unitPoint
        }
        guard enabled, let sample, sample.isFresh(at: time) else {
            if active { active = false }; reset()
            if sample == nil || sample!.age(at: time) >= 0.25 {
                pointer.ingestMotion(orientation: simd_quatf(), sampleAge: .infinity, speed: 0, time: time)
            }
            return
        }
        _ = pointer.ingestMotion(orientation: sample.orientation, sampleAge: sample.age(at: time), speed: 0, time: time)
        guard pointer.source == .motion else { if active { active = false }; reset(); return }
        if !active { active = true }
        if readyAt == nil { readyAt = time; entryPoint = pointer.unitPoint }
        if hypot(pointer.unitPoint.x - entryPoint.x, pointer.unitPoint.y - entryPoint.y) > 0.035 { armed = true }
        let point = CGPoint(x: pointer.unitPoint.x * size.width, y: pointer.unitPoint.y * size.height)
        // Smallest wins if an incidental parent/child overlap exists.
        let target = targets.filter { $0.enabled && $0.frame.contains(point) && CGRect(origin: .zero, size: size).intersects($0.frame) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let selected = dwell.update(target: target?.id, time: time, allowed: armed && time - (readyAt ?? time) >= 0.5)
        if hovered != target?.id { hovered = target?.id; if hovered != nil { playSound(.hover) } }
        if progress != dwell.progress { progress = dwell.progress }
        if let selected, let action = targets.first(where: { $0.id == selected && $0.enabled })?.action {
            playSound(.select); action()
        }
    }

    func clickHovered() {
        let point = CGPoint(x: pointer.unitPoint.x * size.width, y: pointer.unitPoint.y * size.height)
        guard let target = targets.first(where: { $0.enabled && $0.frame.contains(point) }) else { return }
        target.action()
    }
    func mouse(_ point: CGPoint, time: Double = ProcessInfo.processInfo.systemUptime) {
        let previous = lastMousePoint; lastMousePoint = point
        guard let previous, hypot(point.x - previous.x, point.y - previous.y) > 0.002 else { return }
        pointer.ingestMouse(point, time: time); if active { active = false }; reset()
    }
    func reset() {
        dwell.reset()
        if hovered != nil { hovered = nil }
        if progress != 0 { progress = 0 }
        readyAt = nil; armed = false
    }
}

private struct ControllerMenuKey: EnvironmentKey { static let defaultValue: ControllerMenu? = nil }
extension EnvironmentValues {
    var controllerMenu: ControllerMenu? {
        get { self[ControllerMenuKey.self] }
        set { self[ControllerMenuKey.self] = newValue }
    }
}
struct ControllerMenuFrames: PreferenceKey {
    static var defaultValue: [ControllerMenuTarget] = []
    static func reduce(value: inout [ControllerMenuTarget], nextValue: () -> [ControllerMenuTarget]) { value += nextValue() }
}

/// Native buttons keep mouse, keyboard and accessibility behavior; the controller invokes the same action.
struct MotionButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    let name: String
    init(id: String = "", action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label(); self.name = id }
    init(_ title: String, action: @escaping () -> Void) where Label == Text {
        self.action = action; self.label = Text(title); self.name = title
    }
    var body: some View {
        Button(action: action) { label }.controllerAction(action, name: name)
    }
}

extension View {
    func controllerAction(_ action: @escaping () -> Void, name: String = "") -> some View { modifier(ControllerTargetModifier(action: action, name: name)) }
}
private struct ControllerTargetModifier: ViewModifier {
    let action: () -> Void
    let name: String
    @State private var id = UUID()
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controllerMenu) private var menu
    func body(content: Content) -> some View {
        content
            .background {
                if menu != nil {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ControllerMenuFrames.self,
                            value: [ControllerMenuTarget(id: id, name: name, frame: geometry.frame(in: .named("controllerMenu")), enabled: enabled, action: action)])
                    }
                }
            }
            .overlay { if let menu { ControllerTargetHighlight(menu: menu, id: id) } }
    }
}

private struct ControllerTargetHighlight: View {
    @ObservedObject var menu: ControllerMenu
    let id: UUID
    var body: some View {
        RoundedRectangle(cornerRadius: 10).stroke(WiiTheme.accentDeep, lineWidth: 3)
            .padding(-4).opacity(menu.active && menu.hovered == id ? 1 : 0).allowsHitTesting(false)
    }
}

/// Read only our own window so a covered screen cannot activate buttons through a sheet.
struct MenuWindowReader: NSViewRepresentable {
    var found: (NSWindow?) -> Void
    final class Reader: NSView {
        var found: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); let window = window; DispatchQueue.main.async { self.found?(window) } }
    }
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.found = found; return view }
    func updateNSView(_ view: Reader, context: Context) { view.found = found }
}
