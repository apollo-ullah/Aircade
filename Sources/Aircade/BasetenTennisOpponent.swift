import Foundation
import MotionCore

struct TennisOpponentStatus: Equatable {
    var provider = "MODEL"
    var modelVersion = "connecting"
    var latencyMS = 0
    var fallbackUsed = true

    var decision = "Waiting for model plan"

    var label: String {
        let timing = latencyMS > 0 ? " · \(latencyMS) ms" : ""
        return "\(provider.uppercased()) · \(modelVersion)\(timing) · \(decision)"
    }
}

/// Keeps model inference outside the render loop. The match reads the latest
/// validated plan synchronously and continues using it until a refresh succeeds.
final class BasetenTennisOpponent: TennisOpponentStrategy {
    private struct Candidate: Codable {
        let id: String
        let targetX: Float
        let flightDuration: Double
        let delay: Double
        let stroke: String
        let distance: Double
        let reactionTime: Double
        let pace: Double
        let targetsWeakSide: Bool
        let rallyLength: Int
    }

    private struct PlanRequest: Codable {
        let provider: String
        let requireModel = true
        let playerID: String?
        let difficulty: String
        let score: Int
        let misses: Int
        let longestRally: Int
        let incomingBallX: Float?
        let opponentAttemptX: Float?
        let previousReturnX: Float?
        let candidates: [Candidate]
    }

    private struct PlannedReturn: Codable {
        let candidateID: String
        let targetX: Float
        let flightDuration: Double
        let delay: Double
        let stroke: String
        let returnProbability: Double
    }

    private struct PlanResponse: Codable {
        let provider: String
        let modelVersion: String
        let latencyMs: Int
        let fallbackUsed: Bool
        let returns: [PlannedReturn]
    }

    var onStatus: ((TennisOpponentStatus) -> Void)?
    private let lock = NSLock()
    private var plans: [TennisOpponentReturn] = [AutomaticReboundOpponent().returnPlan(rally: 0, sequence: 0)]
    private(set) var provider = "baseten"
    private var modelPlanAvailable = false
    var hasModelPlan: Bool { lock.lock(); defer { lock.unlock() }; return modelPlanAvailable }
    private var generation = 0
    private var lastRefresh = -Double.infinity
    private var lastTargetX: Float?
    private var refreshing = false

    func returnPlan(rally: Int, sequence: Int) -> TennisOpponentReturn {
        lock.lock(); defer { lock.unlock() }
        guard !plans.isEmpty else { return AutomaticReboundOpponent().returnPlan(rally: rally, sequence: sequence) }
        let plan = plans[0] // Preserve the model's first-ranked shot exactly.
        lastTargetX = plan.targetX
        return plan
    }

    func select(provider: String) {
        lock.lock(); defer { lock.unlock() }
        self.provider = provider; generation += 1; refreshing = false
        modelPlanAvailable = false; lastTargetX = nil; lastRefresh = -.infinity
        plans = [AutomaticReboundOpponent().returnPlan(rally: 0, sequence: 0)]
    }

    func refresh(playerID: String?, match: TennisMatch) {
        lock.lock()
        guard !refreshing, ProcessInfo.processInfo.systemUptime - lastRefresh >= 2.2 else { lock.unlock(); return }
        refreshing = true
        lastRefresh = ProcessInfo.processInfo.systemUptime
        let epoch = generation
        let provider = self.provider
        let previousReturnX = lastTargetX
        lock.unlock()

        let candidates = Self.candidates(rally: match.rally)
        let payload = PlanRequest(provider: provider, playerID: playerID, difficulty: "rival", score: match.score,
                                  misses: match.misses, longestRally: match.longestRally,
                                  incomingBallX: match.ball?.direction == .towardOpponent ? match.ball?.to.x : nil,
                                  opponentAttemptX: match.ball?.direction == .towardOpponent ? match.ball?.defenderContactX : nil,
                                  previousReturnX: previousReturnX,
                                  candidates: candidates)
        Task { [weak self] in
            guard let self else { return }
            defer { self.finishRefresh(epoch: epoch) }
            do {
                let response = try await self.fetch(payload)
                let valid = response.returns.compactMap(Self.validate)
                guard !response.fallbackUsed, !valid.isEmpty, valid.count == response.returns.count else { throw URLError(.cannotParseResponse) }
                guard self.install(valid, epoch: epoch) else { return }
                let status = TennisOpponentStatus(provider: response.provider, modelVersion: response.modelVersion,
                                                  latencyMS: response.latencyMs, fallbackUsed: response.fallbackUsed, decision: "Model chose \(response.returns[0].candidateID)")
                await MainActor.run { if self.generation == epoch { self.onStatus?(status) } }
            } catch {
                let status = TennisOpponentStatus(provider: provider, modelVersion: self.hasModelPlan ? "cached model plan" : "unavailable", latencyMS: 0, fallbackUsed: !self.hasModelPlan, decision: self.hasModelPlan ? "Using last model-selected shot" : "Retry model connection")
                await MainActor.run { if self.generation == epoch { self.onStatus?(status) } }
            }
        }
    }

    private func install(_ newPlans: [TennisOpponentReturn], epoch: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == epoch else { return false }
        plans = newPlans; modelPlanAvailable = true
        return true
    }

    private func finishRefresh(epoch: Int) {
        lock.lock(); defer { lock.unlock() }
        if generation == epoch { refreshing = false }
    }

    private func fetch(_ payload: PlanRequest) async throws -> PlanResponse {
        let path = ProcessInfo.processInfo.environment["AIRCADE_STATION_CONFIG"]
        let configURL = path.map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".local/station.json")
        let config = try JSONDecoder().decode(StationConfiguration.self, from: Data(contentsOf: configURL))
        guard let base = URL(string: config.url), let scheme = base.scheme,
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(base.host ?? "")) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: base.appendingPathComponent("api/tennis/opponent-plan"))
        request.httpMethod = "POST"
        // Planning is asynchronous and a late result is used for a later ball.
        // Allow the station enough time for a shared Baseten model response.
        request.timeoutInterval = 9
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PlanResponse.self, from: data)
    }

    private static func validate(_ value: PlannedReturn) -> TennisOpponentReturn? {
        guard value.targetX.isFinite, abs(value.targetX) <= 3.5,
              value.flightDuration.isFinite, (0.85...4.0).contains(value.flightDuration),
              value.delay.isFinite, (0.18...0.8).contains(value.delay),
              let stroke = TennisStroke(rawValue: value.stroke) else { return nil }
        return TennisOpponentReturn(targetX: value.targetX, flightDuration: value.flightDuration,
                                    delay: value.delay, stroke: stroke)
    }

    private static func candidates(rally: Int) -> [Candidate] {
        let definitions: [(String, Float, Double, Double, TennisStroke)] = [
            ("deep-left", -3.10, 2.72, 0.34, .forehand),
            ("left", -1.55, 2.88, 0.38, .backhand),
            ("middle", 0, 2.42, 0.31, .forehand),
            ("right", 1.55, 2.86, 0.39, .forehand),
            ("deep-right", 3.10, 2.68, 0.35, .backhand)
        ]
        return definitions.map { id, x, duration, delay, stroke in
            Candidate(id: id, targetX: x, flightDuration: duration, delay: delay,
                      stroke: stroke.rawValue, distance: Double(abs(x)), reactionTime: duration,
                      pace: 1 / duration, targetsWeakSide: x < 0, rallyLength: rally)
        }
    }
}
