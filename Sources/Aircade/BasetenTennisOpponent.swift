import Foundation
import MotionCore

struct TennisOpponentStatus: Equatable {
    var provider = "MODEL"
    var modelVersion = "connecting"
    var latencyMS = 0
    var fallbackUsed = true
    var decision = "Waiting for model plan"
    var inputSummary: String?
    var selectedCandidateID: String?
    var appliedCandidateID: String?
    var requestLatencyMS: Double?
    var observationID: String?
    var decisionID: String?
    var responseID: String?
    var planAgeSeconds: Double?
    var stateLabel = "Waiting"
    var appliedDecisionID: String?
    var appliedObservationID: String?
    var appliedObservationToShotMS: Double?

    var label: String {
        let timing = latencyMS > 0 ? " · \(latencyMS) ms" : ""
        return "\(provider.uppercased()) · \(modelVersion)\(timing) · \(stateLabel) · \(decision)"
    }
}

/// Inference never blocks rendering. A generation owns each request, while a
/// captured decision owns each prepared shot; later responses cannot relabel it.
final class BasetenTennisOpponent: TennisOpponentStrategy {
    typealias Transport = (Data) async throws -> Data

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
    private struct PlanRequest: Encodable {
        let provider: String
        let requireModel = true
        let observationID: String
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
    }
    private struct PlanResponse: Codable {
        let provider: String
        let modelVersion: String
        let latencyMs: Int
        let fallbackUsed: Bool
        let observationID: String?
        let decisionID: String?
        let selectedCandidateID: String?
        let inputSummary: String?
        let responseID: String?
        let returns: [PlannedReturn]
    }
    private struct Decision {
        let plan: TennisOpponentReturn
        let candidateID: String
        let decisionID: String
        let observationID: String
        let receivedAt: Double
        let observedAt: Double
    }
    private struct StationFailure: Error {
        let code: String
        let retryAfter: Double?
        var description: String {
            switch code {
            case "timeout": return "Model missed the six-second deadline"
            case "rate_limit": return "Model is cooling down; retry shortly"
            case "budget": return "Station request budget reached"
            case "refused": return "Model declined the decision"
            case "incomplete": return "Model response was incomplete"
            case "invalid": return "Model returned an invalid decision"
            default: return "Model connection unavailable"
            }
        }
    }

    var onStatus: ((TennisOpponentStatus) -> Void)?
    private let lock = NSLock()
    private let transport: Transport
    private let clock: () -> Double
    private var task: Task<Void, Never>?
    private var selected: Decision?
    private var pending: Decision?
    private var applied: Decision?
    private var status = TennisOpponentStatus()
    private(set) var provider = "baseten"
    private var generation = 0
    private var publication = 0
    private var lastRefresh = -Double.infinity
    private var nextAllowedRefresh = -Double.infinity
    private var lastTargetX: Float?
    private var refreshing = false
    private var suspended = false

    init(transport: @escaping Transport = BasetenTennisOpponent.stationRequest,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport
        self.clock = clock
    }

    var hasModelPlan: Bool { lock.lock(); defer { lock.unlock() }; return selected != nil }
    var currentStatus: TennisOpponentStatus {
        lock.lock(); defer { lock.unlock() }
        return snapshot()
    }

    func returnPlan(rally: Int, sequence: Int) -> TennisOpponentReturn {
        lock.lock(); defer { lock.unlock() }
        guard let selected else {
            pending = nil
            return AutomaticReboundOpponent().returnPlan(rally: rally, sequence: sequence)
        }
        pending = selected
        lastTargetX = selected.plan.targetX
        return selected.plan
    }

    /// Called only when TennisMatch emits opponentReturn, not at preparation or
    /// response receipt. A pending shot can survive pause and newer responses.
    func markReturnApplied() {
        lock.lock()
        guard let pending else { lock.unlock(); return }
        let reused = applied?.decisionID == pending.decisionID
        applied = pending
        self.pending = nil
        status.appliedCandidateID = pending.candidateID
        status.appliedDecisionID = pending.decisionID
        status.appliedObservationID = pending.observationID
        status.appliedObservationToShotMS = max(0, clock() - pending.observedAt) * 1000
        if reused || refreshing || selected?.decisionID != pending.decisionID { status.stateLabel = "Cached" }
        lock.unlock()
        publish()
    }

    func select(provider: String) {
        invalidate(preservePlan: false, preservePending: false, suspend: false)
        lock.lock()
        self.provider = provider
        status = TennisOpponentStatus(provider: provider, modelVersion: "connecting", decision: "Preparing model shot")
        nextAllowedRefresh = -.infinity
        lock.unlock()
        publish()
    }

