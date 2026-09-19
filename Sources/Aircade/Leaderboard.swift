import Foundation

struct LeaderboardRow: Codable, Equatable, Identifiable {
    var rank: Int
    var nickname: String
    var score: Int
    var accuracy: Int
    var bestCombo: Int
    var id: Int { rank }
}
struct LeaderboardBoard: Codable, Equatable {
    var difficulty: String
    var totalPlayers: Int
    var rows: [LeaderboardRow]
}
struct LeaderboardTarget: Codable, Equatable {
    var rank: Int
    var nickname: String
    var score: Int
    var pointsNeeded: Int
}
struct LeaderboardStanding: Codable, Equatable {
    var difficulty: String
    var isPublic: Bool
    var personalBest: Int?
    var rank: Int?
    var totalPlayers: Int
    var next: LeaderboardTarget?

    var challenge: String {
        if !isPublic { return "Your scores are private. Join the public board in your profile to compete." }
        if let next { return "Score \((next.score + 1).formatted()) to pass \(next.nickname) at #\(next.rank)." }
        if rank == 1 { return "You lead this board. Set a new personal best to raise the bar." }
        return "Finish your first round to join this board."
    }
}
struct RankProgress: Codable, Equatable {
    var runID: String
    var playerID: String
    var newPersonalBest: Bool
    var previousBest: Int?
    var previousRank: Int?
    var placesClimbed: Int
    var standing: LeaderboardStanding

    var headline: String {
        if standing.isPublic, placesClimbed > 0 { return "Up \(placesClimbed) \(placesClimbed == 1 ? "place" : "places")!" }
        if standing.isPublic, previousRank == nil, let rank = standing.rank { return "On the board at #\(rank)!" }
        return newPersonalBest ? "New personal best!" : "Another round in the books."
    }
}
struct RunSaveResponse: Decodable {
    var progress: RankProgress?
}
