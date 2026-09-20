import XCTest
import MotionCore
import CryptoKit
@testable import Aircade

final class PlayerSessionTests: XCTestCase {
    private var directory: URL!
    private let alice = BadgePlayer(id: "11111111-1111-1111-1111-111111111111", nickname: "Alice", isPublic: false)
    private let bob = BadgePlayer(id: "22222222-2222-2222-2222-222222222222", nickname: "Bob", isPublic: true)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aircade-run-policy-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func session(configuration: StationConfiguration? = nil,
                         transport: @escaping PlayerSession.Transport = { _ in throw URLError(.notConnectedToInternet) }) -> PlayerSession {
        PlayerSession(queueDirectory: directory, automaticRetry: false, uploadOnFinish: false,
                      configurationProvider: { configuration }, transport: transport)
    }

    func testViewConfigurationGettersNeverReloadTheProvider() {
        var reads = 0
        let config = StationConfiguration(url: "http://127.0.0.1:8794", token: "test-only-token")
        let players = PlayerSession(queueDirectory: directory, automaticRetry: false,
                                    configurationProvider: { reads += 1; return config })
        XCTAssertEqual(reads, 1)
        for _ in 0..<100 {
            XCTAssertTrue(players.profilesAvailable)
            XCTAssertEqual(players.leaderboardURL(for: "Tennis").port, 8794)
        }
        XCTAssertEqual(reads, 1, "SwiftUI can evaluate repeatedly without touching the configuration file")
    }

