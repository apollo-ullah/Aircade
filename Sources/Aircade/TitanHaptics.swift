import Foundation
import Combine
import Darwin
import ControllerLink

/// TITAN Core stock firmware serial protocol (Quick Start Guide, page 9).
enum TitanEffect: String, CaseIterable {
    case hit, block, damage, victory, defeat, draw, touch

    func command(channel: Int, intensity: Double) -> String {
        let gain = intensity.isFinite ? min(1, max(0, intensity)) : 0
        func strength(_ value: Double) -> String {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value * gain)
        }
        let effect: String
        switch self {
        case .hit: effect = "Tick \(strength(0.8)) 20;"
        case .block: effect = "Pulse \(strength(0.65)) 45;"
        case .damage: effect = "Vibrate 90 \(strength(0.6)) 140 0.5 0.3;"
        case .victory: effect = "Vibrate 180 \(strength(0.5)) 180 0.5 0;"
        case .defeat: effect = "Vibrate 60 \(strength(0.45)) 200 0.5 0;"
        case .draw: effect = "Pulse \(strength(0.4)) 100;"
        case .touch: effect = "Tick \(strength(0.3)) 10;"
        }
        return "CHNL \(min(3, max(1, channel))); \(effect)\n"
    }
}

/// Main-thread owned. Nonblocking writes never wait on hardware or queue old hits.
/// Connection is explicit: constructing a model/test never opens a serial device.
final class TitanHaptics: ObservableObject {
    @Published private(set) var status = "Disconnected"
    @Published private(set) var connected = false
    @Published var channel = 1
    @Published var recipient: ControllerDevice = .airPod
    @Published var intensity = 0.5
    private let openPort: (String) -> Int32
    init(openPort: @escaping (String) -> Int32 = { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }) {
        self.openPort = openPort
    }
    private var descriptor: Int32 = -1
    private var lastEffect = -Double.infinity
    private var savedOptions: termios?
    private var drainTimer: Timer?

    static func ports() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("cu.usb") || $0.hasPrefix("cu.SLAB") || $0.hasPrefix("cu.wch") }
            .sorted().map { "/dev/" + $0 }
    }

    func connect(path: String) {
        disconnect()
        guard path.hasPrefix("/dev/cu."), !path.dropFirst(5).contains("/") else {
            status = "Choose a serial port under /dev/cu.*"; return
        }
        let fd = openPort(path)
        guard fd >= 0 else { fail("Open failed"); return }
        descriptor = fd
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { fail("Serial configuration failed"); return }
        savedOptions = options
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSTOPB | PARENB | CRTSCTS)
        cfsetispeed(&options, speed_t(B115200)); cfsetospeed(&options, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { fail("Baud rate configuration failed"); return }
        tcflush(fd, TCIOFLUSH)
        connected = true; status = "Port open · 115200 baud · use Test to verify motor"
        lastEffect = -Double.infinity
        // Drain diagnostic output so firmware logging cannot back up indefinitely.
        drainTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.descriptor >= 0 else { return }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(self.descriptor, &bytes, bytes.count)
            if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { self.fail("Device disconnected") }
        }
    }

    func disconnect() {
        drainTimer?.invalidate(); drainTimer = nil
        if descriptor >= 0 {
            tcflush(descriptor, TCIOFLUSH)
            if var options = savedOptions { tcsetattr(descriptor, TCSANOW, &options) }
            Darwin.close(descriptor)
        }
        descriptor = -1; savedOptions = nil; connected = false; status = "Disconnected"
    }

    func play(_ effect: TitanEffect, for device: ControllerDevice? = nil) {
        guard connected, device == nil || device == recipient, intensity > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEffect >= 0.025 else { return }
        let bytes = Array(effect.command(channel: channel, intensity: intensity).utf8)
        let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == bytes.count else {
            // A full buffer drops this event. A partial command disconnects so it
            // cannot be joined to a later hit and interpreted as a different effect.
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            fail("Serial write failed"); return
        }
        lastEffect = now
    }

    private func fail(_ message: String) {
        let detail = String(cString: strerror(errno))
        disconnect(); status = "\(message): \(detail)"
    }
    deinit {
        drainTimer?.invalidate()
        if descriptor >= 0 { Darwin.close(descriptor) }
    }
}
