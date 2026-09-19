import XCTest
@testable import Aircade

final class ShellRoutingTests: XCTestCase {
    func testAPlainLaunchOpensTheHomeScreen() {
        XCTAssertEqual(WiiShell.initialRoute(arguments: ["Aircade"]), .home)
    }

    func testTheGameSmokeFlagsJumpStraightIntoNeonRush() {
        for flag in ["--game-smoke-test", "--scripted-game-test", "--scripted-repro", "--scripted-demo"] {
            XCTAssertEqual(WiiShell.initialRoute(arguments: ["Aircade", flag]), .neonRush, "\(flag) must bypass the channel grid")
        }
    }

    func testTheLabFlagsJumpStraightIntoTheTrainingLab() {
        for flag in ["--smoke-test", "--simple-calibration"] {
            XCTAssertEqual(WiiShell.initialRoute(arguments: ["Aircade", flag]), .lab, "\(flag) must bypass the channel grid")
        }
    }

    func testTheMultiplayerFlagOpensTheDuelChannel() {
        XCTAssertEqual(WiiShell.initialRoute(arguments: ["Aircade", "--multiplayer"]), .duel)
    }

    func testAnUnrecognisedFlagStillOpensHome() {
        XCTAssertEqual(WiiShell.initialRoute(arguments: ["Aircade", "--nonsense"]), .home)
    }
}
