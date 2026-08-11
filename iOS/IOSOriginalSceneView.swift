import SceneKit
import SwiftUI

struct IOSOriginalSceneView: UIViewRepresentable {
    @ObservedObject var game: GameManager

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = UIColor(red: 0.025, green: 0.03, blue: 0.04, alpha: 1)
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.antialiasingMode = ProcessInfo.processInfo.isLowPowerModeEnabled ? .none : .multisampling2X
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.recenter(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(game)
    }

    @MainActor final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        private let rig = SCNNode()
        private var previous = CGPoint.zero

        override init() {
            super.init()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 78
            rig.position = SCNVector3(-0.6, 1.25, 1.5)
            rig.addChildNode(camera)
            scene.rootNode.addChildNode(rig)
            buildScene()
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.translation(in: gesture.view)
            if gesture.state == .began { previous = point }
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            previous = point
            Task { @MainActor [weak self] in
                self?.gameRotate(dx: Double(dx), dy: Double(dy))
            }
        }

        @objc func recenter(_ gesture: UITapGestureRecognizer) {
            currentGame?.recenterStudentView()
        }

        private weak var currentGame: GameManager?

        func update(_ game: GameManager) {
            currentGame = game
            if game.viewMode == .teacher {
                rig.position = SCNVector3(0, 1.55, -4.2)
                rig.eulerAngles = SCNVector3(0, 0, 0)
            } else {
                rig.position = SCNVector3(-0.6, game.player.posture == .standing ? 1.58 : 1.25, 1.5)
                rig.eulerAngles = game.cameraPose.angles
                rig.eulerAngles.y += Float(game.studentLookYaw)
                rig.eulerAngles.x += Float(game.studentLookPitch)
            }
            camera.camera?.vignettingIntensity = CGFloat(0.35 + game.player.stress / 180)
            camera.camera?.fStop = 2.4 + game.player.focusQuality * 4
        }

        private func gameRotate(dx: Double, dy: Double) {
            currentGame?.rotateStudentView(deltaX: dx * 0.007, deltaY: dy * 0.005)
        }

        private func buildScene() {
            let floor = box(12, 0.12, 15, UIColor(white: 0.12, alpha: 1), SCNVector3(0, -0.06, 0))
            scene.rootNode.addChildNode(floor)
            scene.rootNode.addChildNode(box(12, 4, 0.12, UIColor(red: 0.18, green: 0.2, blue: 0.22, alpha: 1), SCNVector3(0, 2, -6.5)))
            scene.rootNode.addChildNode(box(0.12, 4, 13, UIColor(white: 0.12, alpha: 1), SCNVector3(-6, 2, 0)))
            scene.rootNode.addChildNode(box(0.12, 4, 13, UIColor(white: 0.12, alpha: 1), SCNVector3(6, 2, 0)))
            scene.rootNode.addChildNode(box(6.4, 1.7, 0.08, UIColor(red: 0.03, green: 0.14, blue: 0.11, alpha: 1), SCNVector3(0, 2.05, -6.42)))
            for row in 0..<5 {
                for column in 0..<4 {
                    let x = Float(column) * 2.55 - 3.82
                    let z = Float(row) * 2.05 - 3.7
                    scene.rootNode.addChildNode(box(1.55, 0.1, 0.78, UIColor(red: 0.3, green: 0.22, blue: 0.14, alpha: 1), SCNVector3(x, 0.78, z)))
                }
            }
            let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = 420; ambient.color = UIColor(red: 0.25, green: 0.28, blue: 0.36, alpha: 1)
            let ambientNode = SCNNode(); ambientNode.light = ambient; scene.rootNode.addChildNode(ambientNode)
            for x: Float in [-3.2, 0, 3.2] {
                let light = SCNLight(); light.type = .omni; light.intensity = 520; light.attenuationEndDistance = 7; light.color = UIColor(red: 1, green: 0.9, blue: 0.72, alpha: 1)
                let node = SCNNode(); node.light = light; node.position = SCNVector3(x, 3.4, -1.5); scene.rootNode.addChildNode(node)
            }
        }

        private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, _ color: UIColor, _ position: SCNVector3) -> SCNNode {
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.02)
            geometry.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: geometry); node.position = position; return node
        }
    }
}
