import AppKit

/// Opt-in on-device check. Plays a short cue and checks each player's configured UID.
/// It cannot measure acoustic output or Bluetooth/motion latency.
enum AudioOutputCheck {
    @MainActor static func run(_ motion: MotionModel) {
        let output = AudioOutput.shared
        let originalPreference = output.preference
        let originalEnabled = WiiAudio.shared.enabled
        let systemBefore = AudioDeviceCatalog.defaultOutputID()
        output.select(.speakers)
        Task { @MainActor in
            for _ in 0..<100 {
                if output.destination?.isBuiltInSpeaker == true { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            WiiAudio.shared.enabled = true
            WiiAudio.shared.startMusic()
            WiiAudio.shared.play(.save)
            GameAudio.shared.play("Glass")
            let menu = await WiiAudio.shared.outputDeviceUIDs()
            let effects = await GameAudio.shared.outputDeviceUIDs()
            let destination = output.destination
            let systemAfter = AudioDeviceCatalog.defaultOutputID()
            let folder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/Music")
            let hasMusic = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .contains { ["mp3", "m4a", "wav", "aiff"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            let passed = destination?.isBuiltInSpeaker == true && systemBefore == systemAfter &&
                menu["menuCue"] == destination?.uid && effects["Glass"] == destination?.uid &&
                (!hasMusic || menu["music"] == destination?.uid)
            let report: [String: Any] = ["passed": passed, "output": destination?.name ?? "Unavailable",
                "menuCueRouted": menu["menuCue"] == destination?.uid && menu["menuCue"] != nil,
                "gameEffectRouted": effects["Glass"] == destination?.uid && effects["Glass"] != nil,
                "musicPresent": hasMusic, "musicRouted": menu["music"] == destination?.uid && menu["music"] != nil,
                "systemDefaultUnchanged": systemBefore == systemAfter, "acousticOutputVerified": false]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: motion.logDirectory.appendingPathComponent("audio-output-check.json"))
            }
            NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.settings)
            try? await Task.sleep(for: .milliseconds(600))
            if let content = NSApp.windows.first?.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let image = bitmap.representation(using: .png, properties: [:]) {
                    try? image.write(to: motion.logDirectory.appendingPathComponent("audio-settings.png"))
                }
            }
            output.select(originalPreference)
            WiiAudio.shared.enabled = originalEnabled
            NSApp.terminate(nil)
        }
    }
}
