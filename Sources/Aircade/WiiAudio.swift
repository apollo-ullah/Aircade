import AVFoundation

/// Synthesized interaction sounds. Nothing is bundled or downloaded; every cue
/// is generated in process, so the repo carries no third-party audio.
final class WiiAudio: @unchecked Sendable {
    static let shared = WiiAudio()

    enum Cue: CaseIterable {
        case hover, select, open, close, save

        var frequency: Double {
            switch self {
            case .hover: return 880
            case .select: return 1_320
            case .open: return 1_760
            case .close: return 660
            case .save: return 1_046
            }
        }
        var duration: Double {
            switch self {
            case .hover: return 0.045
            case .select: return 0.075
            case .open, .close: return 0.13
            case .save: return 0.2
            }
        }
    }

    /// UserDefaults is thread-safe; all player work stays on the audio queue.
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "aircade.menuAudio") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "aircade.menuAudio")
            queue.async { [self] in
                if newValue { startMusicIfNeeded() }
                else { music?.pause(); activeCue?.stop() }
            }
        }
    }

    private var cues: [Cue: AVAudioPlayer] = [:]
    private var activeCue: AVAudioPlayer?
    private let queue = DispatchQueue(label: "Aircade.WiiAudio", qos: .userInitiated)
    private var music: AVAudioPlayer?
    private var musicRequested = false
    private let output = AudioOutput.shared
    private var outputObserver: NSObjectProtocol?

    private init() {
        outputObserver = NotificationCenter.default.addObserver(forName: .aircadeAudioOutputChanged, object: nil, queue: nil) { [weak self] note in
            guard let self, note.object as? AudioOutput === self.output else { return }
            self.queue.async { [weak self] in self?.reroute() }
        }
    }

    /// A short sine burst with a raised-cosine envelope, so it fades in and out
    /// instead of clicking at the buffer edges.
    static func tone(frequency: Double, duration: Double, sampleRate: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let envelope = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(max(1, count - 1)))
            return Float(sin(2 * .pi * frequency * t) * envelope * 0.25)
        }
    }

    func play(_ cue: Cue) {
        guard enabled else { return }
        let requested = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard enabled, ProcessInfo.processInfo.systemUptime - requested < 0.3,
                  let destination = output.destination else { return }
            if cues[cue] == nil {
                let samples = Self.tone(frequency: cue.frequency, duration: cue.duration, sampleRate: 44_100)
                cues[cue] = try? AVAudioPlayer(data: Self.wave(samples: samples))
            }
            guard let player = cues[cue] else { return }
            activeCue?.stop()
            player.currentDevice = destination.uid
            player.currentTime = 0
            if !player.play() { output.reportPlaybackFailure() }
            activeCue = player
        }
    }

    /// Plays a track the user has placed in `Resources/Music/` beside the app
    /// bundle. Nothing ships in that folder and it is gitignored, so this is a
    /// no-op on a clean checkout.
    func startMusic() {
        queue.async { [self] in musicRequested = true; startMusicIfNeeded() }
    }

    private func startMusicIfNeeded() {
        guard enabled, musicRequested, let destination = output.destination else { return }
        if let music {
            music.currentDevice = destination.uid
            if !music.isPlaying, !music.play() { output.reportPlaybackFailure() }
            return
        }
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources/Music", isDirectory: true)
        let tracks = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                   includingPropertiesForKeys: nil))?
            .filter { ["mp3", "m4a", "wav", "aiff"].contains($0.pathExtension.lowercased()) }
        guard let track = tracks?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
              let player = try? AVAudioPlayer(contentsOf: track) else { return }
        player.numberOfLoops = -1
        player.volume = 0.35
        player.currentDevice = destination.uid
        if !player.play() { output.reportPlaybackFailure() }
        music = player
    }

    func stopMusic() {
        queue.async { [self] in
            musicRequested = false
            music?.stop(); music = nil
        }
    }

    private func reroute() {
        activeCue?.stop()
        music?.pause()
        // Keep the existing playback position; never fall back to AirPods if speakers disappear.
        startMusicIfNeeded()
    }

    func outputDeviceUIDs() async -> [String: String] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var devices: [String: String] = [:]
                if let uid = music?.currentDevice { devices["music"] = uid }
                if let uid = activeCue?.currentDevice { devices["menuCue"] = uid }
                continuation.resume(returning: devices)
            }
        }
    }

    /// Small in-memory PCM clips let music and synthesized cues use the same UID routing API.
    static func wave(samples: [Float], sampleRate: UInt32 = 44_100) -> Data {
        var data = Data()
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: "RIFF".utf8); number(36 + bytes)
        data.append(contentsOf: "WAVEfmt ".utf8); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(sampleRate); number(sampleRate * 2)
        number(UInt16(2)); number(UInt16(16))
        data.append(contentsOf: "data".utf8); number(bytes)
        for sample in samples { number(Int16(max(-1, min(1, sample)) * 32767)) }
        return data
    }
}
