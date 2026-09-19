import AppKit
import SceneKit
import simd
import MotionCore

final class SaberScene {
    let scene = SCNScene()
    let pivot = SCNNode()
    private let bladeMaterial = SCNMaterial()
    private let racketMaterial = SCNMaterial()
    private let saberEquipment = SCNNode()
    private let tennisEquipment = SCNNode()
    private var live = true
    private let targetNode = SCNNode()
    private let effects = SCNNode()
    private let attackNode = SCNNode()
    private let ghostNode = SCNNode()
    private let directionNode = SCNNode()
    private var attackTarget = SIMD3<Float>.zero
    private var lastTrail: SIMD3<Float>?
    private let rushRoot = SCNNode()
    private let tennisRoot = SCNNode()
    private let tennisBall = SCNNode()
    private let arcadeEnvironment = SCNNode()
    private var rushNodes: [Int: SCNNode] = [:]
    private var activeSport: AircadeSport = .neonRush
    enum ImpactKind { case cut, glance, parry, damage }

    init() {
        scene.background.contents = Self.skyTexture()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48
        camera.camera?.wantsHDR = false
        camera.camera?.bloomIntensity = 0.12
        camera.camera?.bloomThreshold = 0.6
        camera.position = SCNVector3(0, 1.3, 6.3)
        camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        ambient.light?.color = NSColor(calibratedWhite: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 850
        key.eulerAngles = SCNVector3(-0.8, -0.5, 0)
        scene.rootNode.addChildNode(key)

        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = Self.turfTexture()
        floor.firstMaterial?.diffuse.wrapS = .repeat
        floor.firstMaterial?.diffuse.wrapT = .repeat
        floor.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(14, 14, 1)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -1.65
        scene.rootNode.addChildNode(floorNode)
        scene.rootNode.addChildNode(pivot)
        let handle = SCNCylinder(radius: 0.11, height: 0.62)
        handle.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.92, alpha: 1)
        handle.firstMaterial?.metalness.contents = 0.1
        handle.firstMaterial?.roughness.contents = 0.3
        let handleNode = SCNNode(geometry: handle)
        handleNode.position.y = -0.3
        saberEquipment.addChildNode(handleNode)
        for i in 0..<6 {
            let ring = SCNTorus(ringRadius: 0.11, pipeRadius: 0.014)
            ring.firstMaterial?.diffuse.contents = NSColor.darkGray
            let node = SCNNode(geometry: ring)
            node.position.y = -0.52 + CGFloat(i) * 0.085
            saberEquipment.addChildNode(node)
        }
        // Off-centre switch makes roll visible even though the blade is cylindrical.
        let button = SCNNode(geometry: SCNSphere(radius: 0.045))
        button.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        button.position = SCNVector3(0.1, -0.12, 0.035)
        saberEquipment.addChildNode(button)

        let blade = SCNCapsule(capRadius: 0.045, height: 2.35)
        bladeMaterial.diffuse.contents = NSColor.white
        bladeMaterial.emission.contents = NSColor.cyan
        blade.materials = [bladeMaterial]
        let bladeNode = SCNNode(geometry: blade)
        bladeNode.position.y = 1.175
        saberEquipment.addChildNode(bladeNode)
        pivot.addChildNode(saberEquipment)
        buildTennisRacket()
        pivot.addChildNode(tennisEquipment)
        scene.rootNode.addChildNode(targetNode)
        scene.rootNode.addChildNode(effects)
        scene.rootNode.addChildNode(attackNode)
        scene.rootNode.addChildNode(ghostNode)
        scene.rootNode.addChildNode(directionNode)
        scene.rootNode.addChildNode(rushRoot)
        scene.rootNode.addChildNode(tennisRoot)
        scene.rootNode.addChildNode(arcadeEnvironment)
        let ball = SCNSphere(radius: CGFloat(RacketDimensions.ballRadius))
        ball.segmentCount = 24
        ball.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.78, green: 0.9, blue: 0.12, alpha: 1)
        ball.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.01, alpha: 1)
        tennisBall.geometry = ball
        tennisRoot.addChildNode(tennisBall)
        buildArcadeEnvironment()
        setSport(.neonRush)
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
    private func buildTennisRacket() {
        let grip = SCNCylinder(radius: 0.105, height: 0.62)
        grip.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
        let gripNode = SCNNode(geometry: grip)
        gripNode.position.y = -0.3
        tennisEquipment.addChildNode(gripNode)
        for i in 0..<5 {
            let wrap = SCNTorus(ringRadius: 0.105, pipeRadius: 0.012)
            wrap.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.82, alpha: 1)
            let node = SCNNode(geometry: wrap)
            node.position.y = -0.5 + CGFloat(i) * 0.1
            tennisEquipment.addChildNode(node)
        }
        racketMaterial.diffuse.contents = NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.72, alpha: 1)
        racketMaterial.emission.contents = NSColor(calibratedRed: 0.01, green: 0.12, blue: 0.18, alpha: 1)
        let shaft = SCNCapsule(capRadius: 0.045, height: 0.85)
        shaft.materials = [racketMaterial]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = 0.35
        tennisEquipment.addChildNode(shaftNode)
        let frame = SCNTorus(ringRadius: CGFloat(RacketDimensions.frameRadius), pipeRadius: CGFloat(RacketDimensions.frameTubeRadius))
        frame.ringSegmentCount = 48
        frame.pipeSegmentCount = 12
        frame.materials = [racketMaterial]
        let frameNode = SCNNode(geometry: frame)
        frameNode.simdPosition = RacketDimensions.faceCenter
        frameNode.eulerAngles.x = .pi / 2
        frameNode.simdScale = RacketDimensions.frameScale
        tennisEquipment.addChildNode(frameNode)
        let half = SIMD2<Float>(RacketDimensions.faceHalfWidth, RacketDimensions.faceHalfHeight)
        let center = RacketDimensions.faceCenter
        for offset in stride(from: -half.x + 0.06, through: half.x - 0.05, by: 0.10) {
            let height = half.y * sqrt(max(0, 1 - pow(offset / half.x, 2)))
            tennisEquipment.addChildNode(lineNode(from: center + SIMD3<Float>(offset, -height, 0), to: center + SIMD3<Float>(offset, height, 0), radius: 0.008, color: .white))
        }
        for offset in stride(from: -half.y + 0.06, through: half.y - 0.05, by: 0.11) {
            let width = half.x * sqrt(max(0, 1 - pow(offset / half.y, 2)))
            tennisEquipment.addChildNode(lineNode(from: center + SIMD3<Float>(-width, offset, 0), to: center + SIMD3<Float>(width, offset, 0), radius: 0.008, color: .white))
        }
    }
    func setSport(_ sport: AircadeSport) {
        activeSport = sport
        saberEquipment.isHidden = sport != .neonRush
        tennisEquipment.isHidden = sport != .tennis
        rushRoot.isHidden = sport != .neonRush
        tennisRoot.isHidden = sport != .tennis
        targetNode.isHidden = true
        directionNode.isHidden = true
        hideAttack()
    }
    func setArcadeVisible(_ visible: Bool) {
        arcadeEnvironment.isHidden = !visible
        rushRoot.isHidden = !visible || activeSport != .neonRush
        tennisRoot.isHidden = !visible || activeSport != .tennis
        saberEquipment.isHidden = !visible || activeSport != .neonRush
        tennisEquipment.isHidden = !visible || activeSport != .tennis
        if visible {
            targetNode.isHidden = true
            directionNode.isHidden = true
            hideAttack()
        }
    }
    private static func turfTexture() -> NSImage {
        let size = 256
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        var seed: UInt32 = 91
        for y in 0..<size {
            for x in 0..<size {
                seed = seed &* 1664525 &+ 1013904223
                let noise = Int((seed >> 24) % 36)
                let index = (y * size + x) * 4
                bitmap.bitmapData![index] = UInt8(67 + noise)
                bitmap.bitmapData![index + 1] = UInt8(111 + noise)
                bitmap.bitmapData![index + 2] = UInt8(30 + noise / 2)
                bitmap.bitmapData![index + 3] = 255
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        return image
    }
    private static func skyTexture() -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 512))
        image.lockFocus()
        NSGradient(starting: NSColor(calibratedRed: 0.79, green: 0.9, blue: 0.94, alpha: 1),
                   ending: NSColor(calibratedRed: 0.30, green: 0.66, blue: 0.88, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: 1024, height: 512), angle: 90)
        // Soft, irregular cloud banks painted into the sky, rather than solid 3D ovals.
        for bank in 0..<5 {
            for puff in 0..<18 {
                let x = CGFloat(bank * 245 + puff * 13 - 65)
                let y = CGFloat(250 + (bank % 3) * 55 + Int(sin(Double(puff) * 0.8) * 12))
                NSColor.white.withAlphaComponent(0.045).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 95, height: CGFloat(16 + puff % 4 * 5))).fill()
            }
        }
        image.unlockFocus()
        return image
    }
    private func buildArcadeEnvironment() {
        // Scenery never participates in hit testing or game-state updates.
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ p: SCNVector3, _ color: NSColor) {
            let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
            geometry.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: geometry); node.position = p
            arcadeEnvironment.addChildNode(node)
        }
        let turf = Self.turfTexture()
        for i in 0..<8 {
            let surface = SCNBox(width: 8, height: 0.012, length: 4, chamferRadius: 0)
            surface.firstMaterial?.diffuse.contents = turf
            surface.firstMaterial?.multiply.contents = NSColor(calibratedWhite: i % 2 == 0 ? 1 : 0.90, alpha: 1)
            let node = SCNNode(geometry: surface)
            node.position = SCNVector3(0, -1.63, -Float(i) * 4)
            arcadeEnvironment.addChildNode(node)
        }
        for x: Float in [-4, 4] {
            box(0.045, 0.018, 30, SCNVector3(x, -1.6, -12), .white)
            box(0.12, 0.6, 31, SCNVector3(x * 1.22, -1.35, -12), NSColor(calibratedRed: 0.13, green: 0.38, blue: 0.29, alpha: 1))
        }
        for z: Float in [1.5, -12, -26] { box(8, 0.018, 0.045, SCNVector3(0, -1.6, z), .white) }
        // Centre net shared by the tennis game and stadium backdrop.
        box(0.09, 1.65, 0.09, SCNVector3(-4.15, -0.82, -5.4), .white)
        box(0.09, 1.65, 0.09, SCNVector3(4.15, -0.82, -5.4), .white)
        box(8.3, 0.055, 0.055, SCNVector3(0, -0.15, -5.4), .white)
        for x in stride(from: -4.0 as Float, through: 4.0, by: 0.28) {
            box(0.012, 1.25, 0.012, SCNVector3(x, -0.78, -5.4), NSColor.white.withAlphaComponent(0.7))
        }
        for y in stride(from: -1.38 as Float, through: -0.26, by: 0.18) {
            box(8.05, 0.012, 0.012, SCNVector3(0, y, -5.4), NSColor.white.withAlphaComponent(0.7))
        }
        for side: Float in [-1, 1] {
            for row in 0..<3 {
                box(1.1, 0.3, 29, SCNVector3(side * (6 + Float(row) * 1.1), -1.35 + Float(row) * 0.38, -13), NSColor(calibratedRed: 0.69, green: 0.74, blue: 0.69, alpha: 1))
                for seat in 0..<22 {
                    let x = side * (6 + Float(row) * 1.1)
                    let y = -1.05 + Float(row) * 0.38
                    let z = -Float(seat) * 1.25
                    let shirt = NSColor(calibratedHue: CGFloat((seat * 7 + row * 3) % 20) / 20, saturation: 0.48, brightness: 0.80, alpha: 1)
                    box(0.25, 0.35, 0.24, SCNVector3(x, y + 0.17, z), shirt)
                    let head = SCNNode(geometry: SCNSphere(radius: 0.12))
                    head.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.73, green: 0.52, blue: 0.35, alpha: 1)
                    head.position = SCNVector3(x, y + 0.45, z)
                    arcadeEnvironment.addChildNode(head)
                }
            }
            for i in 0..<15 {
                let z = -Float(i) * 3.7 + 1
                let x = side * (12 + Float(i % 3))
                let height = CGFloat(2.5 + Double(i % 4) * 0.4)
                let trunk = SCNNode(geometry: SCNCylinder(radius: 0.10, height: height))
                trunk.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.38, green: 0.29, blue: 0.18, alpha: 1)
                trunk.position = SCNVector3(x, Float(height / 2) - 1.65, z)
                arcadeEnvironment.addChildNode(trunk)
                for tier in 0..<3 {
                    let foliage = SCNCone(topRadius: 0.12, bottomRadius: CGFloat(1.15 - Double(tier) * 0.23), height: 1.8)
                    foliage.radialSegmentCount = 9
                    foliage.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.22 + Double(i % 3) * 0.025, green: 0.39 + Double(tier) * 0.06, blue: 0.13, alpha: 1)
                    let crown = SCNNode(geometry: foliage)
                    crown.position = SCNVector3(x + Float(tier % 2) * 0.14, Float(height) - 1.3 + Float(tier) * 0.65, z)
                    crown.eulerAngles.y = CGFloat(i + tier) * 0.7
                    arcadeEnvironment.addChildNode(crown)
                }
            }
        }
        box(22, 1.7, 0.35, SCNVector3(0, -0.8, -30), NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.33, alpha: 1))
        let sign = SCNText(string: "Aircade Sports", extrusionDepth: 0.005)
        sign.font = .systemFont(ofSize: 0.65, weight: .medium)
        sign.firstMaterial?.diffuse.contents = NSColor.white
        let node = SCNNode(geometry: sign)
        let bounds = node.boundingBox
        node.position = SCNVector3(-(bounds.max.x + bounds.min.x) / 2, -0.85, -29.8)
        arcadeEnvironment.addChildNode(node)
    }
    func clearRush() {
        rushRoot.childNodes.forEach { $0.removeFromParentNode() }
        rushNodes = [:]
        effects.childNodes.forEach { $0.removeFromParentNode() }
        lastTrail = nil
    }
    func clearTennis() {
        tennisBall.isHidden = true
        effects.childNodes.forEach { $0.removeFromParentNode() }
        lastTrail = nil
    }
    func syncTennis(ball: TennisBallFlight?, elapsed: Double) {
        guard let ball else { tennisBall.isHidden = true; return }
        tennisBall.isHidden = false
        tennisBall.simdPosition = ball.position(at: elapsed)
    }
    func tennisImpact(at point: SIMD3<Float>, velocity: SIMD3<Float>) {
        impact(at: point, kind: .parry, velocity: velocity)
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
        let color: NSColor = target.hazard ? .systemRed : target.direction == .any ? NSColor(calibratedRed: 0.22, green: 0.65, blue: 0.13, alpha: 1) : NSColor(calibratedRed: 0.02, green: 0.49, blue: 0.77, alpha: 1)
        let box = SCNBox(width: 0.62, height: 0.62, length: 0.62, chamferRadius: 0.015)
        box.firstMaterial?.diffuse.contents = color
        box.firstMaterial?.emission.contents = color.blended(withFraction: 0.88, of: .black)
        box.firstMaterial?.metalness.contents = 0.05
        parent.addChildNode(SCNNode(geometry: box))
        let frame = SCNBox(width: 0.58, height: 0.58, length: 0.018, chamferRadius: 0.012)
        frame.firstMaterial?.diffuse.contents = color
        frame.firstMaterial?.emission.contents = color
        let face = SCNNode(geometry: frame)
        face.position.z = 0.315
        parent.addChildNode(face)
        let inset = SCNNode(geometry: SCNBox(width: 0.52, height: 0.52, length: 0.018, chamferRadius: 0.008))
        inset.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.97, alpha: 1)
        inset.position.z = 0.33; parent.addChildNode(inset)
        let symbol = target.hazard ? "×" : target.direction == .left ? "←" : target.direction == .right ? "→" : target.direction == .down ? "↓" : "✦"
        let geometry = SCNText(string: symbol, extrusionDepth: 0.005)
        geometry.font = .systemFont(ofSize: 0.38, weight: .bold)
        geometry.flatness = 0.1
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.emission.contents = NSColor.black
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
        racketMaterial.emission.contents = value ? NSColor(calibratedRed: 0.04, green: 0.32, blue: 0.5, alpha: 1) : NSColor(calibratedWhite: 0.08, alpha: 1)
    }
    func flash() {
        guard live else { return }
        bladeMaterial.emission.contents = NSColor.white
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.bladeMaterial.emission.contents = self.live ? NSColor.cyan : NSColor.darkGray
            self.racketMaterial.emission.contents = self.live ? NSColor(calibratedRed: 0.04, green: 0.32, blue: 0.5, alpha: 1) : NSColor.darkGray
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
