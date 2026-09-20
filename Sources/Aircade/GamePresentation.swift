import SwiftUI

/// A channel page extends the home menu's rounded type and glossy surfaces.
/// The scene stays behind gameplay; setup gets a quiet, opaque reading surface.
enum GameIdentity {
    case tennis, rush, duel
    var title: String { switch self { case .tennis: return "Tennis"; case .rush: return "Neon Rush"; case .duel: return "Saber Duel" } }
    var accent: Color { switch self { case .tennis: return Color(red: 0.13, green: 0.49, blue: 0.39); case .rush: return WiiTheme.accentDeep; case .duel: return Color(red: 0.38, green: 0.40, blue: 0.72) } }
    var eyebrow: String { switch self { case .tennis: return "THE RALLY CHALLENGE"; case .rush: return "FIND YOUR FLOW"; case .duel: return "LOCAL MULTIPLAYER" } }
    var subtitle: String { switch self { case .tennis: return "One more shot. One better rally."; case .rush: return "A little swing. A whole lot of play."; case .duel: return "Your couch. Your arena." } }
}

struct GameLobby<HeroDetails: View, Options: View>: View {
    let identity: GameIdentity
    @ViewBuilder var heroDetails: () -> HeroDetails
    @ViewBuilder var options: () -> Options

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("aircade").font(WiiTheme.display(28)).foregroundStyle(WiiTheme.accentDeep)
                        Capsule().fill(WiiTheme.hairline).frame(width: 1, height: 22)
                        Text("\(identity.title) channel").font(WiiTheme.display(15, .medium)).foregroundStyle(WiiTheme.inkSoft)
                        Spacer()
                        Label(identity == .duel ? "2 players" : "1 player", systemImage: identity == .duel ? "person.2.fill" : "person.fill")
                            .font(WiiTheme.display(13, .semibold)).foregroundStyle(WiiTheme.inkSoft)
                    }
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 20) {
                            GameArtwork(identity: identity).frame(height: geometry.size.height < 740 ? 220 : 280)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(identity.eyebrow).font(WiiTheme.display(11)).tracking(2).foregroundStyle(identity.accent)
                                Text(identity.title).font(WiiTheme.display(48)).tracking(-1.8)
                                Text(identity.subtitle).font(WiiTheme.display(19, .medium)).foregroundStyle(WiiTheme.inkSoft)
                            }
                            heroDetails()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: geometry.size.height < 740 ? 14 : 18, content: options)
                            .padding(geometry.size.height < 740 ? 22 : 26).frame(width: 410).wiiPanel(radius: 24)
                    }
                }
                .frame(maxWidth: 1160)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
        }
        .background(WiiTheme.stage).foregroundStyle(WiiTheme.ink)
    }
}

