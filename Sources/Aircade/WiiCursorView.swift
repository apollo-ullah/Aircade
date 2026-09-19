import SwiftUI

/// The pointing hand. Drawn as an overlay in window coordinates so it floats
/// above every channel without participating in their layout.
struct WiiCursorView: View {
    @ObservedObject var pointer: PointerModel
    @ObservedObject var menu: ControllerMenu
    var size: CGSize

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.7), lineWidth: 3).frame(width: 46, height: 46)
            Circle().trim(from: 0, to: menu.progress).stroke(WiiTheme.accentDeep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 46, height: 46).rotationEffect(.degrees(-90))
            Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 26))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
            .opacity(pointer.source == .motion ? 1 : 0)
            .position(x: pointer.unitPoint.x * size.width,
                      y: pointer.unitPoint.y * size.height)
            .allowsHitTesting(false)
    }
}
