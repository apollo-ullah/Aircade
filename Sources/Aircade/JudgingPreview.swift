import AppKit
import MotionCore
import SceneKit
import SwiftUI
import simd

/// Opt-in, unattended layout QA. No physical sensors, provider requests or score uploads.
/// Run from the repository with `Aircade --judging-preview`; outputs use the log directory.
enum JudgingPreview {
    static var requested: Bool { CommandLine.arguments.contains("--judging-preview") }
    private static let defaultsName = "Aircade.JudgingPreview"
    private static var driver: Driver?

    static func makeMotionForLaunch() -> MotionModel {
        guard requested else { return MotionModel() }
        let directory = ProcessInfo.processInfo.environment["AIRCADE_LOG_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("build/judging-preview", isDirectory: true)
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let model = MotionModel(logDirectory: directory, scoreDefaults: defaults,
                                tennisOpponent: AutomaticReboundOpponent())
        model.gripDefaults = defaults
        model.clock = { 100 }
        model.game.sound = false; model.tennis.sound = false
        return model
    }

    static var banner: some View {
        Text("SIMULATED UI PREVIEW · No hardware or API evidence")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 5)
            .background(.orange.opacity(0.94), in: Capsule()).padding(.top, 5)
            .allowsHitTesting(false)
    }

    @MainActor static func run(_ motion: MotionModel) {
        guard driver == nil else { return }
        driver = Driver(motion: motion)
        driver?.start()
    }

    @MainActor private final class Driver {
        let motion: MotionModel
        let size = NSSize(width: 1120, height: 760)
        var fixtureWindow: NSWindow?
        var output: [[String: Any]] = []

        init(motion: MotionModel) { self.motion = motion }

        func start() {
            guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
                finish(error: "Main window was not created."); return
            }
            window.setContentSize(size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            later {
                self.captureMain("01-home")
                NotificationCenter.default.post(name: .wiiRouteRequest, object: Route.tennis)
                self.later {
                    self.captureMain("02-tennis-lobby-no-controller")
                    self.motion.controllers.selectSolo(.airPod)
                    self.motion.simulated = true; self.motion.running = true
                    self.motion.receive(q: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)),
                        euler: .zero, rate: .zero, accel: .zero, sensorTime: 100,
                        location: "Simulated", receivedAt: 100)
                    self.later {
                        self.captureMain("03-tennis-lobby-simulated")
                        self.showFixture(SensorEvidenceView.previewFixture, name: "04-sensor-input-simulated") {
                            self.showFixture(SensorEvidenceView.recordedPreviewFixture, name: "05-sensor-replay-simulated") {
                                self.finish()
                            }
                        }
                    }
                }
            }
        }

        private func later(_ operation: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: operation)
        }

        private func captureMain(_ name: String) {
            guard let view = NSApp.windows.first(where: { $0.contentView != nil && $0 !== fixtureWindow })?.contentView else {
                output.append(["file": name, "passed": false, "error": "Main content view unavailable"]); return
            }
            capture(view, name: name)
            if name.contains("tennis") {
                // AppKit bitmap caching may omit the Metal-backed SceneKit layer.
                // Export the actual court separately so layout and scene can both be reviewed.
                let scene = SCNView(frame: NSRect(origin: .zero, size: size))
                scene.scene = motion.scene.scene
                scene.antialiasingMode = .multisampling4X
                if let tiff = scene.snapshot().tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    save(png, name: "\(name)-scene", width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
                }
            }
        }

        private func showFixture<V: View>(_ fixture: V, name: String, completion: @escaping @MainActor () -> Void) {
            let host = NSHostingView(rootView: ZStack(alignment: .top) {
                WiiTheme.stage
                fixture.frame(maxWidth: .infinity, maxHeight: .infinity)
                JudgingPreview.banner
            }.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Judging UI preview · simulated"
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.center(); window.makeKeyAndOrderFront(nil)
            fixtureWindow = window
            later {
                self.capture(host, name: name)
                window.orderOut(nil)
                self.fixtureWindow = nil
                completion()
            }
        }

        private func capture(_ view: NSView, name: String) {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                output.append(["file": name, "passed": false, "error": "Bitmap allocation failed"]); return
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                output.append(["file": name, "passed": false, "error": "PNG encoding failed"]); return
            }
            save(png, name: name, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        private func save(_ data: Data, name: String, width: Int, height: Int) {
            do {
                try data.write(to: motion.logDirectory.appendingPathComponent("\(name).png"))
                output.append(["file": "\(name).png", "passed": true, "pixelsWide": width, "pixelsHigh": height])
            } catch {
                output.append(["file": name, "passed": false, "error": error.localizedDescription])
            }
        }

        private func finish(error: String? = nil) {
            if let error { output.append(["passed": false, "error": error]) }
            let passed = output.count >= 7 && output.allSatisfy { $0["passed"] as? Bool == true } && motion.players.pendingRuns.isEmpty
            let report: [String: Any] = ["passed": passed, "viewport": ["width": 1120, "height": 760],
                "hardwareVerified": false, "apiVerified": false, "input": "simulated fixture only",
                "scoresQueued": motion.players.pendingRuns.count, "screenshots": output]
            if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? json.write(to: motion.logDirectory.appendingPathComponent("judging-preview-result.json"))
            }
            print("JUDGING PREVIEW \(passed ? "PASS" : "FAIL") · \(motion.logDirectory.path) · no hardware/API evidence")
            motion.stop()
            UserDefaults(suiteName: JudgingPreview.defaultsName)?.removePersistentDomain(forName: JudgingPreview.defaultsName)
            NSApp.terminate(nil)
        }
    }
}
