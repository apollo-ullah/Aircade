import AppKit
import SwiftUI

/// UI-only capture; does not connect the arena or call a model.
enum AIChallengePreview {
    static func run(_ motion: MotionModel) {
        motion.selectSport(.tennis)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            capture(motion, name: "ai-tennis-menu")
            motion.tennis.challengeSelected = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                capture(motion, name: "ai-tennis-challenge")
                NSApp.terminate(nil)
            }
        }
    }
    private static func capture(_ motion: MotionModel, name: String) {
        guard let content = NSApp.windows.first?.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: motion.logDirectory.appendingPathComponent("\(name).png"))
        }
    }
}