/// Lightweight native artwork: crisp at any display scale, with no asset downloads.
struct GameArtwork: View {
    let identity: GameIdentity
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color.white, identity.accent.opacity(0.12), identity.accent.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.65), lineWidth: 1).frame(width: 320, height: 320).offset(x: 130, y: -60)
                Circle().stroke(.white.opacity(0.5), lineWidth: 24).frame(width: 390, height: 390).offset(x: 130, y: -60)
                switch identity {
                case .tennis:
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(identity.accent.opacity(0.12))
                        Rectangle().stroke(.white.opacity(0.9), lineWidth: 3).padding(18)
                        Rectangle().fill(.white.opacity(0.9)).frame(height: 3)
                        Rectangle().fill(.white.opacity(0.9)).frame(width: 3).padding(.vertical, 18)
                        Image(systemName: "figure.tennis").font(.system(size: 116, weight: .medium)).foregroundStyle(identity.accent)
                            .shadow(color: .white, radius: 0, x: 3, y: 3)
                    }.frame(width: geo.size.width * 0.72, height: 175).rotationEffect(.degrees(-9))
                    Circle().fill(Color(red: 0.79, green: 0.9, blue: 0.28)).frame(width: 45, height: 45)
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2).padding(8))
                        .shadow(color: identity.accent.opacity(0.2), radius: 8, y: 12).offset(x: 140, y: -60)
                case .rush:
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(index == 0 ? Color(red: 0.34, green: 0.7, blue: 0.5) : index == 1 ? WiiTheme.accentDeep : Color(red: 0.85, green: 0.39, blue: 0.4))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.9), lineWidth: 3))
                            .overlay(Image(systemName: index == 0 ? "sparkle" : index == 1 ? "arrow.down" : "xmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
                            .frame(width: 78, height: 78).rotationEffect(.degrees(index == 1 ? 10 : -12))
                            .shadow(color: identity.accent.opacity(0.18), radius: 12, y: 12)
                            .offset(x: CGFloat(index - 1) * 123, y: index == 1 ? -28 : 22)
                    }
                    Capsule().fill(.white).frame(width: 270, height: 7).rotationEffect(.degrees(-30)).offset(x: -50, y: 55)
                        .shadow(color: WiiTheme.accent, radius: 8)
                case .duel:
                    blade(color: WiiTheme.accent, angle: -40).offset(x: -10)
                    blade(color: .orange, angle: 40).offset(x: 10)
                    Image(systemName: "sparkle").font(.system(size: 42)).foregroundStyle(.white).offset(y: -18)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(WiiTheme.hairline, lineWidth: 1))
        }.accessibilityHidden(true)
    }
    private func blade(color: Color, angle: Double) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(.white).frame(width: 13, height: 155)
                .overlay(Capsule().stroke(color, lineWidth: 4)).shadow(color: color.opacity(0.65), radius: 10)
            RoundedRectangle(cornerRadius: 5).fill(WiiTheme.ink).frame(width: 19, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 2))
        }.rotationEffect(.degrees(angle))
    }
}

struct GamePrimaryAction: View {
    var title: String
    var symbol = "play.fill"
    var accent = WiiTheme.accentDeep
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
            Text(title)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
        }.font(WiiTheme.display(17)).padding(.horizontal, 22).frame(minHeight: 58)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [accent, accent.opacity(0.85)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: accent.opacity(0.2), radius: 8, y: 4)
    }
}

struct GameActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(enabled ? 1 : 0.45).scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GameOption: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    var accent = WiiTheme.accentDeep
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(WiiTheme.display(15))
                Text(detail).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 19)).foregroundStyle(selected ? accent : WiiTheme.hairline)
        }.foregroundStyle(selected ? accent : WiiTheme.ink).padding(15).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(selected ? accent.opacity(0.08) : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent : WiiTheme.hairline, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GameRule: View {
    let symbol: String
    let title: String
    let detail: String
    var color = WiiTheme.accentDeep
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                .frame(width: 40, height: 40).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(WiiTheme.display(14))
                Text(detail).font(WiiTheme.body(12)).foregroundStyle(WiiTheme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GameMetric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(WiiTheme.display(25)).monospacedDigit()
            Text(label).font(WiiTheme.display(10, .semibold)).foregroundStyle(WiiTheme.inkSoft)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GameOverlay<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.06, green: 0.14, blue: 0.2).opacity(0.65).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22, content: content)
                        .padding(32).frame(width: min(620, geometry.size.width - 48)).wiiPanel(radius: 28)
                        .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            }
        }.foregroundStyle(WiiTheme.ink)
    }
}

struct GameCountdown: View {
    let value: Double
    let title: String
    let hint: String
    var body: some View {
        VStack(spacing: 15) {
            Text(title).font(WiiTheme.display(16)).tracking(2)
            Text("\(max(1, Int(ceil(value))))").font(WiiTheme.display(112))
                .frame(width: 180, height: 180)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 3))
            Text(hint).font(WiiTheme.display(17, .medium))
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.32)).allowsHitTesting(false)
    }
}

extension View {
    func gameReadout() -> some View {
        padding(.horizontal, 20).padding(.vertical, 15)
            .background(Color(red: 0.06, green: 0.13, blue: 0.19).opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
