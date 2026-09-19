import SwiftUI

enum Route: Hashable {
    case home, neonRush, tennis, duel, avatar, profile, controller, lab, scripts, settings
}

struct Channel: Identifiable {
    let route: Route
    let title: String
    /// SF Symbol standing in for the animated banner until each channel gets
    /// its own artwork.
    let symbol: String
    var id: Route { route }
}

enum ChannelCatalog {
    /// Only working channels appear in the public menu.
    static let all: [Channel] = [
        Channel(route: .tennis, title: "Tennis", symbol: "figure.tennis"),
        Channel(route: .neonRush, title: "Neon Rush", symbol: "bolt.fill"),
        Channel(route: .duel, title: "Saber Duel", symbol: "person.2.fill"),
        Channel(route: .controller, title: "Controllers", symbol: "gamecontroller.fill"),
        Channel(route: .profile, title: "Leaderboard", symbol: "person.crop.circle"),
        Channel(route: .lab, title: "Practice", symbol: "target")
    ]

    /// Which channel a unit-space cursor point is over, if any.
    static func channel(at unitPoint: CGPoint, frames: [Route: CGRect], in size: CGSize) -> Route? {
        let point = CGPoint(x: unitPoint.x * size.width, y: unitPoint.y * size.height)
        return frames.first { $0.value.contains(point) }?.key
    }
}

extension Notification.Name {
    /// Legacy name retained for the Space shortcut. Motion selection uses dwell.
    static let wiiPointerFlick = Notification.Name("WiiPointerFlick")
    static let wiiRouteRequest = Notification.Name("WiiRouteRequest")
}

/// Reports each tile's frame up to the grid so the cursor can be hit-tested
/// against the same geometry SwiftUI laid out.
struct ChannelFramesKey: PreferenceKey {
    static var defaultValue: [Route: CGRect] = [:]
    static func reduce(value: inout [Route: CGRect], nextValue: () -> [Route: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ChannelGrid: View {
    var open: (Route) -> Void


    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    Text("aircade").font(WiiTheme.display(44)).foregroundStyle(WiiTheme.accentDeep)
                    Spacer()
                    Text("Tilt to aim · hold for 1 second to open").font(WiiTheme.display(18, .medium)).foregroundStyle(WiiTheme.inkSoft)
                }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(ChannelCatalog.all) { channel in
                    tile(channel, height: min(230, max(160, (geo.size.height - 180) / 2)))

                }
            }
            }
            .padding(.horizontal, max(26, (geo.size.width - 1160) / 2))
            .padding(.top, 38)

        }
        .background(WiiTheme.stage)
    }

    private func tile(_ channel: Channel, height: CGFloat) -> some View {
        MotionButton(id: "channel-\(channel.route)") { open(channel.route) } label: {
            VStack(spacing: 0) {
                // The sweep goes over the banner, which is artwork only. The
                // name strip below it stays clear so the label reads crisply.
                Image(systemName: channel.symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(WiiTheme.accentDeep)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WiiTheme.panelFill)
                    .gloss(0)
                Text(channel.title)
                    .font(WiiTheme.display(16, .bold))
                    .foregroundStyle(WiiTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(WiiTheme.barFill)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: WiiTheme.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: WiiTheme.tileRadius).stroke(WiiTheme.hairline, lineWidth: 1))
            .shadow(color: WiiTheme.shadow.opacity(0.12), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.title)
    }
}
