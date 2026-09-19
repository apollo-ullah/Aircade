import AppKit

/// Sound lookup and device startup can take hundreds of milliseconds even though
/// playback itself is asynchronous. Keep both off the motion/render run loop.
final class GameAudio: @unchecked Sendable {
    static let shared = GameAudio()
    private let queue = DispatchQueue(label: "Aircade.SoundEffects", qos: .userInitiated)
    // All sound objects are created and used on this one queue.
    private var sounds: [String: NSSound] = [:]
    private let output = AudioOutput.shared
    private var outputObserver: NSObjectProtocol?
    private init() {
        outputObserver = NotificationCenter.default.addObserver(forName: .aircadeAudioOutputChanged, object: nil, queue: nil) { [weak self] note in
            guard let self, note.object as? AudioOutput === self.output else { return }
            self.queue.async { [weak self] in
                self?.sounds.values.forEach { $0.stop() }
            }
        }
    }

    func play(_ name: String) {
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            // Drop obsolete queued cues instead of replaying a backlog after an audio stall.
            guard ProcessInfo.processInfo.systemUptime - requested < 0.3,
                  let destination = output.destination else { return }
            let sound: NSSound?
            if let cached = sounds[name] { sound = cached }
            else {
                sound = NSSound(named: NSSound.Name(name))
                sounds[name] = sound
            }
            sound?.playbackDeviceIdentifier = destination.uid
            if sound?.play() == false { output.reportPlaybackFailure() }
        }
    }

    func outputDeviceUIDs() async -> [String: String] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: sounds.compactMapValues { $0.playbackDeviceIdentifier })
            }
        }
    }
}