    /// Preserve the verified lobby decision so starting never falls back to a
    /// local shot, but discard the previous run's work and applied provenance.
    func beginRun() {
        invalidate(preservePlan: true, preservePending: false, suspend: false)
        lock.lock()
        applied = nil
        status.appliedCandidateID = nil
        status.appliedDecisionID = nil
        status.appliedObservationID = nil
        status.appliedObservationToShotMS = nil
        lock.unlock()
        publish()
    }

    func suspend() {
        invalidate(preservePlan: true, preservePending: true, suspend: true)
        publish()
    }

    func resume() {
        lock.lock(); suspended = false; lock.unlock()
        publish()
    }

    func endRun() {
        invalidate(preservePlan: false, preservePending: false, suspend: true)
        publish()
    }

    private func invalidate(preservePlan: Bool, preservePending: Bool, suspend: Bool) {
        lock.lock()
        generation += 1
        let cancelled = task
        task = nil
        refreshing = false
        suspended = suspend
        lastRefresh = -.infinity
        if !preservePending { pending = nil }
        if !preservePlan {
            selected = nil; applied = nil; lastTargetX = nil
            status = TennisOpponentStatus(provider: provider, modelVersion: "connecting")
        } else if selected != nil {
            status.stateLabel = "Cached"
            status.decision = suspend ? "Paused; keeping the last model-selected shot" : "Using verified model shot"
        } else {
            status.stateLabel = "Waiting"
            status.decision = suspend ? "Model requests paused" : "Waiting for model plan"
        }
        lock.unlock()
        cancelled?.cancel()
    }

