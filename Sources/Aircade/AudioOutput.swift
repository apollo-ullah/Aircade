import CoreAudio
import Foundation
import Combine
import IOKit.audio

struct AudioOutputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isBuiltInSpeaker: Bool
}

enum AudioOutputPreference: String, CaseIterable, Identifiable {
    case speakers, system
    var id: String { rawValue }
    var title: String { self == .speakers ? "Mac speakers" : "System default" }

    func resolve(devices: [AudioOutputDevice], defaultID: AudioDeviceID?) -> AudioOutputDevice? {
        switch self {
        case .speakers: return devices.first(where: \.isBuiltInSpeaker)
        case .system: return devices.first { $0.id == defaultID }
        }
    }
}

extension Notification.Name {
    static let aircadeAudioOutputChanged = Notification.Name("Aircade.AudioOutputChanged")
}

/// Only selects devices for our players. Never changes the Mac's default output.
final class AudioOutput: ObservableObject {
    static let shared = AudioOutput()
    static let preferenceKey = "aircade.audioOutput"
    @Published private(set) var preference: AudioOutputPreference
    @Published private(set) var status = "Finding audio output…"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var route: AudioOutputDevice?
    private let queue = DispatchQueue(label: "Aircade.AudioDevices", qos: .userInitiated)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    var destination: AudioOutputDevice? {
        lock.lock(); defer { lock.unlock() }; return route
    }

    init(defaults: UserDefaults = .standard, observeHardware: Bool = true) {
        self.defaults = defaults
        preference = AudioOutputPreference(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .speakers
        if observeHardware {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
                if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, callback) == noErr {
                    listeners.append((address, callback))
                }
            }
            refresh()
        }
    }

    deinit {
        for (var address, callback) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, callback)
        }
    }

    func select(_ preference: AudioOutputPreference) {
        self.preference = preference
        defaults.set(preference.rawValue, forKey: Self.preferenceKey)
        refresh()
    }

    func refresh() {
        let requested = preference
        queue.async { [weak self] in
            let devices = AudioDeviceCatalog.outputs()
            let selected = requested.resolve(devices: devices, defaultID: AudioDeviceCatalog.defaultOutputID())
            DispatchQueue.main.async { [weak self] in
                guard let self, self.preference == requested else { return }
                self.lock.lock(); let changed = self.route != selected; self.route = selected; self.lock.unlock()
                self.status = selected.map { "Playing through \($0.name)" } ??
                    (requested == .speakers ? "Mac speakers unavailable. Audio is paused; choose System default to use another output." : "No audio output available.")
                if changed { NotificationCenter.default.post(name: .aircadeAudioOutputChanged, object: self) }
            }
        }
    }

    func reportPlaybackFailure() {
        DispatchQueue.main.async { self.status = "Audio could not start. Check the output volume, then try Test sound." }
    }
}

enum AudioDeviceCatalog {
    static func defaultOutputID() -> AudioDeviceID? {
        number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func outputs() -> [AudioOutputDevice] {
        ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { device in
            let streams = ids(device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            guard !streams.isEmpty, number(device, kAudioDevicePropertyDeviceIsAlive) == 1,
                  let uid = string(device, kAudioDevicePropertyDeviceUID), let name = string(device, kAudioObjectPropertyName) else { return nil }
            let speaker = isBuiltInSpeaker(transport: number(device, kAudioDevicePropertyTransportType),
                terminals: streams.compactMap { number($0, kAudioStreamPropertyTerminalType) },
                source: number(device, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput))
            return AudioOutputDevice(id: device, uid: uid, name: name, isBuiltInSpeaker: speaker)
        }
    }

    static func isBuiltInSpeaker(transport: UInt32?, terminals: [UInt32], source: UInt32?) -> Bool {
        guard transport == kAudioDeviceTransportTypeBuiltIn else { return false }
        if source == UInt32(kIOAudioOutputPortSubTypeHeadphones) || source == UInt32(kIOAudioOutputPortSubTypeLine) { return false }
        // Apple drivers use both modern Core Audio and legacy IOKit terminal identifiers.
        return source == UInt32(kIOAudioOutputPortSubTypeInternalSpeaker) ||
            terminals.contains(kAudioStreamTerminalTypeSpeaker) || terminals.contains(UInt32(OUTPUT_SPEAKER))
    }

    private static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else { return [] }
        return values
    }

    private static func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
