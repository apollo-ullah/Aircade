import XCTest
import AVFoundation
import CoreAudio
import IOKit.audio
@testable import Aircade

final class AudioOutputTests: XCTestCase {
    private let airPods = AudioOutputDevice(id: 1, uid: "pods", name: "AirPods", isBuiltInSpeaker: false)
    private let speakers = AudioOutputDevice(id: 2, uid: "mac", name: "Mac speakers", isBuiltInSpeaker: true)

    func testAppleSpeakerIdentifiersAndHeadphoneExclusion() {
        XCTAssertTrue(AudioDeviceCatalog.isBuiltInSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, terminals: [UInt32(OUTPUT_SPEAKER)], source: nil))
        XCTAssertTrue(AudioDeviceCatalog.isBuiltInSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, terminals: [kAudioStreamTerminalTypeSpeaker], source: nil))
        XCTAssertTrue(AudioDeviceCatalog.isBuiltInSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, terminals: [], source: UInt32(kIOAudioOutputPortSubTypeInternalSpeaker)))
        XCTAssertFalse(AudioDeviceCatalog.isBuiltInSpeaker(transport: kAudioDeviceTransportTypeBluetooth, terminals: [UInt32(OUTPUT_SPEAKER)], source: nil))
        XCTAssertFalse(AudioDeviceCatalog.isBuiltInSpeaker(transport: kAudioDeviceTransportTypeBuiltIn, terminals: [UInt32(OUTPUT_SPEAKER)], source: UInt32(kIOAudioOutputPortSubTypeHeadphones)))
    }

    func testSpeakersIgnoreTheSystemAirPodsDefaultAndNeverFallBackToIt() {
        XCTAssertEqual(AudioOutputPreference.speakers.resolve(devices: [airPods, speakers], defaultID: 1), speakers)
        XCTAssertNil(AudioOutputPreference.speakers.resolve(devices: [airPods], defaultID: 1))
    }

    func testSystemSettingFollowsTheCurrentDefault() {
        XCTAssertEqual(AudioOutputPreference.system.resolve(devices: [airPods, speakers], defaultID: 1), airPods)
        XCTAssertEqual(AudioOutputPreference.system.resolve(devices: [airPods, speakers], defaultID: 2), speakers)
        XCTAssertNil(AudioOutputPreference.system.resolve(devices: [speakers], defaultID: nil))
    }

    @MainActor
    func testPreferenceDefaultsToSpeakersAndSurvivesSettingsRecreation() {
        let suite = "audio-tests-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AudioOutput(defaults: defaults, observeHardware: false)
        XCTAssertEqual(settings.preference, .speakers)
        settings.select(.system)
        XCTAssertEqual(AudioOutput(defaults: defaults, observeHardware: false).preference, .system)
        settings.select(.speakers)
        XCTAssertEqual(AudioOutput(defaults: defaults, observeHardware: false).preference, .speakers)
    }

    func testGeneratedCuesDecodeAsRealMonoAudioWithTheExpectedDuration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cue-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = WiiAudio.tone(frequency: 880, duration: 0.05, sampleRate: 44_100)
        try WiiAudio.wave(samples: samples).write(to: url)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 2_205)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2_205)!
        try file.read(into: buffer)
        let decoded = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 2_205))
        XCTAssertGreaterThan(decoded.map(abs).max()!, 0.1)
        XCTAssertLessThan(abs(decoded.first!), 0.02)
    }
}
