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
    private let tennisOpponent = SCNNode()
    private let opponentSwingArm = SCNNode()
    private let opponentBody = SCNNode()
    private var trackedOpponentFlight: Double?
    private var trackedBounceFlight: Double?
    private let arcadeEnvironment = SCNNode()
    private var rushNodes: [Int: SCNNode] = [:]
    private var activeSport: AircadeSport = .neonRush
    private var basePivotPosition = SIMD3<Float>.zero
    private var tennisPlayerX: Float = 0
    private static let tennisOpponentZ: Float = -18
    private static let tennisNetZ: Float = -9
    private static let tennisCourtHalfWidth: Float = 7.25
    enum ImpactKind { case cut, glance, parry, damage }

    init() {
        scene.background.contents = Self.skyTexture()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 55
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
        let ball = SCNSphere(radius: 0.15)
        ball.segmentCount = 24
        ball.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.78, green: 0.9, blue: 0.12, alpha: 1)
        ball.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.01, alpha: 1)
        tennisBall.geometry = ball
        tennisRoot.addChildNode(tennisBall)
        buildTennisOpponent()
        tennisRoot.addChildNode(tennisOpponent)
        buildArcadeEnvironment()
        setSport(.neonRush)
        setLive(false)
    }

    func setOrientation(_ q: simd_quatf) { pivot.simdOrientation = q }
    func setPose(_ pose: SaberPose, trail: Bool) {
        basePivotPosition = pose.position
        let courtOffset = SIMD3<Float>(activeSport == .tennis ? tennisPlayerX : 0, 0, 0)
        pivot.simdPosition = pose.position + courtOffset
        pivot.simdOrientation = pose.orientation
        let effectivePose = SaberPose(position: pose.position + courtOffset, orientation: pose.orientation)
        let tip = effectivePose.point(CombatGeometry.bladeLength)
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
        let frame = SCNTorus(ringRadius: 0.53, pipeRadius: 0.055)
        frame.ringSegmentCount = 48
        frame.pipeSegmentCount = 12
        frame.materials = [racketMaterial]
        let frameNode = SCNNode(geometry: frame)
        frameNode.position.y = 1.17
        frameNode.eulerAngles.x = .pi / 2
        frameNode.scale = SCNVector3(0.76, 1, 1.13)
        tennisEquipment.addChildNode(frameNode)
        for offset in stride(from: -0.36 as Float, through: 0.36, by: 0.12) {
            tennisEquipment.addChildNode(lineNode(from: SIMD3<Float>(offset, 0.66, 0), to: SIMD3<Float>(offset, 1.68, 0), radius: 0.008, color: .white))
        }
        for offset in stride(from: 0.78 as Float, through: 1.56, by: 0.13) {
            let width = 0.46 * sqrt(max(0.05, 1 - pow((offset - 1.17) / 0.58, 2)))
            tennisEquipment.addChildNode(lineNode(from: SIMD3<Float>(-width, offset, 0), to: SIMD3<Float>(width, offset, 0), radius: 0.008, color: .white))
        }
    }
    private func buildTennisOpponent() {
        func material(_ color: NSColor) -> SCNMaterial {
            let value = SCNMaterial()
            value.diffuse.contents = color
            value.roughness.contents = 0.72
            return value
        }
        func capsule(_ radius: CGFloat, _ height: CGFloat, _ color: NSColor) -> SCNNode {
            let geometry = SCNCapsule(capRadius: radius, height: height)
            geometry.firstMaterial = material(color)
            return SCNNode(geometry: geometry)
        }

        tennisOpponent.name = "tennis-opponent"
        tennisOpponent.position = SCNVector3(0, -1.64, Self.tennisOpponentZ)
        tennisOpponent.scale = SCNVector3(1.28, 1.28, 1.28)

        let shirt = NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.82, alpha: 1)
        let shorts = NSColor(calibratedWhite: 0.94, alpha: 1)
        let skin = NSColor(calibratedRed: 0.78, green: 0.58, blue: 0.43, alpha: 1)
        let hair = NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.07, alpha: 1)

        let torso = capsule(0.34, 1.05, shirt)
        torso.position = SCNVector3(0, 1.25, 0)
        torso.scale = SCNVector3(1, 1, 0.72)
        opponentBody.addChildNode(torso)

        let head = SCNNode(geometry: SCNSphere(radius: 0.43))
        head.geometry?.firstMaterial = material(skin)
        head.position = SCNVector3(0, 2.08, 0)
        head.scale = SCNVector3(0.88, 1.05, 0.9)
        opponentBody.addChildNode(head)

        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.435))
        hairCap.geometry?.firstMaterial = material(hair)
        hairCap.position = SCNVector3(0, 2.2, -0.015)
        hairCap.scale = SCNVector3(0.9, 0.62, 0.92)
        opponentBody.addChildNode(hairCap)

        for x: Float in [-0.14, 0.14] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.045))
            eye.geometry?.firstMaterial = material(.black)
            eye.position = SCNVector3(x, 2.11, 0.37)
            opponentBody.addChildNode(eye)
        }
        let smile = SCNNode(geometry: SCNTorus(ringRadius: 0.10, pipeRadius: 0.018))
        smile.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.30, green: 0.08, blue: 0.06, alpha: 1))
        smile.position = SCNVector3(0, 1.94, 0.39)
        smile.scale = SCNVector3(1, 0.48, 1)
        opponentBody.addChildNode(smile)

        for x: Float in [-0.2, 0.2] {
            let leg = capsule(0.13, 0.72, shorts)
            leg.position = SCNVector3(x, 0.47, 0)
            opponentBody.addChildNode(leg)
            let shoe = capsule(0.13, 0.44, .white)
            shoe.position = SCNVector3(x, 0.12, 0.12)
            shoe.eulerAngles.x = .pi / 2
            opponentBody.addChildNode(shoe)
        }

        let freeArm = capsule(0.11, 0.78, skin)
        freeArm.position = SCNVector3(-0.47, 1.35, 0)
        freeArm.eulerAngles.z = -0.42
        opponentBody.addChildNode(freeArm)

        opponentSwingArm.position = SCNVector3(0.42, 1.57, 0)
        let arm = capsule(0.115, 0.86, skin)
        arm.position = SCNVector3(0, -0.37, 0)
        opponentSwingArm.addChildNode(arm)

        let racket = SCNNode()
        let handle = SCNCylinder(radius: 0.055, height: 0.55)
        handle.firstMaterial = material(NSColor(calibratedWhite: 0.18, alpha: 1))
        let handleNode = SCNNode(geometry: handle)
        handleNode.position = SCNVector3(0, -0.95, 0)
        racket.addChildNode(handleNode)
        let frame = SCNTorus(ringRadius: 0.34, pipeRadius: 0.04)
        frame.firstMaterial = material(NSColor(calibratedRed: 0.91, green: 0.76, blue: 0.12, alpha: 1))
        let frameNode = SCNNode(geometry: frame)
        frameNode.position = SCNVector3(0, -1.47, 0)
        frameNode.eulerAngles.x = .pi / 2
        frameNode.scale = SCNVector3(0.76, 1, 1.08)
        racket.addChildNode(frameNode)
        for offset in stride(from: -0.22 as Float, through: 0.22, by: 0.11) {
            racket.addChildNode(lineNode(from: SIMD3<Float>(offset, -1.78, 0), to: SIMD3<Float>(offset, -1.16, 0), radius: 0.006, color: .white))
        }
        opponentSwingArm.addChildNode(racket)
        opponentSwingArm.eulerAngles = SCNVector3(0.18, 0, -2.0)
        opponentBody.addChildNode(opponentSwingArm)
        tennisOpponent.addChildNode(opponentBody)
    }
    func setSport(_ sport: AircadeSport) {
        activeSport = sport
        pivot.simdPosition = basePivotPosition + SIMD3<Float>(sport == .tennis ? tennisPlayerX : 0, 0, 0)
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
        let courtHalfWidth = Self.tennisCourtHalfWidth
        let courtWidth = CGFloat(courtHalfWidth * 2)
        for i in 0..<11 {
            let surface = SCNBox(width: courtWidth, height: 0.012, length: 4, chamferRadius: 0)
            surface.firstMaterial?.diffuse.contents = turf
            surface.firstMaterial?.multiply.contents = NSColor(calibratedWhite: i % 2 == 0 ? 1 : 0.90, alpha: 1)
            let node = SCNNode(geometry: surface)
            node.position = SCNVector3(0, -1.63, -Float(i) * 4)
            arcadeEnvironment.addChildNode(node)
        }
        for x: Float in [-courtHalfWidth, courtHalfWidth] {
            box(0.045, 0.018, 42, SCNVector3(x, -1.6, -18), .white)
            box(0.12, 0.6, 43, SCNVector3(x * 1.18, -1.35, -18), NSColor(calibratedRed: 0.13, green: 0.38, blue: 0.29, alpha: 1))
        }
        // Inner singles lines emphasize the extra doubles-court width.
        for x: Float in [-5.45, 5.45] {
            box(0.035, 0.016, 21, SCNVector3(x, -1.59, -9), NSColor.white.withAlphaComponent(0.88))
        }
        for z: Float in [1.5, -4.5, -13.5, -19.5, -39] { box(courtWidth, 0.018, 0.045, SCNVector3(0, -1.6, z), .white) }
        box(0.035, 0.016, 9, SCNVector3(0, -1.59, -9), NSColor.white.withAlphaComponent(0.88))
        // Centre net shared by the tennis game and stadium backdrop.
        box(0.09, 1.65, 0.09, SCNVector3(-courtHalfWidth - 0.15, -0.82, Self.tennisNetZ), .white)
        box(0.09, 1.65, 0.09, SCNVector3(courtHalfWidth + 0.15, -0.82, Self.tennisNetZ), .white)
        box(courtWidth + 0.3, 0.055, 0.055, SCNVector3(0, -0.15, Self.tennisNetZ), .white)
        for x in stride(from: -courtHalfWidth, through: courtHalfWidth, by: 0.28) {
            box(0.012, 1.25, 0.012, SCNVector3(x, -0.78, Self.tennisNetZ), NSColor.white.withAlphaComponent(0.7))
        }
        for y in stride(from: -1.38 as Float, through: -0.26, by: 0.18) {
            box(courtWidth + 0.05, 0.012, 0.012, SCNVector3(0, y, Self.tennisNetZ), NSColor.white.withAlphaComponent(0.7))
        }
        for side: Float in [-1, 1] {
            for row in 0..<3 {
                box(1.1, 0.3, 41, SCNVector3(side * (9.4 + Float(row) * 1.1), -1.35 + Float(row) * 0.38, -19), NSColor(calibratedRed: 0.69, green: 0.74, blue: 0.69, alpha: 1))
                for seat in 0..<31 {
                    let x = side * (9.4 + Float(row) * 1.1)
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
            for i in 0..<18 {
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
        box(22, 1.7, 0.35, SCNVector3(0, -0.8, -42), NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.33, alpha: 1))
        let sign = SCNText(string: "Aircade Sports", extrusionDepth: 0.005)
        sign.font = .systemFont(ofSize: 0.65, weight: .medium)
        sign.firstMaterial?.diffuse.contents = NSColor.white
        let node = SCNNode(geometry: sign)
        let bounds = node.boundingBox
        node.position = SCNVector3(-(bounds.max.x + bounds.min.x) / 2, -0.85, -41.8)
        arcadeEnvironment.addChildNode(node)
    }
    func clearRush() {
        rushRoot.childNodes.forEach { $0.removeFromParentNode() }
        rushNodes = [:]
        effects.childNodes.forEach { $0.removeFromParentNode() }
        lastTrail = nil
    }
    func clearTennis() {
        setTennisPlayerX(0)
        tennisBall.isHidden = true
        tennisOpponent.removeAllActions()
        opponentBody.removeAllActions()
        opponentSwingArm.removeAllActions()
        tennisOpponent.position = SCNVector3(0, -1.64, Self.tennisOpponentZ)
        opponentSwingArm.eulerAngles = SCNVector3(0.18, 0, -2.0)
        trackedOpponentFlight = nil
        trackedBounceFlight = nil
        effects.childNodes.forEach { $0.removeFromParentNode() }
        lastTrail = nil
    }
    func setTennisPlayerX(_ x: Float) {
        tennisPlayerX = x
        if activeSport == .tennis {
            pivot.simdPosition = basePivotPosition + SIMD3<Float>(x, 0, 0)
        }
    }
    func syncTennis(ball: TennisBallFlight?, elapsed: Double) {
        guard let ball else { tennisBall.isHidden = true; return }
        tennisBall.isHidden = false
        tennisBall.simdPosition = ball.position(at: elapsed)
        if let bounce = ball.bounce, let bounceTime = ball.bounceTime,
           elapsed >= bounceTime, trackedBounceFlight != ball.born {
            trackedBounceFlight = ball.born
            showTennisBounce(at: bounce)
        }
        if ball.direction == .towardOpponent, trackedOpponentFlight != ball.born {
            trackedOpponentFlight = ball.born
            let movementTime = max(0.12, ball.duration * 0.72)
            let contactX = ball.defenderContactX ?? ball.to.x
            let anticipatedStroke: TennisStroke = ball.to.x >= contactX ? .forehand : .backhand
            let bodyX = opponentBodyX(contactX: contactX, stroke: anticipatedStroke)
            tennisOpponent.removeAction(forKey: "track-ball")
            tennisOpponent.runAction(.move(to: SCNVector3(bodyX, -1.64, Self.tennisOpponentZ), duration: movementTime), forKey: "track-ball")
            let lean: CGFloat = CGFloat(ball.to.x) < tennisOpponent.position.x ? 0.10 : -0.10
            opponentBody.runAction(.sequence([.rotateTo(x: 0, y: 0, z: lean, duration: 0.12),
                                               .rotateTo(x: 0, y: 0, z: 0, duration: movementTime)]))
        }
    }
    func prepareTennisOpponent(contactX: Float, stroke: TennisStroke, delay: Double) {
        tennisOpponent.removeAction(forKey: "track-ball")
        tennisOpponent.runAction(.move(to: SCNVector3(opponentBodyX(contactX: contactX, stroke: stroke), -1.64, Self.tennisOpponentZ), duration: min(0.16, delay)), forKey: "prepare")
        opponentSwingArm.removeAllActions()
        let readyZ: CGFloat = stroke == .forehand ? -2.42 : 2.15
        let readyY: CGFloat = stroke == .forehand ? -0.3 : 0.35
        opponentSwingArm.runAction(.rotateTo(x: 0.12, y: readyY, z: readyZ, duration: max(0.12, delay * 0.72)))
    }
    func tennisOpponentHit(contactX: Float, stroke: TennisStroke) {
        tennisOpponent.position.x = CGFloat(opponentBodyX(contactX: contactX, stroke: stroke))
        opponentSwingArm.removeAllActions()
        let contactZ: CGFloat = stroke == .forehand ? -1.65 : 1.65
        let followZ: CGFloat = stroke == .forehand ? -0.35 : 0.35
        let followY: CGFloat = stroke == .forehand ? 0.5 : -0.5
        opponentSwingArm.eulerAngles = SCNVector3(-0.08, followY, contactZ)
        opponentSwingArm.runAction(.sequence([
            .rotateTo(x: -0.08, y: followY, z: followZ, duration: 0.14),
            .wait(duration: 0.08),
            .rotateTo(x: 0.18, y: 0, z: -2.0, duration: 0.24)
        ]), forKey: "swing")
        tennisImpact(at: SIMD3<Float>(contactX, 0.05, Self.tennisOpponentZ), velocity: .zero)
    }
    func tennisOpponentMiss(ballX: Float, attemptedX: Float) {
        let stroke: TennisStroke = ballX >= attemptedX ? .forehand : .backhand
        tennisOpponent.position.x = CGFloat(opponentBodyX(contactX: attemptedX, stroke: stroke))
        opponentSwingArm.removeAllActions()
        let direction: CGFloat = stroke == .forehand ? -1 : 1
        opponentSwingArm.runAction(.sequence([
            .rotateTo(x: -0.15, y: direction * 0.7, z: direction * 0.55, duration: 0.12),
            .rotateTo(x: 0.18, y: 0, z: -2.0, duration: 0.28)
        ]), forKey: "miss-swing")
        let miss = SCNNode(geometry: SCNTorus(ringRadius: 0.22, pipeRadius: 0.035))
        miss.geometry?.firstMaterial?.emission.contents = NSColor.systemOrange
        miss.eulerAngles.x = .pi / 2
        miss.simdPosition = SIMD3<Float>(ballX, 0.05, Self.tennisOpponentZ)
        effects.addChildNode(miss)
        miss.runAction(.sequence([.group([.scale(to: 2.5, duration: 0.32), .fadeOut(duration: 0.32)]), .removeFromParentNode()]))
    }
    private func showTennisBounce(at point: SIMD3<Float>) {
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.15, pipeRadius: 0.018))
        ring.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.78, green: 0.9, blue: 0.12, alpha: 1)
        ring.eulerAngles.x = .pi / 2
        ring.simdPosition = point + SIMD3<Float>(0, 0.015, 0)
        effects.addChildNode(ring)
        ring.runAction(.sequence([.group([.scale(to: 3.2, duration: 0.28), .fadeOut(duration: 0.28)]), .removeFromParentNode()]))
    }
    private func opponentBodyX(contactX: Float, stroke: TennisStroke) -> Float {
        // At the contact pose the racket centre is offset from the character's
        // root. Moving the body by the inverse offset keeps racket and ball aligned.
        contactX + (stroke == .forehand ? 1.12 : -2.02)
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