    func refresh(playerID: String?, match: TennisMatch) {
        lock.lock()
        let started = clock()
        guard !suspended, !refreshing, started - lastRefresh >= 2.2, started >= nextAllowedRefresh else { lock.unlock(); return }
        refreshing = true
        lastRefresh = started
        let epoch = generation
        let requestedProvider = provider
        let observationID = UUID().uuidString
        let previousReturnX = lastTargetX
        status.stateLabel = selected == nil ? "Waiting" : "Cached"
        status.decision = selected == nil ? "Requesting a model shot" : "Requesting next shot; keeping verified plan"
        lock.unlock()
        publish()
        let payload = PlanRequest(provider: requestedProvider, observationID: observationID, playerID: playerID,
                                  difficulty: "rival", score: match.score, misses: match.misses,
                                  longestRally: match.longestRally,
                                  incomingBallX: match.ball?.direction == .towardOpponent ? match.ball?.to.x : nil,
                                  opponentAttemptX: match.ball?.direction == .towardOpponent ? match.ball?.defenderContactX : nil,
                                  previousReturnX: previousReturnX, candidates: Self.candidates(rally: match.rally))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.transport(JSONEncoder().encode(payload))
                try Task.checkCancellation()
                let response = try JSONDecoder().decode(PlanResponse.self, from: data)
                let decision = try Self.validate(response, payload: payload, receivedAt: self.clock(), observedAt: started)
                self.install(decision, response: response, epoch: epoch, started: started)
            } catch {
                self.fail(error, epoch: epoch)
            }
        }
        lock.lock()
        if generation == epoch { self.task = task } else { task.cancel() }
        lock.unlock()
    }

    private func install(_ decision: Decision, response: PlanResponse, epoch: Int, started: Double) {
        lock.lock()
        guard generation == epoch, !suspended else { lock.unlock(); return }
        selected = decision
        refreshing = false
        status.provider = response.provider
        status.modelVersion = response.modelVersion
        status.latencyMS = response.latencyMs
        status.requestLatencyMS = max(0, clock() - started) * 1000
        status.fallbackUsed = false
        status.decision = "Model chose \(decision.candidateID)"
        status.inputSummary = response.inputSummary ?? "Five legal shots; score and current ball state."
        status.selectedCandidateID = decision.candidateID
        status.observationID = decision.observationID
        status.decisionID = decision.decisionID
        status.responseID = response.responseID
        status.stateLabel = "Fresh"
        lock.unlock()
        publish()
    }

    private func fail(_ error: Error, epoch: Int) {
        lock.lock()
        guard generation == epoch, !suspended else { lock.unlock(); return }
        refreshing = false
        let failure = error as? StationFailure
        if let delay = failure?.retryAfter { nextAllowedRefresh = clock() + delay }
        status.stateLabel = selected == nil ? "Unavailable" : "Cached"
        status.fallbackUsed = selected == nil
        status.decision = (failure?.description ?? "Model connection or response unavailable")
            + (selected == nil ? "; retry connection" : "; using last model-selected shot")
        if selected == nil { status.modelVersion = "unavailable" }
        lock.unlock()
        publish()
    }

    private func snapshot() -> TennisOpponentStatus {
        var value = status
        value.planAgeSeconds = selected.map { max(0, clock() - $0.receivedAt) }
        return value
    }

    private func publish() {
        lock.lock()
        publication += 1
        let revision = publication
        let epoch = generation
        let value = snapshot()
        lock.unlock()
        let deliver = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = self.generation == epoch && self.publication == revision
            self.lock.unlock()
            if valid { self.onStatus?(value) }
        }
        if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
    }

    private static func validate(_ response: PlanResponse, payload: PlanRequest, receivedAt: Double, observedAt: Double) throws -> Decision {
        guard !response.fallbackUsed, !response.returns.isEmpty, response.latencyMs >= 0,
              !response.modelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StationFailure(code: "invalid", retryAfter: nil) }
        let strict = payload.provider == "astra" || payload.provider == "jev"
        let identityOK: Bool
        switch payload.provider {
        case "astra": identityOK = response.provider == "OpenAI API" && response.modelVersion.range(of: #"^gpt-6-astra(?:-\d{4}-\d{2}-\d{2})?$"#, options: .regularExpression) != nil
        case "jev": identityOK = response.provider == "Vercel Jev" && response.modelVersion == "typesafe-ai/jev"
        case "baseten": identityOK = ["Baseten Model API", "Baseten"].contains(response.provider)
        default: identityOK = false
        }
        guard identityOK, !strict || (response.observationID == payload.observationID
            && response.decisionID?.isEmpty == false && response.returns.count == 1
            && response.selectedCandidateID == response.returns[0].candidateID) else { throw StationFailure(code: "invalid", retryAfter: nil) }
        var ids = Set<String>()
        for value in response.returns {
            guard ids.insert(value.candidateID).inserted,
                  let candidate = payload.candidates.first(where: { $0.id == value.candidateID }),
                  value.targetX == candidate.targetX, value.flightDuration == candidate.flightDuration,
                  value.delay == candidate.delay, value.stroke == candidate.stroke else { throw StationFailure(code: "invalid", retryAfter: nil) }
        }
        let first = response.returns[0]
        guard let stroke = TennisStroke(rawValue: first.stroke) else { throw StationFailure(code: "invalid", retryAfter: nil) }
        return Decision(plan: TennisOpponentReturn(targetX: first.targetX, flightDuration: first.flightDuration,
                                                   delay: first.delay, stroke: stroke), candidateID: first.candidateID,
                        decisionID: response.decisionID ?? "local:\(UUID().uuidString)",
                        observationID: response.observationID ?? payload.observationID, receivedAt: receivedAt, observedAt: observedAt)
    }

    static func stationRequest(_ data: Data) async throws -> Data {
        guard let config = await PlayerSession.loadConfigurationAsync() else { throw URLError(.resourceUnavailable) }
        guard let base = URL(string: config.url), let scheme = base.scheme,
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(base.host ?? "")) else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("api/tennis/opponent-plan"))
        request.httpMethod = "POST"
        // The server enforces the shared six-second model deadline. Transport
        // allows a small local hop allowance, equally for Astra and Jev.
        request.timeoutInterval = 9
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let delay = (body?["retryAfterMs"] as? Double).map { max(0, $0 / 1000) }
            throw StationFailure(code: body?["code"] as? String ?? "unavailable", retryAfter: delay)
        }
        return data
    }

    private static func candidates(rally: Int) -> [Candidate] {
        let definitions: [(String, Float, Double, Double, TennisStroke)] = [
            ("deep-left", -3.10, 2.72, 0.34, .forehand), ("left", -1.55, 2.88, 0.38, .backhand),
            ("middle", 0, 2.42, 0.31, .forehand), ("right", 1.55, 2.86, 0.39, .forehand),
            ("deep-right", 3.10, 2.68, 0.35, .backhand)
        ]
        return definitions.map { id, x, duration, delay, stroke in
            Candidate(id: id, targetX: x, flightDuration: duration, delay: delay,
                      stroke: stroke.rawValue, distance: Double(abs(x)), reactionTime: duration,
                      pace: 1 / duration, targetsWeakSide: x < 0, rallyLength: rally)
        }
    }
}
