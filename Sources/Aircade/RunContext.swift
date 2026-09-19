import Foundation

enum ArcadeRunGame: String, Codable {
    case neonRush = "Neon Rush"
    case tennis = "Tennis"
    case saberDuel = "Saber Duel"

    var supportsProfileScores: Bool { self != .saberDuel }
}

/// The identity belongs to the run, not whichever profile is selected when it ends.
struct RunProfileSnapshot: Equatable {
    let id: String
    let nickname: String
    let isPublic: Bool

    init(_ player: BadgePlayer) {
        id = player.id
        nickname = player.nickname
        isPublic = player.isPublic
    }
}

struct RunContext: Identifiable, Equatable {
    let id: String
    let game: ArcadeRunGame
    let mode: String
    let profile: RunProfileSnapshot?
    let avatarID: String?
    private(set) var isSimulated: Bool

    init(game: ArcadeRunGame, mode: String, player: BadgePlayer?, simulated: Bool,
         avatarID: String? = nil) {
        id = UUID().uuidString
        self.game = game
        self.mode = mode
        profile = player.map(RunProfileSnapshot.init)
        self.avatarID = avatarID
        isSimulated = simulated
    }

    var isGuest: Bool { profile == nil }
    var eligibleForLocalBest: Bool { !isSimulated }
    // Private profiles can save personal scores. Public visibility remains a server-side opt-in.
    var eligibleForProfileUpload: Bool { !isSimulated && profile != nil && game.supportsProfileScores }

    mutating func observeInput(simulated: Bool) {
        isSimulated = isSimulated || simulated
    }
}

struct RunCompletion: Equatable {
    let context: RunContext
    let queuedForProfile: Bool
    var eligibleForLocalBest: Bool { context.eligibleForLocalBest }
}
