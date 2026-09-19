import SwiftUI

/// Compatibility shim. The Wii system-menu palette lives in `WiiTheme`; these
/// names forward to it until every screen has migrated, then this file is
/// deleted (see Task 8).
enum SportsTheme {
    static let blue = WiiTheme.accentDeep
    static let green = Color(red: 0.24, green: 0.63, blue: 0.18)
    static let ink = WiiTheme.ink
    static let paper = WiiTheme.stageMid
}

typealias SportsButtonStyle = WiiButtonStyle

extension View {
    func sportsPanel() -> some View { wiiPanel() }
    func scoreboard() -> some View { wiiReadout() }
}
