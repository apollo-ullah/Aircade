import AVFoundation

/// Synthesized interaction sounds. Nothing is bundled or downloaded; every cue
/// is generated in process, so the repo carries no third-party audio.
final class WiiAudio {
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

    /// Enabled by default; Settings toggles it.
    var enabled = true

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private let queue = DispatchQueue(label: "Aircade.WiiAudio", qos: .userInitiated)
    private var started = false
    private var music: AVAudioPlayer?

    private init() {}

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
        queue.async { [self] in
            startIfNeeded()
            guard let buffer = buffers[cue] else { return }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        }
    }

    /// Plays a track the user has placed in `Resources/Music/` beside the app
    /// bundle. Nothing ships in that folder and it is gitignored, so this is a
    /// no-op on a clean checkout.
    func startMusic() {
        guard enabled, music == nil else { return }
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources/Music", isDirectory: true)
        let tracks = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                   includingPropertiesForKeys: nil))?
            .filter { ["mp3", "m4a", "wav", "aiff"].contains($0.pathExtension.lowercased()) }
        guard let track = tracks?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
              let player = try? AVAudioPlayer(contentsOf: track) else { return }
        player.numberOfLoops = -1
        player.volume = 0.35
        player.play()
        music = player
    }

    func stopMusic() {
        music?.stop()
        music = nil
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        for cue in Cue.allCases {
            let samples = Self.tone(frequency: cue.frequency, duration: cue.duration,
                                    sampleRate: format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            buffers[cue] = buffer
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }
}
