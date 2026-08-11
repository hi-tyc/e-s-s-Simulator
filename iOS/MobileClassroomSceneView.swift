import SceneKit
import SwiftUI

struct MobileClassroomSceneView: UIViewRepresentable {
    @ObservedObject var game: MobileGameManager

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = UIColor(red: 0.025, green: 0.028, blue: 0.035, alpha: 1)
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        view.antialiasingMode = lowPower ? .none : .multisampling2X
        view.preferredFramesPerSecond = lowPower ? 30 : 60
        view.rendersContinuously = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.recenter(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(direction: game.direction, action: game.lastAction)
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        private let cameraPivot = SCNNode()
        private var yaw: Float = 0
        private var pitch: Float = -0.05
        private var targetYaw: Float = 0
        private var targetPitch: Float = -0.05
        private var previousTranslation = CGPoint.zero
        private var lastAction: MobileAction?
        private var baseFOV: CGFloat = 78

        override init() {
            super.init()
            buildScene()
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            if gesture.state == .began { previousTranslation = translation }
            let dx = translation.x - previousTranslation.x
            let dy = translation.y - previousTranslation.y
            previousTranslation = translation
            yaw = (yaw - Float(dx) * 0.005).clamped(to: -2.8...2.8)
            pitch = (pitch - Float(dy) * 0.004).clamped(to: -0.75...0.45)
            applyCamera(animated: false)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = camera.camera else { return }
            if gesture.state == .began { baseFOV = camera.fieldOfView }
            camera.fieldOfView = (baseFOV / gesture.scale).clamped(to: 58...92)
        }

        @objc func recenter(_ gesture: UITapGestureRecognizer) {
            yaw = 0
            pitch = -0.05
            applyCamera(animated: true)
        }

        func update(direction: MobileLookDirection, action: MobileAction?) {
            switch direction {
            case .left: targetYaw = 0.9; targetPitch = -0.04
            case .front: targetYaw = 0; targetPitch = -0.04
            case .right: targetYaw = -0.9; targetPitch = -0.04
            case .desk: targetYaw = 0; targetPitch = -0.62
            case .rear: targetYaw = 2.75; targetPitch = -0.02
            }
            yaw = targetYaw
            pitch = targetPitch
            applyCamera(animated: true)

            guard action != lastAction else { return }
            lastAction = action
            if action == .breathe {
                camera.runAction(.sequence([
                    .moveBy(x: 0, y: 0.035, z: 0, duration: 1.2),
                    .moveBy(x: 0, y: -0.035, z: 0, duration: 1.5)
                ]))
            }
        }

        private func applyCamera(animated: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.32 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraPivot.eulerAngles = SCNVector3(pitch, yaw, 0)
            SCNTransaction.commit()
        }

        private func buildScene() {
            scene.fogColor = UIColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
            scene.fogStartDistance = 9
            scene.fogEndDistance = 22

            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = baseFOV
            camera.camera?.wantsHDR = true
            camera.camera?.bloomIntensity = 0.22
            camera.position = SCNVector3(0, 0, 0)
            cameraPivot.position = SCNVector3(0, 1.55, 2.2)
            cameraPivot.addChildNode(camera)
            scene.rootNode.addChildNode(cameraPivot)

            scene.rootNode.addChildNode(makeRoom())
            scene.rootNode.addChildNode(makeFurniture())
            scene.rootNode.addChildNode(makePeople())
            scene.rootNode.addChildNode(makeLighting())
        }

        private func makeRoom() -> SCNNode {
            let room = SCNNode()
            room.addChildNode(box(width: 12, height: 0.12, length: 15, color: UIColor(white: 0.12, alpha: 1), at: .init(0, -0.06, 0)))
            room.addChildNode(box(width: 12, height: 4, length: 0.12, color: UIColor(red: 0.18, green: 0.2, blue: 0.21, alpha: 1), at: .init(0, 2, -6.5)))
            room.addChildNode(box(width: 0.12, height: 4, length: 13, color: UIColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1), at: .init(-6, 2, 0)))
            room.addChildNode(box(width: 0.12, height: 4, length: 13, color: UIColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1), at: .init(6, 2, 0)))

