import SwiftUI

/// The pointing hand. Drawn as an overlay in window coordinates so it floats
/// above every channel without participating in their layout.
struct WiiCursorView: View {
    @ObservedObject var pointer: PointerModel
    var size: CGSize

    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 26))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .opacity(pointer.source == .motion ? 1 : 0)
            .position(x: pointer.unitPoint.x * size.width,
                      y: pointer.unitPoint.y * size.height)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85),
                       value: pointer.unitPoint)
            .allowsHitTesting(false)
    }
}
