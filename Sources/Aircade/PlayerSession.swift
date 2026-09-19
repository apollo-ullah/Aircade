import Foundation
import CryptoKit
import SwiftUI
import MotionCore

struct BadgePlayer: Codable {
    var id: String
    var nickname: String
    var isPublic: Bool
    var needsName: Bool? = nil
}
struct BadgeRun: Codable {
    var id: String
    var playerID: String
    var difficulty: String
    var score: Int
    var cuts: Int
    var bestCombo: Int
    var accuracy: Int
    var completed: Bool
    var isDemo: Bool
    var gameVersion: String
}
struct StationConfiguration: Codable {
    let url: String
    let token: String
}
final class PlayerSession: ObservableObject {
    @Published var player: BadgePlayer?
    @Published var showingSignIn = false
    @Published var suggestedName: String?
    @Published var busy = false
    @Published var bests: [String: Int] = [:]
    @Published var message = "Scan your badge before playing a ranked round."
    @Published var saveStatus = ""
    private var runIdentity: (id: String, playerID: String)?
    private var pending: [BadgeRun] = []
    private var uploading = false
    private var retryTimer: Timer?
    private let queueURL: URL
    private var configuration: StationConfiguration? {
        let path = ProcessInfo.processInfo.environment["AIRCADE_STATION_CONFIG"]
        let url = path.map { URL(fileURLWithPath: $0) } ?? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".local/station.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StationConfiguration.self, from: $0) }
    }
    var leaderboardURL: URL { URL(string: configuration?.url ?? "") ?? URL(string: "http://127.0.0.1:8787")! }
    init(queueDirectory: URL? = nil, automaticRetry: Bool = true) {
        let directory = queueDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aircade", isDirectory: true)
        queueURL = directory.appendingPathComponent("pending-runs.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: queueURL.path) { pending = try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: queueURL)) }
        } catch { saveStatus = "Could not read saved upload queue: \(error.localizedDescription)" }
        if automaticRetry {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.flush() }
            flush()
        }
    }
    func authorize() -> Bool {
        guard player != nil else { showingSignIn = true; return false }
        return true
    }
    func beginRun(demo: Bool) {
        runIdentity = demo ? nil : player.map { (UUID().uuidString, $0.id) }
        saveStatus = demo ? "Demo and scripted scores are not saved." : ""
    }
    func finishRun(_ state: NeonRush, demo: Bool) {
        guard !demo, let identity = runIdentity else { return }
        runIdentity = nil
        pending.append(BadgeRun(id: identity.id, playerID: identity.playerID, difficulty: state.difficulty.rawValue,
                               score: state.score, cuts: state.cuts, bestCombo: state.bestCombo, accuracy: state.accuracy,
                               completed: state.completed, isDemo: false, gameVersion: "0.4.0"))
        persistQueue(); flush()
    }
    private func persistQueue() {
        do { try JSONEncoder().encode(pending).write(to: queueURL, options: .atomic) }
        catch { saveStatus = "Score is in memory only; disk save failed: \(error.localizedDescription)" }
    }
    func logout() {
        player = nil
        suggestedName = nil
        bests = [:]
        runIdentity = nil
        message = "Logged out. Scan your badge to load your profile and high scores."
        showingSignIn = false
    }
    func nextPlayer() {
        logout()
        message = "Scan the next player’s badge."
        showingSignIn = true
    }
    func signIn(_ raw: String, suggestedName candidateName: String? = nil) {
        let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !payload.isEmpty, payload.utf8.count <= 4096 else { message = "Enter a badge code (up to 4096 bytes)."; return }
        busy = true; message = "Finding your player profile…"
        let digest = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await request("/api/sign-in", method: "POST", body: ["badgeDigest": digest])
                let found = try JSONDecoder().decode(BadgePlayer.self, from: data)
                let needsName = found.needsName ?? (found.nickname == "Player " + found.id.prefix(6))
                suggestedName = needsName ? candidateName.flatMap(BadgeNameReader.clean) : nil
                bests = [:]
                player = found
                refreshBests()
                message = suggestedName == nil ? "Welcome! Choose your nickname and leaderboard visibility." : "Name read from your badge. Confirm or correct it before saving."
            } catch { message = error.localizedDescription }
        }
    }
    func saveProfile(nickname: String, isPublic: Bool) {
        guard let player, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await request("/api/players/\(player.id)", method: "PATCH", body: ["nickname": nickname, "isPublic": isPublic])
                self.player = try JSONDecoder().decode(BadgePlayer.self, from: data)
                suggestedName = nil
                message = "Ready to play"; showingSignIn = false
            } catch { message = error.localizedDescription }
        }
    }
    func flush() {
        guard !uploading, !pending.isEmpty else { return }
        uploading = true
        Task { @MainActor in
            defer { uploading = false }
            while let run = pending.first {
                do {
                    let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
                    _ = try await request("/api/runs", method: "POST", body: body)
                    pending.removeFirst(); persistQueue(); saveStatus = "Score saved to MongoDB."; refreshBests()
                } catch { saveStatus = "Score queued — \(error.localizedDescription) Retrying automatically."; return }
            }
        }
    }
    func refreshBests() {
        guard let id = player?.id else { return }
        Task { @MainActor in
            guard let data = try? await request("/api/players/\(id)/bests", method: "GET", body: [:]), player?.id == id else { return }
            bests = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        }
    }
    private func request(_ path: String, method: String, body: [String: Any]) async throws -> Data {
        guard let config = configuration, let base = URL(string: config.url), let scheme = base.scheme,
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(base.host ?? "")) else {
            throw NSError(domain: "Aircade", code: 1, userInfo: [NSLocalizedDescriptionKey: "Start the local server first (scripts/start-station.sh)."])
        }
        var request = URLRequest(url: base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.timeoutInterval = 8
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "Server request failed."
            throw NSError(domain: "Aircade", code: 2, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return data
    }
}