            let board = box(width: 6.4, height: 1.75, length: 0.08, color: UIColor(red: 0.035, green: 0.15, blue: 0.12, alpha: 1), at: .init(0, 2.05, -6.4))
            room.addChildNode(board)
            for x in stride(from: -4.8 as Float, through: 4.8, by: 2.4) {
                let window = box(width: 1.75, height: 1.5, length: 0.05, color: UIColor(red: 0.055, green: 0.1, blue: 0.18, alpha: 1), at: .init(x, 2.05, -6.32))
                window.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.02, green: 0.06, blue: 0.14, alpha: 1)
                window.geometry?.firstMaterial?.emission.intensity = 0.55
                room.addChildNode(window)
            }
            return room
        }

        private func makeFurniture() -> SCNNode {
            let furniture = SCNNode()
            for row in 0..<5 {
                for column in 0..<4 {
                    let x = Float(column) * 2.55 - 3.82
                    let z = Float(row) * 2.05 - 3.7
                    let desk = SCNNode()
                    desk.position = SCNVector3(x, 0, z)
                    desk.addChildNode(box(width: 1.55, height: 0.1, length: 0.78, color: UIColor(red: 0.32, green: 0.24, blue: 0.16, alpha: 1), at: .init(0, 0.78, 0)))
                    for legX: Float in [-0.64, 0.64] {
                        desk.addChildNode(box(width: 0.06, height: 0.76, length: 0.06, color: .darkGray, at: .init(legX, 0.38, 0)))
                    }
                    furniture.addChildNode(desk)
                }
            }
            let teacherDesk = box(width: 2.7, height: 0.85, length: 0.9, color: UIColor(red: 0.28, green: 0.2, blue: 0.13, alpha: 1), at: .init(0, 0.43, -5.1))
            furniture.addChildNode(teacherDesk)
            return furniture
        }

        private func makePeople() -> SCNNode {
            let people = SCNNode()
            for row in 0..<5 {
                for column in 0..<4 where !(row == 2 && column == 1) {
                    let person = SCNNode()
                    person.position = SCNVector3(Float(column) * 2.55 - 3.82, 0, Float(row) * 2.05 - 3.48)
                    let body = SCNCapsule(capRadius: 0.28, height: 0.92)
                    body.firstMaterial?.diffuse.contents = UIColor(red: 0.18, green: 0.27, blue: 0.38, alpha: 1)
                    let bodyNode = SCNNode(geometry: body)
                    bodyNode.position.y = 1.28
                    person.addChildNode(bodyNode)
                    let head = SCNSphere(radius: 0.23)
                    head.firstMaterial?.diffuse.contents = UIColor(red: 0.72, green: 0.58, blue: 0.48, alpha: 1)
                    let headNode = SCNNode(geometry: head)
                    headNode.position.y = 1.93
                    person.addChildNode(headNode)
                    people.addChildNode(person)
                }
            }
            return people
        }

        private func makeLighting() -> SCNNode {
            let lights = SCNNode()
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = UIColor(red: 0.25, green: 0.28, blue: 0.36, alpha: 1)
            ambient.intensity = 330
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            lights.addChildNode(ambientNode)

            for x: Float in [-3.2, 0, 3.2] {
                let light = SCNLight()
                light.type = .omni
                light.color = UIColor(red: 1, green: 0.91, blue: 0.72, alpha: 1)
                light.intensity = 460
                light.attenuationEndDistance = 7
                let node = SCNNode()
                node.light = light
                node.position = SCNVector3(x, 3.45, -1.4)
                lights.addChildNode(node)
            }
            return lights
        }

        private func box(width: CGFloat, height: CGFloat, length: CGFloat, color: UIColor, at position: SCNVector3) -> SCNNode {
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.025)
            geometry.firstMaterial?.diffuse.contents = color
            geometry.firstMaterial?.roughness.contents = 0.78
            let node = SCNNode(geometry: geometry)
            node.position = position
            return node
        }
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
