import Foundation

struct AIChallengeScore: Codable, Identifiable {
    let id: String
    let playerID: String?
    let nickname: String
    let provider: String
    let model: String
    let controlMode: String
    let rules: String
    let flightSeconds: Int
    let human: Int
    let opponent: Int
    let simulated: Bool
    let exhibition: Bool
    let assisted: Bool
    let interrupted: Bool
    let completed: Bool
    let createdAt: Date
    var isPublic: Bool = false
    var eligible: Bool { playerID != nil && !simulated && !exhibition && !assisted && !interrupted && completed }
    var won: Bool { human > opponent }
    var variant: String { "\(provider)|\(model)|\(controlMode)|\(rules)|\(flightSeconds)" }
}

/// Station-local experimental board. Explicitly separate from the shared legacy Tennis board.
final class AIChallengeScores: ObservableObject {
    @Published private(set) var records: [AIChallengeScore] = []
    @Published private(set) var error: String?
    private let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aircade/ai-challenge-scores.json")
        if let data = try? Data(contentsOf: self.url) {
            do { records = try JSONDecoder().decode([AIChallengeScore].self, from: data) }
            catch { self.error = "Challenge history could not be read. Existing file preserved." }
        }
    }
    func record(_ score: AIChallengeScore) {
        guard error == nil, !records.contains(where: { $0.id == score.id }) else { return }
        let updated = records + [score]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            records = updated
        } catch { self.error = "Challenge score could not be saved." }
    }
    func leaders(provider: String) -> [AIChallengeScore] {
        let candidates = records.filter { $0.isPublic && $0.provider == provider && $0.model == (provider == "jev" ? "typesafe-ai/jev" : "gpt-6-astra") && $0.controlMode == (provider == "jev" ? "state" : "screen") && $0.eligible && $0.rules == "controlled-v1" && $0.flightSeconds == 8 }
        // One best run per badge, separately for the exact model/control/rules variant.
        var best: [String: AIChallengeScore] = [:]
        for score in candidates {
            let key = score.variant + "|" + (score.playerID ?? "")
            if let old = best[key], !Self.better(score, old) { continue }
            best[key] = score
        }
        return best.values.sorted(by: Self.better)
    }
    static func better(_ a: AIChallengeScore, _ b: AIChallengeScore) -> Bool {
        if a.won != b.won { return a.won }
        if a.human - a.opponent != b.human - b.opponent { return a.human - a.opponent > b.human - b.opponent }
        if a.human != b.human { return a.human > b.human }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }
}
