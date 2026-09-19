import SwiftUI

enum SportsTheme {
    static let blue = Color(red: 0.04, green: 0.48, blue: 0.72)
    static let green = Color(red: 0.24, green: 0.63, blue: 0.18)
    static let ink = Color(red: 0.20, green: 0.29, blue: 0.34)
    static let paper = Color(red: 0.93, green: 0.97, blue: 0.99)
}

extension View {
    func scoreboard() -> some View {
        self.padding(.horizontal, 18).padding(.vertical, 12)
            .background(LinearGradient(colors: [Color(red: 0.09, green: 0.19, blue: 0.23).opacity(0.76), .black.opacity(0.58)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.45), lineWidth: 1))
    }
    func sportsPanel() -> some View {
        self.background(LinearGradient(colors: [.white, SportsTheme.paper.opacity(0.97)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.95), lineWidth: 1))
            .shadow(color: SportsTheme.blue.opacity(0.16), radius: 2, y: 1)
    }
}

struct SportsButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? .white : SportsTheme.blue)
            .background(LinearGradient(colors: primary ? [Color(red: 0.17, green: 0.72, blue: 0.91), SportsTheme.blue] : [.white, SportsTheme.paper], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? SportsTheme.blue : SportsTheme.blue.opacity(0.35), lineWidth: 1.5))
            .shadow(color: SportsTheme.blue.opacity(0.16), radius: 1, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}
