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
}
