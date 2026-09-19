import XCTest
import Darwin
@testable import Aircade

final class TitanHapticsTests: XCTestCase {
    func testRealSerialConfigurationAndBytesThroughPseudoTerminal() throws {
        var master: Int32 = -1, slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        defer { Darwin.close(master); Darwin.close(slave) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let haptics = TitanHaptics(openPort: { _ in dup(slave) })
        haptics.connect(path: "/dev/cu.test")
        defer { haptics.disconnect() }
        XCTAssertTrue(haptics.connected)
        var options = termios()
        XCTAssertEqual(tcgetattr(slave, &options), 0)
        XCTAssertEqual(cfgetospeed(&options), speed_t(B115200))
        XCTAssertEqual(options.c_lflag & tcflag_t(ICANON | ECHO), 0)
        haptics.channel = 2; haptics.intensity = 0.5
        haptics.play(.hit, for: .phone) // Wrong player must not receive it.
        var buffer = [UInt8](repeating: 0, count: 512)
        XCTAssertEqual(Darwin.read(master, &buffer, buffer.count), -1)
        haptics.play(.hit, for: .airPod)
        var received = ""
        let deadline = Date().addingTimeInterval(0.5)
        repeat {
            let count = Darwin.read(master, &buffer, buffer.count)
            if count > 0 { received += String(decoding: buffer.prefix(count), as: UTF8.self) }
            if received.contains("\n") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        } while Date() < deadline
        XCTAssertEqual(received, "CHNL 2; Tick 0.400 20;\n")
        haptics.disconnect()
        haptics.play(.damage)
        XCTAssertEqual(Darwin.read(master, &buffer, buffer.count), -1)
    }

    func testBoundedDistinctEffectsAndInvalidPort() {
        XCTAssertEqual(Set(TitanEffect.allCases.map { $0.command(channel: 1, intensity: 1) }).count, 7)
        XCTAssertEqual(TitanEffect.hit.command(channel: 99, intensity: .infinity), "CHNL 3; Tick 0.000 20;\n")
        XCTAssertEqual(TitanEffect.hit.command(channel: -1, intensity: 100), "CHNL 1; Tick 0.800 20;\n")
        var opened = false
        let haptics = TitanHaptics(openPort: { _ in opened = true; return -1 })
        haptics.connect(path: "/tmp/file")
        XCTAssertFalse(opened); XCTAssertFalse(haptics.connected)
        haptics.connect(path: "/dev/cu.missing")
        XCTAssertTrue(opened); XCTAssertFalse(haptics.connected)
    }
}
