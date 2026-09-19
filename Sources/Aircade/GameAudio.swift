import AppKit

/// Sound lookup and device startup can take hundreds of milliseconds even though
/// playback itself is asynchronous. Keep both off the motion/render run loop.
final class GameAudio {
    static let shared = GameAudio()
    private let queue = DispatchQueue(label: "Aircade.SoundEffects", qos: .userInitiated)
    // All sound objects are created and used on this one queue.
    private var sounds: [String: NSSound] = [:]
    private init() {}

    func play(_ name: String) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            // Drop obsolete queued cues instead of replaying a backlog after an audio stall.
            guard ProcessInfo.processInfo.systemUptime - requested < 0.3 else { return }
            let sound: NSSound?
            if let cached = sounds[name] { sound = cached }
            else {
                sound = NSSound(named: NSSound.Name(name))
                sounds[name] = sound
            }
            _ = sound?.play()
        }
    }
}
