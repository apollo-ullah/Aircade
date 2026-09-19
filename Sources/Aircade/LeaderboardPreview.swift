import AppKit
import SwiftUI

/// Opt-in layout fixture. Uses a private queue and an in-memory transport; never uploads scores.
enum LeaderboardPreview {
    @MainActor static func run(_ motion: MotionModel) {
        let directory = motion.logDirectory.appendingPathComponent("leaderboard-preview-queue")
        let players = PlayerSession(queueDirectory: directory, automaticRetry: false,
            configurationProvider: { StationConfiguration(url: "https://preview.invalid", token: "fixture") },
            transport: { request in
                let body: String
                if request.url!.path.contains("standing") {
                    body = #"{"difficulty":"Arcade","isPublic":true,"personalBest":3200,"rank":3,"totalPlayers":4,"next":{"rank":2,"nickname":"Test Rival","score":4000,"pointsNeeded":801}}"#
                } else {
                    body = #"{"difficulty":"Arcade","totalPlayers":4,"rows":[{"rank":1,"nickname":"Test Champion","score":6500,"accuracy":98,"bestCombo":22},{"rank":2,"nickname":"Test Rival","score":4000,"accuracy":94,"bestCombo":18},{"rank":3,"nickname":"Test Player","score":3200,"accuracy":90,"bestCombo":12},{"rank":4,"nickname":"Test Rookie","score":900,"accuracy":80,"bestCombo":6}]}"#
                }
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        players.player = BadgePlayer(id: "preview-only", nickname: "Test Player", isPublic: true)
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            Text("SYNTHETIC UI PREVIEW · No real players or scores").font(.caption).padding(8)
            PlayerChannelView(motion: motion, players: players)
        }.background(WiiTheme.stage).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.center(); window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: motion.logDirectory.appendingPathComponent("leaderboard-preview.png"))
                }
            }
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
            NSApp.terminate(nil)
        }
    }
}
