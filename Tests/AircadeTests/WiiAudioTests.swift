import XCTest
@testable import Aircade

final class WiiAudioTests: XCTestCase {
    func testAToneIsTheRequestedLength() {
        let samples = WiiAudio.tone(frequency: 880, duration: 0.05, sampleRate: 44_100)
        XCTAssertEqual(samples.count, 2_205)
    }

    func testAToneIsAudibleRatherThanSilent() {
        let samples = WiiAudio.tone(frequency: 880, duration: 0.05, sampleRate: 44_100)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1)
    }

    func testAToneStartsAndEndsNearSilenceSoItDoesNotClick() {
        let samples = WiiAudio.tone(frequency: 880, duration: 0.05, sampleRate: 44_100)
        XCTAssertLessThan(abs(samples.first ?? 1), 0.02)
        XCTAssertLessThan(abs(samples.last ?? 1), 0.02)
    }

    func testEveryCueHasADistinctPitch() {
        let pitches = Set(WiiAudio.Cue.allCases.map(\.frequency))
        XCTAssertEqual(pitches.count, WiiAudio.Cue.allCases.count)
    }

    func testMusicLooksInsideTheAppBeforeUsingTheLegacySiblingFolder() {
        let app = URL(fileURLWithPath: "/tmp/Aircade.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)

        XCTAssertEqual(
            WiiAudio.musicFolders(bundleURL: app, resourceURL: resources),
            [
                resources.appendingPathComponent("Music", isDirectory: true),
                URL(fileURLWithPath: "/tmp/Resources/Music", isDirectory: true)
            ]
        )
    }

    func testBundledMusicIsDetected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = root.appendingPathComponent("Aircade.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let music = resources.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(WiiAudio.hasPlayableMusic(bundleURL: app, resourceURL: resources))
        try Data([0]).write(to: music.appendingPathComponent("Menu.mp3"))
        XCTAssertTrue(WiiAudio.hasPlayableMusic(bundleURL: app, resourceURL: resources))
    }
}
