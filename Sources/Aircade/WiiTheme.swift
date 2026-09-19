import SwiftUI

/// The Wii system-menu design language: near-white glossy surfaces, a cyan-blue
/// accent, hairline borders, and generous corner radii.
enum WiiTheme {
    static let stageTop = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let stageMid = Color(red: 0.933, green: 0.957, blue: 0.973)
    static let stageEdge = Color(red: 0.843, green: 0.890, blue: 0.925)
    static let panelTop = Color.white
    static let panelBottom = Color(red: 0.910, green: 0.941, blue: 0.965)
    static let hairline = Color(red: 0.800, green: 0.851, blue: 0.890)
    static let accent = Color(red: 0.247, green: 0.714, blue: 0.910)
    static let accentDeep = Color(red: 0.169, green: 0.576, blue: 0.800)
    static let ink = Color(red: 0.275, green: 0.349, blue: 0.416)
    static let inkSoft = Color(red: 0.420, green: 0.525, blue: 0.596)
    static let barTop = Color(red: 0.957, green: 0.973, blue: 0.984)
    static let barBottom = Color(red: 0.859, green: 0.902, blue: 0.933)
    static let shadow = Color(red: 0.118, green: 0.275, blue: 0.392)

    static let tileRadius: CGFloat = 18
    static let panelRadius: CGFloat = 12

    static var stage: RadialGradient {
        RadialGradient(colors: [stageTop, stageMid, stageEdge],
                       center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: 900)
    }
    static var panelFill: LinearGradient {
        LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom)
    }
    static var accentFill: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }
    static var barFill: LinearGradient {
        LinearGradient(colors: [barTop, barBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Channel names, headings, buttons.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Body copy, numbers, diagnostics.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// The glossy near-white surface every Wii panel sits on: a highlight sweep
/// across the top 46% of the shape. This is a *surface*, drawn behind content,
/// because a sweep laid over body text washes it out.
struct WiiSurface: View {
    var radius: CGFloat
    var fill: LinearGradient = WiiTheme.panelFill
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                fill
                LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0.20)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.46)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .allowsHitTesting(false)
    }
}

extension View {
    /// Lays the highlight sweep *over* this view. Only for artwork — channel
    /// banners and icons. Never put it over body text: it fades the text. Text
    /// surfaces use `wiiPanel()`, which composites the sweep behind content.
    func gloss(_ radius: CGFloat) -> some View {
        overlay(alignment: .top) {
            GeometryReader { geo in
                LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0.20)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.46)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    func wiiPanel(radius: CGFloat = WiiTheme.panelRadius) -> some View {
        background { WiiSurface(radius: radius) }
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(WiiTheme.hairline, lineWidth: 1))
            .shadow(color: WiiTheme.shadow.opacity(0.10), radius: 2, y: 1)
    }

    /// Translucent dark readout that floats over the 3D scene during play. Dark
    /// on purpose: the HUD's text is white and the stage behind it is bright.
    func wiiReadout() -> some View {
        padding(.horizontal, 18).padding(.vertical, 12)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.28), lineWidth: 1))
    }
}

struct WiiButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WiiTheme.display(13, .semibold))
            .padding(.horizontal, 20).padding(.vertical, 10)
            .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(WiiTheme.accentDeep))
            .background(primary ? AnyShapeStyle(WiiTheme.accentFill) : AnyShapeStyle(WiiTheme.panelFill),
                        in: Capsule())
            .overlay(Capsule().stroke(primary ? WiiTheme.accentDeep : WiiTheme.hairline, lineWidth: 1))
            .shadow(color: WiiTheme.shadow.opacity(0.16), radius: 2, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}