    @MainActor
    func testBlockedConfigurationReadTimesOutWithoutBlockingMainActor() async {
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "Background reader released")
        var mainActorRan = false
        Task { @MainActor in mainActorRan = true }
        let loaded = await PlayerSession.loadConfigurationAsync(provider: {
            XCTAssertFalse(Thread.isMainThread)
            release.wait()
            finished.fulfill()
            return StationConfiguration(url: "http://127.0.0.1:8794", token: "fixture")
        }, timeout: 0.03)
        XCTAssertNil(loaded, "A permission-blocked file must not keep a request waiting indefinitely")
        XCTAssertTrue(mainActorRan, "The UI executor stays available while disk access is blocked")
        release.signal()
        await fulfillment(of: [finished], timeout: 1)
    }

    func testStationResolverUsesScopedStagingAndExplicitOverride() throws {
        let bundle = directory.appendingPathComponent("checkout/build/Aircade.app")
        let support = directory.appendingPathComponent("support")
        let legacy = directory.appendingPathComponent("checkout/.local/station.json")
        XCTAssertEqual(PlayerSession.configurationURL(environment: [:], bundleURL: bundle, supportDirectory: support), legacy)
        let stagedDirectory = support.appendingPathComponent("Aircade/Stations")
        try FileManager.default.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        // The test obtains the expected hash independently through CryptoKit.
        let root = bundle.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(root.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        let staged = stagedDirectory.appendingPathComponent("\(digest).json")
        try Data("{}".utf8).write(to: staged)
        XCTAssertEqual(PlayerSession.configurationURL(environment: [:], bundleURL: bundle, supportDirectory: support), staged)
        let explicit = directory.appendingPathComponent("explicit.json")
        XCTAssertEqual(PlayerSession.configurationURL(environment: ["AIRCADE_STATION_CONFIG": explicit.path], bundleURL: bundle, supportDirectory: support), explicit)
    }

    private func rushResult() -> NeonRush {
        var state = NeonRush()
        state.start(difficulty: .arcade)
        state.advance(3)
        state.advance(NeonRush.duration)
        XCTAssertEqual(state.phase, .results)
        return state
    }

    private func tennisResult() -> TennisMatch {
        var state = TennisMatch()
        state.start()
        state.advance(3, opponent: AutomaticReboundOpponent())
        state.advance(TennisMatch.duration, opponent: AutomaticReboundOpponent())
        XCTAssertEqual(state.phase, .results)
        return state
    }

    func testGuestStartsAndFinishesWithoutConfigurationOrNetwork() throws {
        var requests = 0
        let players = session { _ in requests += 1; throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(players.authorize())
        XCTAssertFalse(players.showingSignIn)
        let run = players.beginRun(game: .neonRush, mode: "Arcade")
        XCTAssertTrue(run.isGuest)
        XCTAssertTrue(players.canRecordLocalBest(for: run.id))
        let completion = try XCTUnwrap(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertTrue(completion.eligibleForLocalBest)
        XCTAssertFalse(completion.queuedForProfile)
        XCTAssertTrue(players.pendingRuns.isEmpty)
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending-runs.json").path))
    }

    func testGuestScoreCannotBeUploadedAfterSigningIn() throws {
        let players = session()
        let run = players.beginRun(game: .tennis, mode: "Tennis")
        players.player = alice
        let completion = try XCTUnwrap(players.finishTennis(tennisResult(), demo: false, runID: run.id))
        XCTAssertTrue(completion.context.isGuest)
        XCTAssertTrue(completion.eligibleForLocalBest)
        XCTAssertFalse(completion.queuedForProfile)
        XCTAssertNil(players.finishTennis(tennisResult(), demo: false, runID: run.id))
        XCTAssertTrue(players.pendingRuns.isEmpty)
    }

    @MainActor
    func testSavingProfileCompletesRunPromptOnlyAfterSuccessfulSave() async throws {
        let config = StationConfiguration(url: "https://example.invalid", token: "test-only-token")
        let updated = BadgePlayer(id: alice.id, nickname: "Rally Alice", isPublic: true)
        let completed = expectation(description: "Run prompt continues after profile save")
        let players = session(configuration: config) { request in
            if request.httpMethod == "PATCH" {
                return (try JSONEncoder().encode(updated), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        players.player = alice
        players.showingSignIn = true

        players.saveProfile(nickname: updated.nickname, isPublic: true) { completed.fulfill() }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(players.player, updated)
        XCTAssertFalse(players.showingSignIn)
    }

    func testProfileOwnerAndVisibilityAreSnapshotsAcrossSwitchAndLogout() throws {
        let players = session()
        players.player = alice
        let run = players.beginRun(game: .neonRush, mode: "Arcade", avatarID: "avatar-one")
        players.player = bob
        players.logout()
        let completion = try XCTUnwrap(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertEqual(completion.context.profile?.id, alice.id)
        XCTAssertEqual(completion.context.profile?.nickname, "Alice")
        XCTAssertEqual(completion.context.profile?.isPublic, false)
        XCTAssertEqual(completion.context.avatarID, "avatar-one")
        XCTAssertEqual(players.pendingRuns.map(\.playerID), [alice.id])
        XCTAssertTrue(completion.queuedForProfile, "Private profiles still save personal scores; the server controls visibility")
        let guest = players.beginRun(game: .tennis, mode: "Tennis")
        XCTAssertTrue(guest.isGuest)
    }

    func testSelectGuestClearsProfileForFutureRunsWithoutReattributingExistingRun() throws {
        let players = session()
        players.player = alice
        players.bests = ["Arcade": 2000]
        let ranked = players.beginRun(game: .neonRush, mode: "Arcade")
        players.selectGuest()
        XCTAssertNil(players.player)
        XCTAssertTrue(players.bests.isEmpty)
        XCTAssertEqual(players.activeRun?.profile?.id, alice.id)
        players.abandonRun(runID: ranked.id)
        let guest = players.beginRun(game: .neonRush, mode: "Arcade")
        XCTAssertTrue(guest.isGuest)
        _ = players.finishRun(rushResult(), demo: false, runID: guest.id)
        XCTAssertTrue(players.pendingRuns.isEmpty)
    }

    func testSimulationAtAnyPointIsPermanentAndRunSpecific() throws {
        let players = session()
        players.player = bob
        let run = players.beginRun(game: .neonRush, mode: "Arcade")
        players.observeInput(simulated: true, runID: "a-different-run")
        XCTAssertTrue(players.canRecordLocalBest(for: run.id))
        players.observeInput(simulated: true, runID: run.id)
        players.observeInput(simulated: false, runID: run.id)
        XCTAssertFalse(players.canRecordLocalBest(for: run.id))
        let completion = try XCTUnwrap(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertTrue(completion.context.isSimulated)
        XCTAssertFalse(completion.eligibleForLocalBest)
        XCTAssertFalse(completion.queuedForProfile)
        XCTAssertTrue(players.pendingRuns.isEmpty)

        let next = players.beginRun(game: .neonRush, mode: "Arcade")
        XCTAssertFalse(next.isSimulated)
        XCTAssertTrue(players.canRecordLocalBest(for: next.id))
    }

    func testSimulatedGuestAndTennisFinishFlagsCannotSaveRealRecords() throws {
        let players = session()
        let guest = players.beginRun(game: .neonRush, mode: "Arcade", simulated: true)
        let guestResult = try XCTUnwrap(players.finishRun(rushResult(), demo: false, runID: guest.id))
        XCTAssertFalse(guestResult.eligibleForLocalBest)
        players.player = bob
        let tennis = players.beginRun(game: .tennis, mode: "Tennis")
        let tennisResult = try XCTUnwrap(players.finishTennis(tennisResult(), demo: true, runID: tennis.id))
        XCTAssertFalse(tennisResult.eligibleForLocalBest)
        XCTAssertTrue(players.pendingRuns.isEmpty)
    }

    func testDuplicateResultQueuesExactlyOnceWithOriginalRunID() throws {
        let players = session()
        players.player = alice
        let run = players.beginRun(game: .neonRush, mode: "Arcade")
        XCTAssertNotNil(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertNil(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertNil(players.activeRun)
        XCTAssertEqual(players.pendingRuns.map(\.id), [run.id])
        let persisted = try JSONDecoder().decode([BadgeRun].self, from: Data(contentsOf: directory.appendingPathComponent("pending-runs.json")))
        XCTAssertEqual(persisted, players.pendingRuns)
    }

    func testAbandonedAndLateCallbacksCannotFinishOrTaintAnotherRun() {
        let players = session()
        players.player = alice
        let old = players.beginRun(game: .neonRush, mode: "Arcade")
        players.abandonRun(runID: old.id)
        XCTAssertNil(players.finishRun(rushResult(), demo: false, runID: old.id))
        let new = players.beginRun(game: .neonRush, mode: "Arcade")
        players.abandonRun(runID: old.id)
        players.observeInput(simulated: true, runID: old.id)
        XCTAssertNil(players.finishRun(rushResult(), demo: true, runID: old.id))
        XCTAssertEqual(players.activeRun?.id, new.id)
        XCTAssertTrue(players.canRecordLocalBest(for: new.id))
        XCTAssertNotNil(players.finishRun(rushResult(), demo: false, runID: new.id))
        XCTAssertEqual(players.pendingRuns.map(\.id), [new.id])
    }

    func testWrongGameOrNonterminalStateCannotConsumeRun() {
        let players = session()
        players.player = alice
        let run = players.beginRun(game: .tennis, mode: "Tennis")
        XCTAssertNil(players.finishRun(rushResult(), demo: false, runID: run.id))
        XCTAssertNil(players.finishTennis(TennisMatch(), demo: false, runID: run.id))
        XCTAssertEqual(players.activeRun?.id, run.id)
        XCTAssertNotNil(players.finishTennis(tennisResult(), demo: false, runID: run.id))
        XCTAssertEqual(players.pendingRuns.first?.game, "Tennis")
    }

    func testDuelCompletionIsLocalAndStillHonorsSimulation() throws {
        let players = session()
        players.player = bob
        let run = players.beginRun(game: .saberDuel, mode: "Versus")
        XCTAssertNil(players.finishLocalRun(runID: "another-run"))
        let completion = try XCTUnwrap(players.finishLocalRun(runID: run.id))
        XCTAssertTrue(completion.eligibleForLocalBest)
        XCTAssertFalse(completion.queuedForProfile)
        let simulated = players.beginRun(game: .saberDuel, mode: "Versus")
        players.observeInput(simulated: true, runID: simulated.id)
        XCTAssertEqual(players.finishLocalRun(runID: simulated.id)?.eligibleForLocalBest, false)
        XCTAssertTrue(players.pendingRuns.isEmpty)
    }

    @MainActor
    func testOfflineQueueRestoresAndRetryUsesSameIDAndOwner() async throws {
        let config = StationConfiguration(url: "http://127.0.0.1:8787", token: "test-only-token")
        var attempts: [BadgeRun] = []
        let offline = session(configuration: config) { request in
            attempts.append(try JSONDecoder().decode(BadgeRun.self, from: XCTUnwrap(request.httpBody)))
            throw URLError(.notConnectedToInternet)
        }
        offline.player = alice
        let run = offline.beginRun(game: .neonRush, mode: "Arcade")
        _ = offline.finishRun(rushResult(), demo: false, runID: run.id)
        await offline.flushPending()
        XCTAssertEqual(offline.pendingRuns.count, 1)
        XCTAssertTrue(offline.saveStatus.contains("queued"))

        let restored = session(configuration: config) { request in
            if request.url?.path == "/api/runs" {
                attempts.append(try JSONDecoder().decode(BadgeRun.self, from: XCTUnwrap(request.httpBody)))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-token")
            }
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        restored.player = bob
        XCTAssertEqual(restored.pendingRuns.map(\.id), [run.id])
        await restored.flushPending()
        XCTAssertTrue(restored.pendingRuns.isEmpty)
        XCTAssertEqual(attempts.map(\.id), [run.id, run.id])
        XCTAssertEqual(attempts.map(\.playerID), [alice.id, alice.id])
        XCTAssertEqual(attempts[0], attempts[1], "Retries retain the exact idempotent payload")
        XCTAssertTrue(session().pendingRuns.isEmpty)
    }

    @MainActor
    func testProfileSelectionDoesNotChangePublicOptInDuringUploads() async throws {
        let config = StationConfiguration(url: "https://example.invalid", token: "test-only-token")
        var requestedPaths: [String] = []
        let players = session(configuration: config) { request in
            requestedPaths.append(request.url!.path)
            XCTAssertNotEqual(request.httpMethod, "PATCH", "Saving a result cannot opt anyone into public sharing")
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        players.player = alice
        let run = players.beginRun(game: .tennis, mode: "Tennis")
        _ = players.finishTennis(tennisResult(), demo: false, runID: run.id)
        await players.flushPending()
        XCTAssertEqual(players.player?.isPublic, false)
        XCTAssertTrue(requestedPaths.contains("/api/runs"))
    }

    @MainActor
    func testSelectingGuestWhileSignInIsPendingIgnoresLateProfile() async throws {
        let config = StationConfiguration(url: "https://example.invalid", token: "test-only-token")
        let started = expectation(description: "Sign-in requested")
        var continuation: CheckedContinuation<Void, Never>?
        let found = bob
        let players = session(configuration: config) { request in
            await withCheckedContinuation { continuation = $0; started.fulfill() }
            return (try JSONEncoder().encode(found), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        players.signIn("test-badge-code")
        await fulfillment(of: [started], timeout: 1)
        players.selectGuest()
        let run = players.beginRun(game: .neonRush, mode: "Arcade")
        continuation?.resume()
        for _ in 0..<100 where players.busy { await Task.yield() }
        XCTAssertFalse(players.busy)
        XCTAssertNil(players.player)
        XCTAssertTrue(players.activeRun?.isGuest == true)
        XCTAssertEqual(players.activeRun?.id, run.id)
    }
}
