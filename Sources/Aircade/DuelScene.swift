import AppKit
import SceneKit
import MotionCore
import simd

final class DuelScene {
    let court = SaberScene()
    private let second: SCNNode
    private var targets: [SCNNode] = []
    init() {
        court.setArcadeVisible(true)
        court.setLive(true)
        second = court.pivot.clone()
        // Clones share geometry/materials by default; keep player colors independent.
        second.enumerateChildNodes { node, _ in
            node.geometry = node.geometry?.copy() as? SCNGeometry
            node.geometry?.materials = node.geometry?.materials.map { $0.copy() as! SCNMaterial } ?? []
            if node.geometry is SCNCapsule {
                node.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
                node.geometry?.firstMaterial?.emission.contents = NSColor.systemOrange
            }
        }
        court.scene.rootNode.addChildNode(second)
        for player in PlayerSlot.allCases {
            let target = SCNNode(geometry: SCNBox(width: 0.6, height: 0.86, length: 0.5, chamferRadius: 0.13))
            target.geometry?.firstMaterial?.diffuse.contents = player == .one ? NSColor.systemBlue : NSColor.systemOrange
            target.simdPosition = SaberDuel.target(player)
            court.scene.rootNode.addChildNode(target); targets.append(target)
            let text = SCNText(string: "P\(player.rawValue + 1)", extrusionDepth: 0.001)
            text.font = .boldSystemFont(ofSize: 0.18); text.firstMaterial?.diffuse.contents = NSColor.white
            let label = SCNNode(geometry: text); label.position = SCNVector3(-0.14, -0.08, 0.27)
            target.addChildNode(label)
        }
        update(.one, pose: SaberDuel.pose(.one, simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))), ready: false)
        update(.two, pose: SaberDuel.pose(.two, simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))), ready: false)
    }
    func update(_ player: PlayerSlot, pose: SaberPose?, ready: Bool) {
        let node = player == .one ? court.pivot : second
        node.opacity = ready ? 1 : 0.3
        if let pose { node.simdPosition = pose.position; node.simdOrientation = pose.orientation }
    }
    func setHealth(_ health: [Int]) {
        for i in 0..<2 { targets[i].opacity = health[i] > 0 ? 1 : 0.2 }
    }
    func impact(_ event: SaberDuel.Event) {
        court.impact(at: event.point, kind: event.kind == .clash ? .parry : .damage, velocity: .zero)
        if event.kind == .hit {
            let target = targets[event.player.other.rawValue]
            target.runAction(.sequence([.scale(to: 0.82, duration: 0.08), .scale(to: 1, duration: 0.18)]))
        }
    }
}
