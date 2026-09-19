import Foundation
import Combine
import MotionCore
import ControllerLink
import simd

enum ControllerDevice: String, CaseIterable, Identifiable { case airPod, phone; var id: Self { self } }

/// An immutable accepted sample. capturedAt never advances when the UI polls it.
struct ControllerSnapshot {
    let device: ControllerDevice
    let controllerID: UUID
    let sessionID: UUID
    let sequence: UInt64
    let source: String
    let orientation: simd_quatf
    let receivedAt: Double
    let capturedAt: Double
    let ready: Bool
    let simulated: Bool
    func age(at now: Double) -> Double {
        guard now.isFinite, now >= receivedAt else { return .infinity }
        return now - capturedAt
    }
    func isFresh(at now: Double) -> Bool { ready && age(at: now) < 0.25 }
}

/// App-lifetime devices, latest samples, and assignment. No game or scene ownership.
final class ControllerSession: ObservableObject {
    @Published private(set) var soloDevice: ControllerDevice = .airPod
    @Published private(set) var menuDevice: ControllerDevice = .airPod
    @Published private(set) var duelAssignments: [PlayerSlot: ControllerDevice] = [.one: .airPod, .two: .phone]
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var duelActive = false
    let titan = TitanHaptics()
    let phoneHost: PhoneControllerHost
    var onInputChanged: ((ControllerDevice) -> Void)?
    var onInvalidation: ((ControllerDevice, String) -> Void)?
    var onAssignmentChanged: (() -> Void)?
    var onRecenterAirPod: (() -> Void)?
    let invalidations = PassthroughSubject<(ControllerDevice, String), Never>()
    let assignmentChanges = PassthroughSubject<Void, Never>()
    let clock: () -> Double
    private let automaticTimer: Bool
    private var timer: Timer?
    private var hostObservation: AnyCancellable?
    private var local = PlayerControllers()
    private let localID = UUID()
    private var localSession = UUID()
    private var localSequence: UInt64 = 0
    private var lastAirPodTime: Double?
    private var lastAirPodSource: String?
    private var airPodReferenceInvalidated = false
    private var activeFeedback: (id: UUID, recipients: [ControllerDevice: (UUID, UUID)])?

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, automaticTimer: Bool = true) {
        self.clock = clock; self.automaticTimer = automaticTimer
        phoneHost = PhoneControllerHost(clock: clock)
        local.assign(.one, controllerID: localID, sessionID: localSession)
        phoneHost.onInputChanged = { [weak self] in self?.changed(.phone) }
        phoneHost.onInvalidation = { [weak self] reason in
            self?.revision &+= 1; self?.invalidated(.phone, reason)
        }
        phoneHost.onConnectionChanged = { [weak self] in self?.revision &+= 1 }
        hostObservation = phoneHost.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        updatePhoneRole()
    }
    /// Explicit start keeps unit tests and preview construction free of listeners.
    func start() {
        phoneHost.start()
        guard automaticTimer, timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func tick() { phoneHost.tick() }
    func shutdown() {
        timer?.invalidate(); timer = nil
        endRun(); phoneHost.shutdown(); titan.disconnect()
    }
    func selectSolo(_ device: ControllerDevice) {
        guard soloDevice != device else { return }
        soloDevice = device; updatePhoneRole(); assignmentChanges.send(); onAssignmentChanged?()
    }
    func selectMenu(_ device: ControllerDevice) { menuDevice = device }
    /// Swaps roles without re-pairing or touching either device's calibration.
    func assign(_ device: ControllerDevice, to slot: PlayerSlot) {
        guard duelAssignments[slot] != device else { return }
        let previous = duelAssignments[slot]
        if duelAssignments[slot.other] == device { duelAssignments[slot.other] = previous }
        duelAssignments[slot] = device
        updatePhoneRole(); assignmentChanges.send(); onAssignmentChanged?()
    }
    func setDuelActive(_ active: Bool) { duelActive = active; updatePhoneRole() }
    func device(for slot: PlayerSlot) -> ControllerDevice? { duelAssignments[slot] }

    func snapshot(for device: ControllerDevice, at _: Double? = nil) -> ControllerSnapshot? {
        let connection = device == .airPod ? local[.one] : phoneHost.connection
        guard let connection, let frame = connection.frame, let receivedAt = connection.receivedAt,
              let capturedAt = connection.capturedAt, let orientation = connection.orientation else { return nil }
        return ControllerSnapshot(device: device, controllerID: connection.controllerID, sessionID: connection.sessionID,
            sequence: frame.sequence, source: frame.source, orientation: orientation, receivedAt: receivedAt,
            capturedAt: capturedAt, ready: frame.ready, simulated: frame.simulated)
    }
    func snapshot(for slot: PlayerSlot) -> ControllerSnapshot? {
        duelAssignments[slot].flatMap { snapshot(for: $0) }
    }
    func name(for device: ControllerDevice) -> String {
        if device == .phone { return "iPhone" }
        return snapshot(for: .airPod)?.source ?? lastAirPodSource ?? "AirPod"
    }
    func readiness(for device: ControllerDevice) -> String {
        guard let value = snapshot(for: device) else {
            return device == .phone ? phoneHost.status : "Connect and calibrate an AirPod"
        }
        if !value.ready { return "Recenter \(name(for: device))" }
        return value.isFresh(at: clock()) ? "\(name(for: device)) ready" : "Waiting for \(name(for: device)) motion"
    }

    /// Root passes the accepted host timestamp; this layer never recalibrates or smooths.
    @discardableResult
    func submitAirPod(orientation: simd_quatf, source: String, ready: Bool, simulated: Bool = false, sampleTime: Double) -> Bool {
        let now = clock()
        guard now.isFinite, sampleTime.isFinite, sampleTime <= now else { return false }
        if let lastAirPodSource, lastAirPodSource != source {
            localSession = UUID(); localSequence = 0; lastAirPodTime = nil
            local.assign(.one, controllerID: localID, sessionID: localSession)
            invalidated(.airPod, "AirPod source changed. Check the active earbud, then resume.")
        }
        guard lastAirPodTime.map({ sampleTime > $0 || (airPodReferenceInvalidated && sampleTime == $0) }) ?? true else { return false }
        let frame = PlayerControllerFrame(controllerID: localID, sessionID: localSession, sequence: localSequence + 1,
            source: source, orientation: orientation, ready: ready, simulated: simulated, sampleAge: now - sampleTime)
        guard local.receive(frame, for: .one, at: now) else { return false }
        localSequence += 1; lastAirPodTime = sampleTime; lastAirPodSource = source
        airPodReferenceInvalidated = false
        changed(.airPod); return true
    }
    func invalidateAirPod(reason: String) {
        local.invalidate(.one); airPodReferenceInvalidated = true
        revision &+= 1; invalidated(.airPod, reason)
    }
    func recenter(_ device: ControllerDevice) {
        if device == .phone { phoneHost.recenter() }
        else { invalidateAirPod(reason: "AirPod recentered. Hold it upright, then resume."); onRecenterAirPod?() }
    }
    func forgetPhone() { phoneHost.forget() }

    /// Feedback snapshots physical connection epochs. Assignment/reconnect cannot
    /// redirect a delayed event to a different player or a new phone connection.
    @discardableResult
    func beginRun() -> UUID {
        var recipients: [ControllerDevice: (UUID, UUID)] = [:]
        for device in ControllerDevice.allCases {
            let connection = device == .airPod ? local[.one] : phoneHost.connection
            if let connection { recipients[device] = (connection.controllerID, connection.sessionID) }
        }
        let id = UUID(); activeFeedback = (id, recipients); phoneHost.setActiveRun(id); return id
    }
    func endRun(_ id: UUID? = nil) {
        guard id == nil || activeFeedback?.id == id else { return }
        activeFeedback = nil; phoneHost.setActiveRun(nil)
    }
    func sendFeedback(run: UUID, to device: ControllerDevice, cue: ControllerFeedback) {
        guard let activeFeedback, activeFeedback.id == run,
              let original = activeFeedback.recipients[device] else { return }
        if let sample = snapshot(for: device), sample.controllerID == original.0,
           sample.sessionID == original.1, sample.isFresh(at: clock()), !sample.simulated,
           let effect = TitanEffect(rawValue: cue.rawValue) {
            titan.play(effect, for: device)
        }
        guard device == .phone, let current = phoneHost.connection,
              current.controllerID == original.0, current.sessionID == original.1 else { return }
        phoneHost.feedback(run: run, cue: cue)
    }
    private func changed(_ device: ControllerDevice) { revision &+= 1; onInputChanged?(device) }
    private func invalidated(_ device: ControllerDevice, _ reason: String) {
        invalidations.send((device, reason)); onInvalidation?(device, reason)
    }
    private func updatePhoneRole() {
        if duelActive, let slot = PlayerSlot.allCases.first(where: { duelAssignments[$0] == .phone }) {
            phoneHost.setRole(.player(slot.rawValue + 1))
        } else { phoneHost.setRole(soloDevice == .phone ? .solo : .unassigned) }
    }
    deinit { timer?.invalidate() }
}
