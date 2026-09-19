import AppKit
import AVFoundation
import Vision
import SwiftUI

struct CameraChoice: Identifiable {
    let id: String
    let name: String
}

final class HandTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var devices: [CameraChoice] = []
    @Published var selectedID = ""
    @Published var running = false
    @Published var status = "Camera off · AirPod rotation only"
    @Published var point: CGPoint?
    @Published var confidence: Float = 0
    @Published var frameRate = 0.0
    @Published var mirrored = true { didSet { previousPoint = nil; point = nil; onLost?() } }
    @Published var preview: NSImage?
    @Published var handSelection = 0 { didSet { previousPoint = nil; point = nil; onLost?() } }
    var scanBadges = false
    var onBadge: ((String, String?) -> Void)?
    let session = AVCaptureSession()
    var onPoint: ((CGPoint, Double) -> Void)?
    var onLost: (() -> Void)?
    private let captureQueue = DispatchQueue(label: "aircade.camera.capture")
    private let visionQueue = DispatchQueue(label: "aircade.camera.vision", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var previousPoint: CGPoint?
    private var lastArrival = 0.0
    private var lastInference = 0.0
    private var lastPreview = 0.0
    private var generation = 0
    private var lastPublishedFrame = 0.0
    private var watchdog: Timer?

    override init() {
        super.init()
        request.maximumHandCount = 2
        refreshDevices()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.running, self.point != nil else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastArrival > 0.3 {
                self.loseHand("Hand lost · keep your controller hand visible")
            }
        }
    }
    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        devices = discovery.devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
        if !devices.contains(where: { $0.id == selectedID }) {
            selectedID = devices.first(where: { $0.name.lowercased().contains("kiyo") })?.id ?? devices.first?.id ?? ""
        }
    }
    func start() {
        stop()
        generation += 1
        let token = generation
        status = "Requesting camera access…"
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                guard allowed else { self.status = "Camera denied · enable it in Privacy & Security → Camera"; return }
                self.configure(token: token)
            }
        }
    }
    private func configure(token: Int) {
        let id = selectedID
        status = "Starting camera…"
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = self.scanBadges ? .hd1280x720 : .vga640x480
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            do {
                let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
                guard let device = discovery.devices.first(where: { $0.uniqueID == id }) else {
                    throw NSError(domain: "Aircade", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected camera is unavailable"])
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw NSError(domain: "Aircade", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open camera input"]) }
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.visionQueue)
                guard self.session.canAddOutput(output) else { throw NSError(domain: "Aircade", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot read camera frames"]) }
                self.session.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.running = true; self.status = self.scanBadges ? "Point the camera at your badge QR code" : "Show your controller hand to the camera"
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.status = error.localizedDescription
                }
            }
        }
    }
    func stop() {
        generation += 1
        running = false; frameRate = 0; preview = nil
        loseHand(scanBadges ? "Camera off · ready to scan a badge" : "Camera off · AirPod rotation only")
        captureQueue.async { [weak self] in self?.session.stopRunning() }
    }
    private func loseHand(_ message: String) {
        point = nil; confidence = 0; previousPoint = nil; status = message
        onLost?()
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastInference >= (scanBadges ? 0.25 : 1.0 / 30),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastInference = time
        if scanBadges {
            let barcode = VNDetectBarcodesRequest()
            barcode.symbologies = [.qr]
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            try? handler.perform([barcode])
            // Ignore frames with multiple QR codes rather than pairing the wrong name.
            let observation = barcode.results?.count == 1 ? barcode.results?.first : nil
            let payload = observation?.payloadStringValue
            let suggestedName = observation.flatMap { BadgeNameReader.read(using: handler, below: $0.boundingBox) }
            let input = CIImage(cvPixelBuffer: buffer)
            let image = imageContext.createCGImage(input, from: input.extent).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, ProcessInfo.processInfo.systemUptime - time < 3 else { return }
                self.preview = image
                self.status = "Point the camera at your badge QR code"
                if let payload { self.onBadge?(payload, suggestedName) }
            }
            return
        }
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            var candidates: [(CGPoint, Float)] = []
            for hand in request.results ?? [] {
                let names: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
                let points = names.compactMap { try? hand.recognizedPoint($0) }.filter { $0.confidence >= 0.3 }
                guard points.count >= 3 else { continue }
                let x = points.reduce(CGFloat(0)) { $0 + $1.location.x } / CGFloat(points.count)
                let y = points.reduce(CGFloat(0)) { $0 + $1.location.y } / CGFloat(points.count)
                candidates.append((CGPoint(x: x, y: y), points.map(\.confidence).reduce(0, +) / Float(points.count)))
            }
            var thumbnail: NSImage?
            if time - lastPreview > 0.1 {
                lastPreview = time
                let input = CIImage(cvPixelBuffer: buffer)
                if let cg = imageContext.createCGImage(input, from: input.extent) {
                    thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
            let captured = candidates
            let image = thumbnail
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, ProcessInfo.processInfo.systemUptime - time < 0.25 else { return }
                if let image { self.preview = image }
                let points = captured.map { (CGPoint(x: self.mirrored ? 1 - $0.0.x : $0.0.x, y: $0.0.y), $0.1) }
                let chosen: (CGPoint, Float)?
                if let previous = self.previousPoint {
                    chosen = points.min { hypot($0.0.x - previous.x, $0.0.y - previous.y) < hypot($1.0.x - previous.x, $1.0.y - previous.y) }
                    if let chosen, hypot(chosen.0.x - previous.x, chosen.0.y - previous.y) > 0.3 {
                        self.loseHand("Hand moved out of tracking range · reacquiring")
                        return
                    }
                } else {
                    chosen = self.handSelection == 0 ? points.max { $0.0.x < $1.0.x } : points.min { $0.0.x < $1.0.x }
                }
                guard let chosen else { self.loseHand("Hand lost · open your fingers slightly and keep the grip visible"); return }
                let dt = time - self.lastPublishedFrame
                self.lastPublishedFrame = time
                self.frameRate = dt > 0 && dt < 0.3 ? 1 / dt : 0
                self.previousPoint = chosen.0; self.point = chosen.0; self.confidence = chosen.1
                self.lastArrival = time
                self.status = "Hand tracked · screen-plane position"
                self.onPoint?(chosen.0, time)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.loseHand("Vision error: \(error.localizedDescription)") }
        }
    }
}

struct HandPreview: View {
    @ObservedObject var tracker: HandTracker
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = tracker.preview {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .scaleEffect(x: tracker.mirrored ? -1 : 1, y: 1)
                    if let p = tracker.point {
                        let aspect = image.size.width / image.size.height
                        let w = min(geometry.size.width, geometry.size.height * aspect)
                        let h = w / aspect
                        Circle().stroke(Color.cyan, lineWidth: 3).frame(width: 18, height: 18)
                            .position(x: (geometry.size.width - w) / 2 + p.x * w,
                                      y: (geometry.size.height - h) / 2 + (1 - p.y) * h)
                    }
                } else {
                    Image(systemName: tracker.scanBadges ? "qrcode.viewfinder" : "hand.raised").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
