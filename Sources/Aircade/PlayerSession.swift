import Foundation
import CryptoKit
import SwiftUI
import MotionCore

struct BadgePlayer: Codable, Equatable {
    var id: String
    var nickname: String
    var isPublic: Bool
    var needsName: Bool? = nil
}
struct BadgeRun: Codable, Equatable {
    var id: String
    var playerID: String
    var game: String? = nil
    var difficulty: String
    var score: Int
    var cuts: Int
    var bestCombo: Int
    var accuracy: Int
    var completed: Bool
    var isDemo: Bool
    var gameVersion: String
}
struct StationConfiguration: Codable, Sendable {
    let url: String
    let token: String
}
final class PlayerSession: ObservableObject {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    @Published var player: BadgePlayer?
    @Published var showingSignIn = false
    @Published var suggestedName: String?
    @Published var busy = false
    @Published var bests: [String: Int] = [:]
    @Published var message = "Ready to play as a guest. Sign in to save scores to your profile."
    @Published var saveStatus = ""
    @Published private(set) var leaderboards: [String: LeaderboardBoard] = [:]
    @Published private(set) var standings: [String: LeaderboardStanding] = [:]
    @Published private(set) var leaderboardStatus: [String: String] = [:]
    @Published private(set) var leaderboardMode = "Arcade"
    @Published private(set) var lastRankProgress: RankProgress?
    private var boardRequests: [String: UUID] = [:]
    @Published private(set) var activeRun: RunContext?
    private var pending: [BadgeRun] = []
    private var uploading = false
    private var retryTimer: Timer?
    private let queueURL: URL
    private let configurationProvider: () -> StationConfiguration?
    private let transport: Transport
    private let uploadOnFinish: Bool
    private var profileRevision = 0
    // SwiftUI reads this memory snapshot. File access must never happen while
    // evaluating profilesAvailable or a view's leaderboard link.
    @Published private var configuration: StationConfiguration?

