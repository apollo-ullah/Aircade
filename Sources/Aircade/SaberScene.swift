import AppKit
import SceneKit
import simd
import MotionCore

final class SaberScene {
    let scene = SCNScene()
    let pivot = SCNNode()
    private let bladeMaterial = SCNMaterial()
    private var live = true
    private let targetNode = SCNNode()
    private let effects = SCNNode()
    private let attackNode = SCNNode()
    private let ghostNode = SCNNode()
    private let directionNode = SCNNode()
    private var attackTarget = SIMD3<Float>.zero
    private var lastTrail: SIMD3<Float>?
    private let rushRoot = SCNNode()
    private let arcadeEnvironment = SCNNode()
    private var rushNodes: [Int: SCNNode] = [:]
    enum ImpactKind { case cut, glance, parry, damage }

    init() {
        scene.background.contents = NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.075, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = 1.3
        camera.camera?.bloomThreshold = 0.6
        camera.position = SCNVector3(0, 1.3, 6.3)
        camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        ambient.light?.color = NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.7, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight(); key.light?.type = .omni; key.light?.intensity = 1300
        key.position = SCNVector3(2, 3, 4)
        scene.rootNode.addChildNode(key)

        let floor = SCNFloor()
        floor.reflectivity = 0.12
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.045, alpha: 1)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -1.65
        scene.rootNode.addChildNode(floorNode)
        for i in -6...6 {
            let material = SCNMaterial()
            material.diffuse.contents = NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.25, alpha: 1)
            for axis in 0...1 {
                let geometry = SCNBox(width: axis == 0 ? 12 : 0.008, height: 0.008,
                                      length: axis == 0 ? 0.008 : 12, chamferRadius: 0)
                geometry.materials = [material]
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(axis == 0 ? 0 : Float(i), -1.64, axis == 0 ? Float(i) : 0)
                scene.rootNode.addChildNode(node)
            }
        }

        scene.rootNode.addChildNode(pivot)
        let handle = SCNCylinder(radius: 0.11, height: 0.62)
        handle.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.24, alpha: 1)
        handle.firstMaterial?.metalness.contents = 0.8
        handle.firstMaterial?.roughness.contents = 0.3
        let handleNode = SCNNode(geometry: handle)
        handleNode.position.y = -0.3
        pivot.addChildNode(handleNode)
        for i in 0..<6 {
            let ring = SCNTorus(ringRadius: 0.11, pipeRadius: 0.014)
            ring.firstMaterial?.diffuse.contents = NSColor.darkGray
            let node = SCNNode(geometry: ring)
            node.position.y = -0.52 + CGFloat(i) * 0.085
            pivot.addChildNode(node)
        }
        // Off-centre switch makes roll visible even though the blade is cylindrical.
        let button = SCNNode(geometry: SCNSphere(radius: 0.045))
        button.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        button.position = SCNVector3(0.1, -0.12, 0.035)
        pivot.addChildNode(button)

        let blade = SCNCapsule(capRadius: 0.045, height: 2.35)
        bladeMaterial.diffuse.contents = NSColor.white
        bladeMaterial.emission.contents = NSColor.cyan
        blade.materials = [bladeMaterial]
        let bladeNode = SCNNode(geometry: blade)
        bladeNode.position.y = 1.175
        pivot.addChildNode(bladeNode)
        scene.rootNode.addChildNode(targetNode)
        scene.rootNode.addChildNode(effects)
        scene.rootNode.addChildNode(attackNode)
        scene.rootNode.addChildNode(ghostNode)
        scene.rootNode.addChildNode(directionNode)
        scene.rootNode.addChildNode(rushRoot)
        scene.rootNode.addChildNode(arcadeEnvironment)
        buildArcadeEnvironment()
        setLive(false)
    }

    func setOrientation(_ q: simd_quatf) { pivot.simdOrientation = q }
    func setPose(_ pose: SaberPose, trail: Bool) {
        pivot.simdPosition = pose.position
        pivot.simdOrientation = pose.orientation
        let tip = pose.point(CombatGeometry.bladeLength)
        if trail, let lastTrail, simd_distance(lastTrail, tip) > 0.03, simd_distance(lastTrail, tip) < 1.3 {
            let line = lineNode(from: lastTrail, to: tip, radius: 0.009, color: .cyan)
            effects.addChildNode(line)
            line.runAction(.sequence([.fadeOut(duration: 0.18), .removeFromParentNode()]))
        }
        lastTrail = trail ? tip : nil
    }

    func resetTarget(position: SIMD3<Float>, visible: Bool) {
        targetNode.removeAllActions()
        targetNode.childNodes.forEach { $0.removeFromParentNode() }
        effects.childNodes.forEach { $0.removeFromParentNode() }
        targetNode.simdPosition = position
        targetNode.isHidden = !visible
        directionNode.isHidden = !visible
        let block = SCNBox(width: 0.66, height: 0.66, length: 0.66, chamferRadius: 0.04)
        block.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.15, green: 0.32, blue: 0.55, alpha: 1)
        block.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.13, alpha: 1)
        block.firstMaterial?.metalness.contents = 0.65
        block.firstMaterial?.roughness.contents = 0.25
        targetNode.addChildNode(SCNNode(geometry: block))
        for x in [-0.28, 0.28] {
            let strip = SCNNode(geometry: SCNBox(width: 0.014, height: 0.52, length: 0.01, chamferRadius: 0))
            strip.geometry?.firstMaterial?.emission.contents = NSColor.cyan
            strip.position = SCNVector3(x, 0, 0.335)
            targetNode.addChildNode(strip)
        }
    }
    func showCutDirection(_ direction: String) {
        directionNode.childNodes.forEach { $0.removeFromParentNode() }
        let text = SCNText(string: direction == "Any" ? "CUT" : direction == "Left" ? "←" : direction == "Right" ? "→" : "↓", extrusionDepth: 0.005)
        text.font = .boldSystemFont(ofSize: direction == "Any" ? 0.14 : 0.25)
        text.firstMaterial?.diffuse.contents = NSColor.white
        text.firstMaterial?.emission.contents = NSColor.white
        let node = SCNNode(geometry: text)
        let bounds = node.boundingBox
        node.position = SCNVector3(-Double(bounds.max.x - bounds.min.x) / 2, 0.95, 0.35)
        directionNode.addChildNode(node)
    }
    func splitTarget(velocity: SIMD3<Float>) {
        targetNode.isHidden = true; directionNode.isHidden = true
        for sign: Float in [-1, 1] {
            let half = SCNNode(geometry: SCNBox(width: 0.31, height: 0.66, length: 0.66, chamferRadius: 0.02))
            half.geometry?.firstMaterial?.diffuse.contents = NSColor.systemTeal
            half.simdPosition = targetNode.simdPosition + SIMD3<Float>(sign * 0.18, 0, 0)
            effects.addChildNode(half)
            let move = SCNAction.moveBy(x: CGFloat(sign * 0.75 + velocity.x * 0.015), y: -0.65, z: 0, duration: 0.65)
            half.runAction(.sequence([.group([move, .rotateBy(x: 0.8, y: CGFloat(sign), z: CGFloat(sign * 0.8), duration: 0.65), .fadeOut(duration: 0.65)]), .removeFromParentNode()]))
        }
    }
    func impact(at point: SIMD3<Float>, kind: ImpactKind, velocity: SIMD3<Float>) {
        let color: NSColor = kind == .damage ? .systemRed : kind == .glance ? .systemOrange : kind == .parry ? .systemYellow : .cyan
        for _ in 0..<22 {
            let spark = SCNNode(geometry: SCNSphere(radius: CGFloat.random(in: 0.013...0.034)))
            spark.geometry?.firstMaterial?.emission.contents = color
            spark.simdPosition = point
            effects.addChildNode(spark)
            let move = SCNAction.moveBy(x: CGFloat.random(in: -0.8...0.8), y: CGFloat.random(in: -0.6...0.8), z: CGFloat.random(in: -0.4...0.7), duration: 0.38)
            spark.runAction(.sequence([.group([move, .fadeOut(duration: 0.38)]), .removeFromParentNode()]))
        }
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.12, pipeRadius: 0.012))
        ring.eulerAngles.x = .pi / 2
        ring.geometry?.firstMaterial?.emission.contents = color
        ring.simdPosition = point
        effects.addChildNode(ring)
        ring.runAction(.sequence([.group([.scale(to: 5, duration: 0.3), .fadeOut(duration: 0.3)]), .removeFromParentNode()]))
        flash()
    }
    func showAttack(target: SIMD3<Float>, horizontalGuard: Bool) {
        hideAttack(); attackTarget = target
        let offset = horizontalGuard ? SIMD3<Float>(0.65, 0, 0) : SIMD3<Float>(0, 0.65, 0)
        let guardLine = lineNode(from: target - offset, to: target + offset, radius: 0.035, color: .systemGreen)
        guardLine.opacity = 0.38
        ghostNode.addChildNode(guardLine)
        let projectile = SCNNode(geometry: SCNSphere(radius: 0.13))
        projectile.geometry?.firstMaterial?.emission.contents = NSColor.systemOrange
        attackNode.addChildNode(projectile)
        attackNode.isHidden = false; ghostNode.isHidden = false
    }
    func advanceAttack(remaining: Double) {
        attackNode.simdPosition = attackTarget + SIMD3<Float>(0, 0, -Float(max(0, remaining)) * 3.3)
    }
    func hideAttack() {
        attackNode.childNodes.forEach { $0.removeFromParentNode() }
        ghostNode.childNodes.forEach { $0.removeFromParentNode() }
        attackNode.isHidden = true; ghostNode.isHidden = true
    }
    private func lineNode(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat, color: NSColor) -> SCNNode {
        let delta = b - a
        let node = SCNNode(geometry: SCNCylinder(radius: radius, height: CGFloat(simd_length(delta))))
        node.geometry?.firstMaterial?.diffuse.contents = NSColor.black
        node.geometry?.firstMaterial?.emission.contents = color
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        return node
    }
    func setArcadeVisible(_ visible: Bool) {
        arcadeEnvironment.isHidden = !visible
        rushRoot.isHidden = !visible
        if visible {
            targetNode.isHidden = true
            directionNode.isHidden = true
            hideAttack()
        }
    }
    private func buildArcadeEnvironment() {
        for index in 0..<9 {
            let z = -Float(index) * 2 - 1.5
            let color = index % 2 == 0 ? NSColor(calibratedRed: 0.13, green: 0.47, blue: 0.41, alpha: 1) : NSColor(calibratedRed: 0.28, green: 0.15, blue: 0.48, alpha: 1)
            for side: Float in [-1, 1] {
                let rail = lineNode(from: SIMD3<Float>(side * 3.1, -1.6, z), to: SIMD3<Float>(side * 3.1, 3.6, z), radius: 0.012, color: color)
                arcadeEnvironment.addChildNode(rail)
            }
            let top = lineNode(from: SIMD3<Float>(-3.1, 3.6, z), to: SIMD3<Float>(3.1, 3.6, z), radius: 0.012, color: color)
            arcadeEnvironment.addChildNode(top)
        }
        for x: Float in [-0.95, 0, 0.95] {
            let line = lineNode(from: SIMD3<Float>(x, -1.62, -18), to: SIMD3<Float>(x, -1.62, 1), radius: 0.014, color: NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.3, alpha: 1))
            arcadeEnvironment.addChildNode(line)
        }
    }
    func clearRush() {
        rushRoot.childNodes.forEach { $0.removeFromParentNode() }
        rushNodes = [:]
        effects.childNodes.forEach { $0.removeFromParentNode() }
        lastTrail = nil
    }
    func syncRush(targets: [RushTarget], elapsed: Double) {
        let activeIDs = Set(targets.map(\.id))
        for id in Array(rushNodes.keys) where !activeIDs.contains(id) {
            rushNodes.removeValue(forKey: id)?.removeFromParentNode()
        }
        for target in targets {
            let node: SCNNode
            if let existing = rushNodes[target.id] { node = existing }
            else {
                node = makeRushTarget(target)
                rushRoot.addChildNode(node); rushNodes[target.id] = node
            }
            node.simdPosition = target.position(at: elapsed)
            // Near-expiry pulses communicate the remaining cut window without moving the hitbox.
            node.opacity = elapsed > target.arrival + target.window * 0.65 ? CGFloat(0.65 + 0.35 * sin(elapsed * 22)) : 1
        }
    }
    private func makeRushTarget(_ target: RushTarget) -> SCNNode {
        let parent = SCNNode()
        let color: NSColor = target.hazard ? .systemRed : target.direction == .any ? NSColor(calibratedRed: 0.65, green: 1, blue: 0.22, alpha: 1) : .cyan
        let box = SCNBox(width: 0.62, height: 0.62, length: 0.62, chamferRadius: target.hazard ? 0.015 : 0.07)
        box.firstMaterial?.diffuse.contents = color.blended(withFraction: 0.65, of: .black)
        box.firstMaterial?.emission.contents = color.blended(withFraction: 0.88, of: .black)
        box.firstMaterial?.metalness.contents = 0.5
        parent.addChildNode(SCNNode(geometry: box))
        let frame = SCNBox(width: 0.58, height: 0.58, length: 0.018, chamferRadius: 0.06)
        frame.firstMaterial?.diffuse.contents = color
        frame.firstMaterial?.emission.contents = color
        let face = SCNNode(geometry: frame)
        face.position.z = 0.315
        parent.addChildNode(face)
        let inset = SCNNode(geometry: SCNBox(width: 0.52, height: 0.52, length: 0.018, chamferRadius: 0.04))
        inset.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.025, alpha: 1)
        inset.position.z = 0.33; parent.addChildNode(inset)
        let symbol = target.hazard ? "×" : target.direction == .left ? "←" : target.direction == .right ? "→" : target.direction == .down ? "↓" : "✦"
        let geometry = SCNText(string: symbol, extrusionDepth: 0.005)
        geometry.font = .systemFont(ofSize: 0.38, weight: .bold)
        geometry.flatness = 0.1
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = color
        let glyph = SCNNode(geometry: geometry)
        let bounds = glyph.boundingBox
        glyph.position = SCNVector3(-Double(bounds.max.x + bounds.min.x) / 2, -Double(bounds.max.y + bounds.min.y) / 2, 0.35)
        parent.addChildNode(glyph)
        return parent
    }
    func burstRushTarget(_ target: RushTarget, at point: SIMD3<Float>, velocity: SIMD3<Float>) {
        for sign: Float in [-1, 1] {
            let piece = SCNNode(geometry: SCNBox(width: 0.28, height: 0.6, length: 0.6, chamferRadius: 0.04))
            piece.geometry?.firstMaterial?.diffuse.contents = target.direction == .any ? NSColor.systemGreen : NSColor.cyan
            piece.simdPosition = point + SIMD3<Float>(sign * 0.15, 0, 0)
            effects.addChildNode(piece)
            piece.runAction(.sequence([.group([
                .moveBy(x: CGFloat(sign * 0.8 + velocity.x * 0.012), y: -0.6, z: 0.3, duration: 0.55),
                .rotateBy(x: 0.5, y: CGFloat(sign), z: CGFloat(sign), duration: 0.55),
                .fadeOut(duration: 0.55)]), .removeFromParentNode()]))
        }
    }
    func setLive(_ value: Bool) {
        guard live != value else { return }
        live = value
        bladeMaterial.emission.contents = value ? NSColor.cyan : NSColor(calibratedWhite: 0.15, alpha: 1)
    }
    func flash() {
        guard live else { return }
        bladeMaterial.emission.contents = NSColor.white
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.bladeMaterial.emission.contents = self.live ? NSColor.cyan : NSColor.darkGray
        }
    }
}

struct SaberView: NSViewRepresentable {
    let controller: SaberScene
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.allowsCameraControl = false
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {}
}

import SwiftUI