    static func configurationURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 bundleURL: URL = Bundle.main.bundleURL,
                                 supportDirectory: URL? = nil) -> URL {
        if let path = environment["AIRCADE_STATION_CONFIG"] { return URL(fileURLWithPath: path) }
        let root = bundleURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        let identifier = SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        let support = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let staged = support.appendingPathComponent("Aircade/Stations/\(identifier).json")
        // This resolver is called by the background reader, never by view getters.
        return FileManager.default.fileExists(atPath: staged.path) ? staged : root.appendingPathComponent(".local/station.json")
    }

    static func loadConfiguration() -> StationConfiguration? {
        (try? Data(contentsOf: configurationURL())).flatMap { try? JSONDecoder().decode(StationConfiguration.self, from: $0) }
    }

    // The lock protects the only mutable field across completion and timeout.
    private final class ConfigurationRead: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<StationConfiguration?, Never>?
        init(_ continuation: CheckedContinuation<StationConfiguration?, Never>) { self.continuation = continuation }
        func finish(_ value: StationConfiguration?) {
            lock.lock()
            let callback = continuation
            continuation = nil
            lock.unlock()
            callback?.resume(returning: value)
        }
    }

    /// A filesystem permission dialog can stall open(). Race that background
    /// operation against a bounded response without waiting for the blocked read.
    static func loadConfigurationAsync(provider: @escaping () -> StationConfiguration? = PlayerSession.loadConfiguration,
                                       timeout: TimeInterval = 2) async -> StationConfiguration? {
        await withCheckedContinuation { continuation in
            let read = ConfigurationRead(continuation)
            DispatchQueue.global(qos: .utility).async { read.finish(provider()) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { read.finish(nil) }
        }
    }

    @MainActor
    private func refreshConfiguration() async -> StationConfiguration? {
        let loaded = await Self.loadConfigurationAsync(provider: configurationProvider)
        configuration = loaded
        return loaded
    }
    var leaderboardURL: URL { URL(string: configuration?.url ?? "") ?? URL(string: "http://127.0.0.1:8787")! }
    func leaderboardURL(for mode: String) -> URL {
        var components = URLComponents(url: leaderboardURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "mode", value: mode)]
        return components.url!
    }
    var pendingRuns: [BadgeRun] { pending }
    var profilesAvailable: Bool { configuration != nil }

    init(queueDirectory: URL? = nil, automaticRetry: Bool = true, uploadOnFinish: Bool = true,
         configurationProvider: (() -> StationConfiguration?)? = nil,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.configurationProvider = configurationProvider ?? PlayerSession.loadConfiguration
        // Injected providers are in-memory fixtures; preserve their immediate
        // availability without making production disk reads synchronous.
        self.configuration = configurationProvider?()
        self.transport = transport
        self.uploadOnFinish = uploadOnFinish
        let directory = queueDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aircade", isDirectory: true)
        queueURL = directory.appendingPathComponent("pending-runs.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: queueURL.path) { pending = try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: queueURL)) }
        } catch { saveStatus = "Could not read saved upload queue: \(error.localizedDescription)" }
        if configurationProvider == nil {
            Task { @MainActor [weak self] in _ = await self?.refreshConfiguration() }
        }
        if automaticRetry {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.flush() }
            flush()
        }
    }
    deinit { retryTimer?.invalidate() }

    func authorize() -> Bool {
        // Profile/network availability never gates the start of a game.
        return true
    }

    @discardableResult
    func beginRun(game: ArcadeRunGame, mode: String, simulated: Bool = false, avatarID: String? = nil) -> RunContext {
        let context = RunContext(game: game, mode: mode, player: player, simulated: simulated, avatarID: avatarID)
        activeRun = context
        lastRankProgress = nil
        saveStatus = simulated ? "Demo and scripted scores are not saved." : context.isGuest ? "Guest score stays on this Mac." : ""
        return context
    }

    // Compatibility for the original Neon Rush callback. New adapters supply game and mode explicitly.
    func beginRun(demo: Bool) {
        beginRun(game: .neonRush, mode: "Arcade", simulated: demo)
    }

    func observeInput(simulated: Bool, runID: String? = nil) {
        guard runID == nil || activeRun?.id == runID else { return }
        activeRun?.observeInput(simulated: simulated)
        if activeRun?.isSimulated == true { saveStatus = "Demo and scripted scores are not saved." }
    }

    func canRecordLocalBest(for runID: String) -> Bool {
        activeRun?.id == runID && activeRun?.eligibleForLocalBest == true
    }

    func abandonRun(runID: String? = nil) {
        guard runID == nil || activeRun?.id == runID else { return }
        activeRun = nil
    }

    @discardableResult
    func finishRun(_ state: NeonRush, demo: Bool, runID: String? = nil) -> RunCompletion? {
        guard state.phase == .results else { return nil }
        return finish(game: .neonRush, runID: runID, simulated: demo, difficulty: state.difficulty.rawValue,
                      score: state.score, cuts: state.cuts, bestCombo: state.bestCombo, accuracy: state.accuracy,
                      completed: state.completed)
    }

    @discardableResult
    func finishTennis(_ state: TennisMatch, demo: Bool, runID: String? = nil) -> RunCompletion? {
        guard state.phase == .results else { return nil }
        return finish(game: .tennis, runID: runID, simulated: demo, difficulty: "Tennis",
                      score: state.score, cuts: state.returns, bestCombo: state.longestRally, accuracy: state.accuracy,
                      completed: state.completed)
    }

    /// Duel currently has local results only; its scoring is not part of the station API.
    @discardableResult
    func finishLocalRun(runID: String, simulated: Bool = false) -> RunCompletion? {
        guard var context = activeRun, context.id == runID, context.game == .saberDuel else { return nil }
        context.observeInput(simulated: simulated)
        activeRun = nil
        return RunCompletion(context: context, queuedForProfile: false)
    }

    private func finish(game: ArcadeRunGame, runID: String?, simulated: Bool, difficulty: String,
                        score: Int, cuts: Int, bestCombo: Int, accuracy: Int, completed: Bool) -> RunCompletion? {
        guard var context = activeRun, context.game == game, runID == nil || context.id == runID else { return nil }
        context.observeInput(simulated: simulated)
        // Consume before queueing. Repeated/late result callbacks cannot submit twice.
        activeRun = nil
        guard context.eligibleForProfileUpload, let profile = context.profile else {
            saveStatus = context.isSimulated ? "Demo and scripted scores are not saved." : "Guest score stays on this Mac."
            return RunCompletion(context: context, queuedForProfile: false)
        }
        pending.append(BadgeRun(id: context.id, playerID: profile.id, game: context.game.rawValue, difficulty: difficulty,
                               score: score, cuts: cuts, bestCombo: bestCombo, accuracy: accuracy,
                               completed: completed, isDemo: false, gameVersion: "0.5.0"))
        saveStatus = "Score queued for your profile."
        persistQueue()
        if uploadOnFinish { flush() }
        return RunCompletion(context: context, queuedForProfile: true)
    }
    private func persistQueue() {
        do { try JSONEncoder().encode(pending).write(to: queueURL, options: .atomic) }
        catch { saveStatus = "Score is in memory only; disk save failed: \(error.localizedDescription)" }
    }
    func logout() {
        // Changing the selected profile affects future runs. A running round retains its owner.
        profileRevision += 1
        player = nil
        suggestedName = nil
        bests = [:]
        standings = [:]; lastRankProgress = nil
        message = "Ready to play as a guest. Sign in to save scores to your profile."
        showingSignIn = false
    }
    func selectGuest() { logout() }
    func nextPlayer() {
        logout()
        message = "Scan the next player’s badge."
        showingSignIn = true
    }
    func signIn(_ raw: String, suggestedName candidateName: String? = nil) {
        let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !payload.isEmpty, payload.utf8.count <= 4096 else { message = "Enter a badge code (up to 4096 bytes)."; return }
        busy = true; message = "Finding your player profile…"
        let revision = profileRevision
        let digest = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await request("/api/sign-in", method: "POST", body: ["badgeDigest": digest])
                guard profileRevision == revision else { return }
                let found = try JSONDecoder().decode(BadgePlayer.self, from: data)
                let needsName = found.needsName ?? (found.nickname == "Player " + found.id.prefix(6))
                suggestedName = needsName ? candidateName.flatMap(BadgeNameReader.clean) : nil
                bests = [:]; standings = [:]; lastRankProgress = nil
                player = found
                refreshBests()
                message = suggestedName == nil ? "Welcome! Choose your nickname and leaderboard visibility." : "Name read from your badge. Confirm or correct it before saving."
            } catch { if profileRevision == revision { message = error.localizedDescription } }
        }
    }
    func saveProfile(nickname: String, isPublic: Bool, completion: @escaping () -> Void = {}) {
        guard let player, !busy else { return }
        busy = true
        let revision = profileRevision
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await request("/api/players/\(player.id)", method: "PATCH", body: ["nickname": nickname, "isPublic": isPublic])
                guard profileRevision == revision, self.player?.id == player.id else { return }
                self.player = try JSONDecoder().decode(BadgePlayer.self, from: data)
                suggestedName = nil
                standings = [:]; lastRankProgress = nil
                refreshBests()
                message = "Ready to play"
                completion()
                showingSignIn = false
            } catch { if profileRevision == revision { message = error.localizedDescription } }
        }
    }
    func flush() {
        Task { @MainActor [weak self] in await self?.flushPending() }
    }

    /// Explicit async entry point also allows offline/retry verification without real timers or MongoDB.
    @MainActor
    func flushPending() async {
        guard !uploading, !pending.isEmpty else { return }
        uploading = true
        defer { uploading = false }
        while let run = pending.first {
            do {
                let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
                let data = try await request("/api/runs", method: "POST", body: body)
                if let progress = try? JSONDecoder().decode(RunSaveResponse.self, from: data).progress,
                   progress.runID == run.id, progress.playerID == run.playerID, player?.id == run.playerID {
                    lastRankProgress = progress
                    standings[run.difficulty] = progress.standing
                }
                pending.removeFirst(); persistQueue(); saveStatus = "Score saved to your profile."; refreshBests()
                refreshLeaderboard(run.difficulty)
            } catch { saveStatus = "Score queued — \(error.localizedDescription) Retrying automatically."; return }
        }
    }
    func refreshBests() {
        guard let id = player?.id else { return }
        for mode in ["Arcade", "Chill", "Tennis"] { refreshLeaderboard(mode) }
        Task { @MainActor in
            guard let data = try? await request("/api/players/\(id)/bests", method: "GET", body: [:]), player?.id == id else { return }
            bests = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        }
    }
    func refreshLeaderboard(_ mode: String = "Arcade") {
        guard ["Arcade", "Chill", "Tennis"].contains(mode) else { return }
        let requestID = UUID(); boardRequests[mode] = requestID
        let profileID = player?.id, revision = profileRevision
        if leaderboards[mode] == nil { leaderboardStatus[mode] = "Loading leaderboard…" }
        Task { @MainActor in
            do {
                let data = try await request("/api/leaderboard", method: "GET", body: [:], query: ["difficulty": mode])
                let board = try JSONDecoder().decode(LeaderboardBoard.self, from: data)
                guard boardRequests[mode] == requestID else { return }
                leaderboards[mode] = board
                leaderboardStatus[mode] = board.rows.isEmpty ? "Be the first to put a score on the board." : "Live board · best score per player"
                if let profileID {
                    let data = try await request("/api/players/\(profileID)/standing", method: "GET", body: [:], query: ["difficulty": mode])
                    guard boardRequests[mode] == requestID, profileRevision == revision, player?.id == profileID else { return }
                    standings[mode] = try JSONDecoder().decode(LeaderboardStanding.self, from: data)
                }
            } catch {
                guard boardRequests[mode] == requestID else { return }
                leaderboardStatus[mode] = leaderboards[mode] == nil ? "Leaderboard unavailable. Start the badge station, then refresh." : "Connection interrupted · showing last received scores"
            }
        }
    }

    func selectLeaderboard(_ mode: String) {
        guard ["Arcade", "Chill", "Tennis"].contains(mode) else { return }
        leaderboardMode = mode
        refreshLeaderboard(mode)
    }

    private func request(_ path: String, method: String, body: [String: Any], query: [String: String] = [:]) async throws -> Data {
        guard let config = await refreshConfiguration(), let base = URL(string: config.url), let scheme = base.scheme,
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(base.host ?? "")) else {
            throw NSError(domain: "Aircade", code: 1, userInfo: [NSLocalizedDescriptionKey: "Start the local server first (scripts/start-station.sh)."])
        }
        let endpoint = base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method; request.timeoutInterval = 8
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "Server request failed."
            throw NSError(domain: "Aircade", code: 2, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return data
    }
}
