import SceneKit
import SwiftUI

@MainActor
struct ClassroomSceneView: NSViewRepresentable {
    @ObservedObject var game: GameManager

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraRig
        view.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.05, alpha: 1)
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        context.coordinator.update(game: game)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(game: game)
    }

    func makeCoordinator() -> ClassroomCoordinator {
        ClassroomCoordinator()
    }
}

@MainActor
final class ClassroomCoordinator {
    let scene = SCNScene()
    let cameraRig = SCNNode()

    private let teacherNode = SCNNode()
    private let teacherGazeNode = SCNNode()
    private let teacherPressureLightNode = SCNNode()
    private let ambientNode = SCNNode()
    private let playerPhoneNode = SCNNode()
    private let blackboardStatusNode = SCNNode()
    private let clockHourHandNode = SCNNode()
    private let clockMinuteHandNode = SCNNode()
    private let homeworkProgressNode = SCNNode()
    private let leftHandNode = SCNNode()
    private let rightHandNode = SCNNode()
    private let drawerNode = SCNNode()
    private let drawerShadowNode = SCNNode()
    private let snackWrapperNode = SCNNode()
    private let bladderIndicatorNode = SCNNode()
    private let leftLegNode = SCNNode()
    private let rightLegNode = SCNNode()
    private let seatTensionNode = SCNNode()
    private let outsideSkyNode = SCNNode()
    private let outsideLampNode = SCNNode()
    private var fanNodes: [SCNNode] = []
    private var classmateNodes: [Int: SCNNode] = [:]
    private var classmateStates: [Int: ClassmateState] = [:]
    private var classmateProfileSignature = ""
    private var lastFanActive = false
    private var lastPose: CameraPose = .forward
    private var lastViewMode: ViewMode = .student

    init() {
        buildScene()
    }

    func update(game: GameManager) {
        let signature = profileSignature(for: game.classmates)
        if !game.classmates.isEmpty && signature != classmateProfileSignature {
            rebuildClassmates(with: game.classmates)
            classmateProfileSignature = signature
        }

        if lastPose != game.cameraPose || lastViewMode != game.viewMode {
            lastPose = game.cameraPose
            lastViewMode = game.viewMode
            SCNTransaction.begin()
            SCNTransaction.animationDuration = cameraTurnDuration(game: game)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyCameraMode(game: game, teacherPosition: teacherNode.position)
            SCNTransaction.commit()
        }

        let teacherPath: [SCNVector3] = [
            SCNVector3(-2.7, 0.05, -4.25), SCNVector3(2.6, 0.05, -3.2),
            SCNVector3(2.6, 0.05, -1.2), SCNVector3(1.2, 0.05, 0.45),
            SCNVector3(0.2, 0.05, 1.55), SCNVector3(-2.2, 0.05, 0.4),
            SCNVector3(-2.8, 0.05, -1.4), SCNVector3(0, 0.05, -4.35),
            SCNVector3(-3.45, 0.05, 4.25)
        ]
        let index = min(game.teacher.positionIndex, teacherPath.count - 1)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.55
        teacherNode.position = teacherPath[index]
        teacherNode.opacity = game.teacher.isNearPlayer ? 1.0 : 0.78
        updateTeacherAttention(game: game, teacherPosition: teacherPath[index])
        if game.viewMode == .teacher {
            applyCameraMode(game: game, teacherPosition: teacherPath[index])
        }
        ambientNode.light?.intensity = 120 + 110 * game.classroomLightLevel + (game.currentPeriod == .third ? -25 : 0)
        playerPhoneNode.opacity = game.audioCues.first?.kind == .phone ? 1.0 : 0.25
        updateClock(text: game.clockText)
        updateBlackboard(game: game)
        updateTimeAtmosphere(game: game)
        updateFans(game: game)
        updateDeskState(game: game)
        if let camera = cameraRig.camera {
            let fatigue = 1 - game.player.focusQuality
            let eventIntensity = eventVisualIntensity(game: game)
            camera.fStop = 1.6 + fatigue * 7.0 + eventIntensity.blur
            camera.focusDistance = game.cameraPose == .desk ? 0.55 : (game.cameraPose == .board ? 5.8 : 1.5)
            camera.vignettingIntensity = 0.45 + fatigue * 1.15 + eventIntensity.vignette
            camera.vignettingPower = 0.8 + fatigue * 1.5 + eventIntensity.vignette
            camera.saturation = CGFloat(1.0 - fatigue * 0.34 - eventIntensity.desaturation)
        }
        for classmate in game.classmates {
            guard let node = classmateNodes[classmate.id] else { continue }
            node.scale = classmate.state == .crying ? SCNVector3(0.9, 0.72, 0.9) : SCNVector3(1, 1, 1)
            node.opacity = classmate.state == .sleeping ? 0.72 : 1
            node.childNodes.first?.geometry?.firstMaterial?.emission.contents = emissionColor(for: classmate.state)
            if classmateStates[classmate.id] != classmate.state {
                classmateStates[classmate.id] = classmate.state
                applyStateAnimation(classmate.state, to: node)
            }
        }
        SCNTransaction.commit()
    }

    private func buildScene() {
        scene.rootNode.addChildNode(makeEnvironment())
        scene.rootNode.addChildNode(makeFurniture())
        scene.rootNode.addChildNode(makeLighting())
        scene.rootNode.addChildNode(makePlayerDeskProps())

        teacherNode.addChildNode(makeTeacherGeometry())
        teacherNode.position = SCNVector3(0, 0.05, -4.25)
        scene.rootNode.addChildNode(teacherNode)

        addClassmates(classmates: [])
        configureCamera()
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 100
        camera.zNear = 0.03
        camera.zFar = 80
        camera.wantsDepthOfField = true
        camera.focusDistance = 1.5
        camera.fStop = 1.8
        camera.vignettingPower = 0.8
        camera.vignettingIntensity = 0.55
        cameraRig.camera = camera
        cameraRig.position = SCNVector3(-0.6, 1.18, 1.5)
        scene.rootNode.addChildNode(cameraRig)
    }

    private func applyCameraMode(game: GameManager, teacherPosition: SCNVector3) {
        switch game.viewMode {
        case .student:
            let height: Float = game.player.posture == .standing ? 1.58 : 1.18
            let stressSway = Float(min(0.035, game.player.stress / 2_500))
            let attentionDip = Float(max(0, 35 - game.player.visualAttention) / 1_200)
            cameraRig.position = SCNVector3(-0.6 + stressSway, height - attentionDip, 1.5)
            cameraRig.eulerAngles = game.cameraPose.angles
            cameraRig.camera?.fieldOfView = 100
        case .teacher:
            cameraRig.position = SCNVector3(teacherPosition.x, 1.48, teacherPosition.z + 0.18)
            cameraRig.eulerAngles = teacherEulerAngles(from: cameraRig.position, to: SCNVector3(0, 0.8, 0.2))
            cameraRig.camera?.fieldOfView = 82
        }
    }

    private func cameraTurnDuration(game: GameManager) -> Double {
        guard game.viewMode == .student else { return 0.35 }
        let stressDelay = game.player.stress / 180
        let attentionDelay = max(0, 45 - game.player.visualAttention) / 90
        let teacherDelay = game.teacher.isNearPlayer ? 0.22 : 0
        return (0.28 + stressDelay + attentionDelay + teacherDelay).clamped(to: 0.28...1.15)
    }

    private func teacherEulerAngles(from: SCNVector3, to: SCNVector3) -> SCNVector3 {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        let yaw = atan2(dx, dz)
        let distance = sqrt(dx * dx + dz * dz)
        let pitch = -atan2(dy, distance)
        return SCNVector3(pitch, yaw, 0)
    }

    private func makeEnvironment() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 8, height: 0.04, length: 12, color: NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.28, alpha: 1), position: SCNVector3(0, -0.02, 0)))
        root.addChildNode(box(width: 8, height: 3.5, length: 0.06, color: wallColor, position: SCNVector3(0, 1.75, -6)))
        root.addChildNode(box(width: 8, height: 3.5, length: 0.06, color: wallColor, position: SCNVector3(0, 1.75, 6)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 12, color: wallColor, position: SCNVector3(-4, 1.75, 0)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 12, color: wallColor, position: SCNVector3(4, 1.75, 0)))
        root.addChildNode(box(width: 8, height: 0.04, length: 12, color: NSColor(calibratedWhite: 0.93, alpha: 1), position: SCNVector3(0, 3.52, 0)))
        root.addChildNode(makeDoors())

        root.addChildNode(box(width: 4.2, height: 1.2, length: 0.05, color: NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.09, alpha: 1), position: SCNVector3(0, 1.95, -5.94)))
        root.addChildNode(box(width: 1.9, height: 0.9, length: 0.05, color: NSColor(calibratedRed: 0.64, green: 0.48, blue: 0.31, alpha: 1), position: SCNVector3(0, 0.55, -4.7)))
        root.addChildNode(makeBlackboardDetails())
        root.addChildNode(makeWallClock())

        root.addChildNode(makeWindowLayer())

        return root
    }

    private func makeWindowLayer() -> SCNNode {
        let root = SCNNode()
        for x in [-3.96, 3.96] {
            for z in [-2.9, 1.2] {
                root.addChildNode(box(width: 0.04, height: 1.05, length: 1.4, color: NSColor(calibratedRed: 0.68, green: 0.86, blue: 1.0, alpha: 0.28), position: SCNVector3(Float(x), 1.7, Float(z))))
            }
        }

        outsideSkyNode.addChildNode(box(width: 0.03, height: 1.0, length: 5.4, color: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.13, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideSkyNode.position = SCNVector3(-4.04, 1.72, -0.85)
        root.addChildNode(outsideSkyNode)

        outsideLampNode.addChildNode(box(width: 0.022, height: 0.72, length: 0.08, color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideLampNode.addChildNode(box(width: 0.024, height: 0.18, length: 0.9, color: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.18, alpha: 1), position: SCNVector3(0, 0.28, 0)))
        outsideLampNode.position = SCNVector3(-4.075, 1.55, 1.2)
        outsideLampNode.opacity = 0.52
        root.addChildNode(outsideLampNode)
        return root
    }

    private func makeDoors() -> SCNNode {
        let root = SCNNode()
        let doorColor = NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.15, alpha: 1)
        let trimColor = NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.08, alpha: 1)

        root.addChildNode(box(width: 0.06, height: 2.0, length: 0.92, color: doorColor, position: SCNVector3(3.97, 1.0, -4.35)))
        root.addChildNode(box(width: 0.08, height: 2.12, length: 1.04, color: trimColor, position: SCNVector3(3.94, 1.06, -4.35)))
        root.addChildNode(sphere(radius: 0.035, color: NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(3.91, 1.02, -4.02)))

        root.addChildNode(box(width: 0.06, height: 2.0, length: 0.92, color: doorColor, position: SCNVector3(-3.97, 1.0, 4.25)))
        root.addChildNode(box(width: 0.08, height: 2.12, length: 1.04, color: trimColor, position: SCNVector3(-3.94, 1.06, 4.25)))
        root.addChildNode(sphere(radius: 0.035, color: NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(-3.91, 1.02, 3.92)))
        return root
    }

    private func makeFurniture() -> SCNNode {
        let root = SCNNode()
        for row in 0..<5 {
            for column in 0..<4 {
                let x = Float(column) * 1.2 - 2.4
                let z = Float(row) * 1.45 - 2.25
                root.addChildNode(makeDesk(at: SCNVector3(x, 0, z), isPlayer: row == 2 && column == 1))
                root.addChildNode(makeChair(at: SCNVector3(x, 0, z + 0.55)))
            }
        }
        return root
    }

    private func makeDesk(at position: SCNVector3, isPlayer: Bool) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let topColor = isPlayer ? NSColor(calibratedRed: 0.74, green: 0.62, blue: 0.46, alpha: 1) : NSColor(calibratedRed: 0.62, green: 0.48, blue: 0.34, alpha: 1)
        root.addChildNode(box(width: 0.82, height: 0.08, length: 0.55, color: topColor, position: SCNVector3(0, 0.72, 0)))
        for x in [-0.34, 0.34] {
            for z in [-0.2, 0.2] {
                root.addChildNode(box(width: 0.05, height: 0.68, length: 0.05, color: NSColor.darkGray, position: SCNVector3(Float(x), 0.36, Float(z))))
            }
        }
        return root
    }

    private func makeChair(at position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        root.addChildNode(box(width: 0.52, height: 0.06, length: 0.46, color: NSColor(calibratedRed: 0.28, green: 0.24, blue: 0.22, alpha: 1), position: SCNVector3(0, 0.45, 0)))
        root.addChildNode(box(width: 0.52, height: 0.5, length: 0.06, color: NSColor(calibratedRed: 0.25, green: 0.21, blue: 0.19, alpha: 1), position: SCNVector3(0, 0.75, 0.22)))
        return root
    }

    private func addClassmates(classmates: [Classmate]) {
        var id = 0
        for row in 0..<5 {
            for column in 0..<4 {
                if row == 2 && column == 1 { continue }
                let x = Float(column) * 1.2 - 2.4
                let z = Float(row) * 1.45 - 2.0
                let profile = classmates.first(where: { $0.id == id })?.profile
                let node = makeStudent(seed: id, profile: profile)
                node.position = SCNVector3(x, 0.5, z)
                node.eulerAngles.y = .pi
                classmateNodes[id] = node
                scene.rootNode.addChildNode(node)
                id += 1
            }
        }
    }

    private func rebuildClassmates(with classmates: [Classmate]) {
        classmateNodes.values.forEach { $0.removeFromParentNode() }
        classmateNodes.removeAll()
        classmateStates.removeAll()
        addClassmates(classmates: classmates)
    }

    private func profileSignature(for classmates: [Classmate]) -> String {
        classmates
            .map { mate in
                "\(mate.id):\(Int(mate.profile.cooperation))-\(Int(mate.profile.orderliness))-\(Int(mate.profile.rebelliousness))-\(Int(mate.profile.empathy))-\(Int(mate.profile.anxiety))-\(Int(mate.profile.maskStrength))"
            }
            .joined(separator: "|")
    }

    private func makeStudent(seed: Int, profile: ClassmateProfile?) -> SCNNode {
        let root = SCNNode()
        root.name = "student_\(seed)"
        let shirtColors = [
            NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.88, green: 0.9, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.32, green: 0.48, blue: 0.35, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.18, blue: 0.22, alpha: 1)
        ]
        let bodyRadius = CGFloat(0.12 + (profile?.maskStrength ?? 55) / 1_800)
        let bodyHeight = CGFloat(0.48 + (profile?.orderliness ?? 50) / 1_000)
        let body = capsule(radius: bodyRadius, height: bodyHeight, color: studentUniformColor(seed: seed, profile: profile, fallback: shirtColors[seed % shirtColors.count]), position: SCNVector3(0, 0.42, 0))
        body.name = "body"
        root.addChildNode(body)

        let head = sphere(radius: 0.14, color: skinColor(seed), position: SCNVector3(0, Float(0.78 + bodyHeight / 16), 0))
        head.name = "head"
        root.addChildNode(head)

        let hair = sphere(radius: 0.145, color: NSColor(calibratedWhite: 0.04 + CGFloat(seed % 3) * 0.04, alpha: 1), position: SCNVector3(0, 0.88, 0.02), scale: hairScale(seed: seed, profile: profile))
        hair.name = "hair"
        root.addChildNode(hair)

        if profile?.orderliness ?? 0 > 72 {
            root.addChildNode(makeGlasses())
        }

        if profile?.anxiety ?? 0 > 68 {
            root.addChildNode(box(width: 0.18, height: 0.01, length: 0.08, color: NSColor(calibratedRed: 0.94, green: 0.86, blue: 0.3, alpha: 1), position: SCNVector3(-0.24, 0.2, -0.16)))
        }

        let phone = box(width: 0.12, height: 0.012, length: 0.2, color: NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.55, alpha: 1), position: SCNVector3(0.18, 0.2, -0.18))
        phone.name = "phone"
        phone.opacity = (profile?.rebelliousness ?? 0) > 72 ? 0.28 : 0
        root.addChildNode(phone)

        let paper = box(width: 0.22, height: 0.006, length: 0.16, color: NSColor(calibratedWhite: 0.92, alpha: 1), position: SCNVector3(-0.12, 0.18, -0.2))
        paper.name = "paper"
        paper.opacity = (profile?.orderliness ?? 50) > 70 ? 0.82 : 0.55
        root.addChildNode(paper)

        if profile?.empathy ?? 0 > 72 {
            root.addChildNode(box(width: 0.08, height: 0.012, length: 0.12, color: NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1), position: SCNVector3(-0.22, 0.21, 0.02)))
        }

        root.scale = SCNVector3(1, Float(0.94 + (profile?.cooperation ?? 50) / 900), 1)
        return root
    }

    private func makeTeacherGeometry() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(capsule(radius: 0.15, height: 0.72, color: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.24, alpha: 1), position: SCNVector3(0, 0.85, 0)))
        root.addChildNode(sphere(radius: 0.15, color: NSColor(calibratedRed: 0.9, green: 0.78, blue: 0.66, alpha: 1), position: SCNVector3(0, 1.28, 0)))
        root.addChildNode(box(width: 0.38, height: 0.04, length: 0.04, color: NSColor.black, position: SCNVector3(0, 1.3, -0.13)))
        teacherGazeNode.addChildNode(gazeCone())
        teacherGazeNode.position = SCNVector3(0, 1.22, -0.32)
        teacherGazeNode.eulerAngles.x = -.pi / 2
        teacherGazeNode.opacity = 0.12
        root.addChildNode(teacherGazeNode)

        let pressureLight = SCNLight()
        pressureLight.type = .omni
        pressureLight.color = NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.24, alpha: 1)
        pressureLight.intensity = 0
        teacherPressureLightNode.light = pressureLight
        teacherPressureLightNode.position = SCNVector3(0, 1.2, -0.12)
        root.addChildNode(teacherPressureLightNode)
        return root
    }

    private func updateTeacherAttention(game: GameManager, teacherPosition: SCNVector3) {
        let pressure = game.teacher.institutionalPressure / 100
        let attention = max(pressure, game.teacher.isNearPlayer ? 0.88 : 0.22)
        let rearDoor = game.teacher.positionIndex == 8
        let color = rearDoor
            ? NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 1.0, green: 0.46, blue: 0.22, alpha: 1)

        teacherGazeNode.opacity = CGFloat(0.08 + attention * 0.32)
        teacherPressureLightNode.light?.intensity = 18 + 120 * attention
        teacherPressureLightNode.light?.color = color
        teacherGazeNode.childNodes.first?.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.18)
        teacherGazeNode.childNodes.first?.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.12)

        let playerPosition = SCNVector3(-0.6, game.player.posture == .standing ? 1.58 : 1.18, 1.5)
        teacherNode.eulerAngles = teacherEulerAngles(from: teacherPosition, to: playerPosition)
    }

    private func makePlayerDeskProps() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.52, height: 0.025, length: 0.42, color: NSColor(calibratedWhite: 0.92, alpha: 1), position: SCNVector3(-0.6, 0.78, 1.43)))
        root.addChildNode(box(width: 0.46, height: 0.006, length: 0.04, color: NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.78, alpha: 1), position: SCNVector3(-0.6, 0.804, 1.31)))
        root.addChildNode(box(width: 0.38, height: 0.006, length: 0.028, color: NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.78, alpha: 1), position: SCNVector3(-0.6, 0.805, 1.41)))
        root.addChildNode(box(width: 0.42, height: 0.006, length: 0.028, color: NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.78, alpha: 1), position: SCNVector3(-0.6, 0.806, 1.5)))
        homeworkProgressNode.addChildNode(box(width: 1, height: 0.01, length: 0.026, color: NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.95, alpha: 1), position: SCNVector3(0, 0, 0)))
        homeworkProgressNode.position = SCNVector3(-0.83, 0.815, 1.2)
        homeworkProgressNode.scale = SCNVector3(0.02, 1, 1)
        root.addChildNode(homeworkProgressNode)

        bladderIndicatorNode.addChildNode(box(width: 1, height: 0.012, length: 0.022, color: NSColor(calibratedRed: 0.1, green: 0.65, blue: 0.72, alpha: 1), position: SCNVector3(0, 0, 0)))
        bladderIndicatorNode.position = SCNVector3(-0.36, 0.814, 1.2)
        bladderIndicatorNode.scale = SCNVector3(0.02, 1, 1)
        bladderIndicatorNode.opacity = 0.24
        root.addChildNode(bladderIndicatorNode)

        leftHandNode.addChildNode(capsule(radius: 0.025, height: 0.3, color: skinTone, position: SCNVector3(0, 0, 0), rotation: SCNVector4(1, 0, 0, Float.pi / 2)))
        leftHandNode.position = SCNVector3(-0.86, 0.83, 1.62)
        leftHandNode.eulerAngles.y = -0.38
        root.addChildNode(leftHandNode)

        rightHandNode.addChildNode(capsule(radius: 0.025, height: 0.28, color: skinTone, position: SCNVector3(0, 0, 0), rotation: SCNVector4(1, 0, 0, Float.pi / 2)))
        rightHandNode.position = SCNVector3(-0.38, 0.83, 1.6)
        rightHandNode.eulerAngles.y = 0.36
        root.addChildNode(rightHandNode)

        playerPhoneNode.addChildNode(box(width: 0.13, height: 0.018, length: 0.28, color: NSColor(calibratedRed: 0.03, green: 0.035, blue: 0.045, alpha: 1), position: SCNVector3(0, 0, 0)))
        let phoneLight = SCNLight()
        phoneLight.type = .omni
        phoneLight.color = NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 1)
        phoneLight.intensity = 70
        playerPhoneNode.light = phoneLight
        playerPhoneNode.position = SCNVector3(-0.22, 0.79, 1.55)
        playerPhoneNode.opacity = 0.25
        root.addChildNode(playerPhoneNode)
        root.addChildNode(capsule(radius: 0.015, height: 0.42, color: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.5, alpha: 1), position: SCNVector3(-0.75, 0.82, 1.25), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))

        drawerShadowNode.addChildNode(box(width: 0.42, height: 0.012, length: 0.045, color: NSColor(calibratedWhite: 0.04, alpha: 1), position: SCNVector3(0, 0, 0)))
        drawerShadowNode.position = SCNVector3(-0.6, 0.735, 1.73)
        drawerShadowNode.opacity = 0.18
        root.addChildNode(drawerShadowNode)

        drawerNode.addChildNode(box(width: 0.44, height: 0.05, length: 0.18, color: NSColor(calibratedRed: 0.44, green: 0.32, blue: 0.22, alpha: 1), position: SCNVector3(0, 0, 0)))
        drawerNode.addChildNode(box(width: 0.1, height: 0.014, length: 0.014, color: NSColor(calibratedRed: 0.78, green: 0.58, blue: 0.28, alpha: 1), position: SCNVector3(0, 0.01, 0.095)))
        drawerNode.position = SCNVector3(-0.6, 0.71, 1.66)
        drawerNode.opacity = 0.55
        root.addChildNode(drawerNode)

        snackWrapperNode.addChildNode(box(width: 0.18, height: 0.012, length: 0.12, color: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.18, alpha: 1), position: SCNVector3(0, 0, 0)))
        snackWrapperNode.addChildNode(box(width: 0.16, height: 0.014, length: 0.035, color: NSColor(calibratedRed: 0.82, green: 0.18, blue: 0.16, alpha: 1), position: SCNVector3(0, 0.008, 0.02)))
        snackWrapperNode.position = SCNVector3(-0.02, 0.806, 1.34)
        snackWrapperNode.eulerAngles.y = 0.45
        snackWrapperNode.opacity = 0.32
        root.addChildNode(snackWrapperNode)

        leftLegNode.addChildNode(capsule(radius: 0.028, height: 0.48, color: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.3, alpha: 1), position: SCNVector3(0, 0, 0), rotation: SCNVector4(1, 0, 0, Float.pi / 2)))
        leftLegNode.position = SCNVector3(-0.78, 0.43, 1.72)
        leftLegNode.eulerAngles.y = -0.12
        root.addChildNode(leftLegNode)

        rightLegNode.addChildNode(capsule(radius: 0.028, height: 0.48, color: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.3, alpha: 1), position: SCNVector3(0, 0, 0), rotation: SCNVector4(1, 0, 0, Float.pi / 2)))
        rightLegNode.position = SCNVector3(-0.43, 0.43, 1.72)
        rightLegNode.eulerAngles.y = 0.12
        root.addChildNode(rightLegNode)

        seatTensionNode.addChildNode(box(width: 0.48, height: 0.012, length: 0.32, color: NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.2, alpha: 1), position: SCNVector3(0, 0, 0)))
        seatTensionNode.position = SCNVector3(-0.6, 0.455, 2.05)
        seatTensionNode.opacity = 0.08
        root.addChildNode(seatTensionNode)
        return root
    }

    private func makeBlackboardDetails() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(makeText("晚自习", size: 0.22, color: NSColor(calibratedWhite: 0.9, alpha: 1), position: SCNVector3(-1.75, 2.24, -5.9)))
        root.addChildNode(makeText("今日目标：完成作业  管理压力  允许求助", size: 0.075, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(-1.78, 1.98, -5.9)))
        root.addChildNode(makeText("抬头会暴露，低头会失去信息。", size: 0.068, color: NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.78, alpha: 1), position: SCNVector3(-1.78, 1.8, -5.9)))
        blackboardStatusNode.position = SCNVector3(-1.78, 1.62, -5.9)
        root.addChildNode(blackboardStatusNode)
        return root
    }

    private func makeWallClock() -> SCNNode {
        let root = SCNNode()
        let face = SCNCylinder(radius: 0.28, height: 0.035)
        face.radialSegmentCount = 32
        face.firstMaterial = material(NSColor(calibratedWhite: 0.92, alpha: 1))
        let faceNode = SCNNode(geometry: face)
        faceNode.position = SCNVector3(2.85, 2.62, -5.88)
        faceNode.eulerAngles.x = CGFloat.pi / 2
        root.addChildNode(faceNode)

        root.addChildNode(makeText("12", size: 0.052, color: .black, position: SCNVector3(2.81, 2.79, -5.83)))
        root.addChildNode(makeText("6", size: 0.052, color: .black, position: SCNVector3(2.84, 2.39, -5.83)))
        root.addChildNode(makeText("3", size: 0.052, color: .black, position: SCNVector3(3.03, 2.58, -5.83)))
        root.addChildNode(makeText("9", size: 0.052, color: .black, position: SCNVector3(2.63, 2.58, -5.83)))

        clockHourHandNode.position = SCNVector3(2.85, 2.62, -5.82)
        clockHourHandNode.addChildNode(box(width: 0.026, height: 0.13, length: 0.012, color: .black, position: SCNVector3(0, 0.065, 0)))
        root.addChildNode(clockHourHandNode)

        clockMinuteHandNode.position = SCNVector3(2.85, 2.62, -5.81)
        clockMinuteHandNode.addChildNode(box(width: 0.018, height: 0.2, length: 0.012, color: NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.22, alpha: 1), position: SCNVector3(0, 0.1, 0)))
        root.addChildNode(clockMinuteHandNode)
        root.addChildNode(sphere(radius: 0.025, color: NSColor(calibratedWhite: 0.08, alpha: 1), position: SCNVector3(2.85, 2.62, -5.8)))
        return root
    }

    private func updateClock(text: String) {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        let hour = parts[0].truncatingRemainder(dividingBy: 12)
        let minute = parts[1]
        let minuteAngle = -CGFloat((minute / 60) * 2 * Double.pi)
        let hourAngle = -CGFloat(((hour + minute / 60) / 12) * 2 * Double.pi)
        clockMinuteHandNode.eulerAngles.z = minuteAngle
        clockHourHandNode.eulerAngles.z = hourAngle
    }

    private func updateBlackboard(game: GameManager) {
        blackboardStatusNode.childNodes.forEach { $0.removeFromParentNode() }
        let status = "时间 \(game.clockText)   作业 \(Int(game.player.homework))%   压力 \(Int(game.player.stress))"
        blackboardStatusNode.addChildNode(makeText(status, size: 0.07, color: NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.62, alpha: 1), position: SCNVector3Zero))
    }

    private func updateTimeAtmosphere(game: GameManager) {
        let lightLevel = game.classroomLightLevel
        let period = game.currentPeriod
        let skyColor: NSColor
        let ambientColor: NSColor
        let lampOpacity: CGFloat

        switch period {
        case .first:
            skyColor = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.15, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.64, green: 0.68, blue: 0.76, alpha: 1)
            lampOpacity = 0.42
        case .breakOne, .breakTwo:
            skyColor = NSColor(calibratedRed: 0.05, green: 0.075, blue: 0.18, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.68, alpha: 1)
            lampOpacity = 0.62
        case .second:
            skyColor = NSColor(calibratedRed: 0.03, green: 0.045, blue: 0.13, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.72, alpha: 1)
            lampOpacity = 0.56
        case .third:
            skyColor = NSColor(calibratedRed: 0.015, green: 0.025, blue: 0.075, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.5, green: 0.55, blue: 0.68, alpha: 1)
            lampOpacity = 0.78
        }

        ambientNode.light?.color = lightLevel < 0.6 ? NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.36, alpha: 1) : ambientColor
        outsideSkyNode.childNodes.first?.geometry?.firstMaterial?.diffuse.contents = skyColor
        outsideSkyNode.childNodes.first?.geometry?.firstMaterial?.emission.contents = skyColor.withAlphaComponent(lightLevel < 0.6 ? 0.42 : 0.12)
        outsideLampNode.opacity = lightLevel < 0.6 ? 0.95 : lampOpacity
        outsideLampNode.childNodes.forEach {
            $0.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.18, alpha: lightLevel < 0.6 ? 0.85 : 0.38)
        }
    }

    private func updateDeskState(game: GameManager) {
        let progress = max(0.02, min(1.0, game.player.homework / 100))
        homeworkProgressNode.scale = SCNVector3(Float(progress) * 0.46, 1, 1)
        homeworkProgressNode.opacity = game.cameraPose == .desk ? 1.0 : 0.62

        let bladderLoad = max(0.02, min(1.0, game.player.bladder / 100))
        bladderIndicatorNode.scale = SCNVector3(Float(bladderLoad) * 0.34, 1, 1)
        bladderIndicatorNode.opacity = game.player.bladder > 48 || game.cameraPose == .desk ? 0.35 + CGFloat(bladderLoad) * 0.55 : 0.18

        let stressTilt = CGFloat(min(0.22, game.player.stress / 420))
        let bodyTension = CGFloat(max(0, game.player.bladder - 52) / 48)
        let phoneActive = game.audioCues.first?.kind == .phone
        let snackActive = game.audioCues.first?.kind == .wrapper
        let paperActive = game.audioCues.first?.kind == .paper
        let drawerOpen = game.cameraPose == .desk || phoneActive || snackActive || paperActive
        drawerNode.position.z = drawerOpen ? 1.78 : 1.66
        drawerNode.opacity = drawerOpen ? 0.92 : 0.55
        drawerShadowNode.opacity = drawerOpen ? 0.44 : 0.18
        snackWrapperNode.opacity = snackActive || game.player.hunger < 18 ? 0.95 : 0.32
        leftHandNode.eulerAngles.x = phoneActive ? -0.08 : stressTilt + bodyTension * 0.04
        leftHandNode.eulerAngles.z = phoneActive ? -0.2 : stressTilt + bodyTension * 0.05
        rightHandNode.eulerAngles.x = snackActive ? -0.34 : (phoneActive ? -0.2 : -stressTilt - bodyTension * 0.04)
        rightHandNode.eulerAngles.z = snackActive ? 0.34 : (phoneActive ? 0.24 : -stressTilt - bodyTension * 0.05)

        if bodyTension > 0.1 && leftLegNode.action(forKey: "bladder_fidget") == nil {
            let left = SCNAction.rotateBy(x: 0, y: 0, z: 0.08, duration: 0.12)
            let right = SCNAction.rotateBy(x: 0, y: 0, z: -0.16, duration: 0.18)
            let back = SCNAction.rotateBy(x: 0, y: 0, z: 0.08, duration: 0.12)
            leftLegNode.runAction(.repeatForever(.sequence([left, right, back, .wait(duration: 0.35)])), forKey: "bladder_fidget")
            rightLegNode.runAction(.repeatForever(.sequence([right, left, back, .wait(duration: 0.35)])), forKey: "bladder_fidget")
            seatTensionNode.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.22, duration: 0.18),
                .fadeOpacity(to: 0.08, duration: 0.28),
                .wait(duration: 0.35)
            ])), forKey: "seat_tension")
        } else if bodyTension <= 0.1 {
            leftLegNode.removeAction(forKey: "bladder_fidget")
            rightLegNode.removeAction(forKey: "bladder_fidget")
            seatTensionNode.removeAction(forKey: "seat_tension")
            leftLegNode.eulerAngles.z = 0
            rightLegNode.eulerAngles.z = 0
            seatTensionNode.opacity = 0.08
        }
    }

    private func eventVisualIntensity(game: GameManager) -> (blur: Double, vignette: Double, desaturation: Double) {
        guard case .event(let event) = game.gameState else {
            return (0, 0, 0)
        }
        switch event.kind {
        case .playerBreakdown:
            return (5.5, 1.2, 0.46)
        case .loneliness:
            return (3.6, 1.0, 0.38)
        case .powerOutage:
            return (1.8, 0.72, 0.28)
        case .phoneNotification:
            return (1.2, 0.42, 0.12)
        case .broadcast:
            return (1.0, 0.46, 0.18)
        case .knockOnDoor:
            return (1.5, 0.58, 0.16)
        case .discovery:
            return (3.0, 0.9, 0.22)
        case .classmateCrying:
            return (2.4, 0.78, 0.24)
        case .classmateHelpRequest:
            return (1.0, 0.34, 0.1)
        case .classmateReport:
            return (2.0, 0.66, 0.2)
        case .memoryTrust:
            return (0.7, 0.24, 0.06)
        case .memorySuspicion:
            return (2.2, 0.74, 0.22)
        case .teacherConcern, .supportOffer:
            return (0.8, 0.28, 0.08)
        case .leaveSeatRequest:
            return (1.4, 0.48, 0.14)
        }
    }

    private func makeText(_ string: String, size: CGFloat, color: NSColor, position: SCNVector3) -> SCNNode {
        let geometry = SCNText(string: string, extrusionDepth: 0.002)
        geometry.font = NSFont.systemFont(ofSize: size, weight: .semibold)
        geometry.flatness = 0.3
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.scale = SCNVector3(1, 1, 1)
        return node
    }

    private func applyStateAnimation(_ state: ClassmateState, to node: SCNNode) {
        node.removeAllActions()
        node.eulerAngles.x = 0
        node.eulerAngles.z = 0
        node.childNode(withName: "phone", recursively: false)?.opacity = state == .usingPhone ? 1 : 0
        node.childNode(withName: "paper", recursively: false)?.opacity = state == .studying ? 0.7 : 0.35

        switch state {
        case .studying:
            let down = SCNAction.rotateTo(x: -0.08, y: CGFloat.pi, z: 0, duration: 0.35)
            let up = SCNAction.rotateTo(x: 0.02, y: CGFloat.pi, z: 0, duration: 0.35)
            node.runAction(.repeatForever(.sequence([down, up])), forKey: "write")
        case .usingPhone:
            node.eulerAngles.x = -0.22
            node.childNode(withName: "phone", recursively: false)?.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.05, green: 0.2, blue: 0.8, alpha: 1)
        case .anxious:
            let left = SCNAction.moveBy(x: -0.025, y: 0, z: 0, duration: 0.05)
            let right = SCNAction.moveBy(x: 0.05, y: 0, z: 0, duration: 0.08)
            let back = SCNAction.moveBy(x: -0.025, y: 0, z: 0, duration: 0.05)
            node.runAction(.repeatForever(.sequence([left, right, back, .wait(duration: 0.25)])), forKey: "fidget")
        case .sleeping:
            node.eulerAngles.x = -0.55
        case .crying:
            node.eulerAngles.x = -0.72
            let tremble = SCNAction.sequence([.moveBy(x: 0, y: 0.012, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.012, z: 0, duration: 0.12)])
            node.runAction(.repeatForever(tremble), forKey: "cry")
        case .offeringHelp:
            node.eulerAngles.x = -0.12
            node.eulerAngles.z = -0.08
        case .lookingAtPlayer:
            node.eulerAngles.x = -0.04
            node.eulerAngles.z = 0
            node.childNode(withName: "head", recursively: false)?.runAction(.repeatForever(.sequence([
                .rotateBy(x: 0, y: 0.08, z: 0, duration: 0.4),
                .rotateBy(x: 0, y: -0.08, z: 0, duration: 0.4)
            ])), forKey: "glance")
        case .covering:
            node.eulerAngles.z = 0.16
        }
    }

    private func makeLighting() -> SCNNode {
        let root = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 230
        ambient.color = NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.78, alpha: 1)
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        for x in [-2.7, 0, 2.7] {
            for z in [-3.6, -0.4, 2.8] {
                let light = SCNLight()
                light.type = .omni
                light.intensity = 260
                light.color = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.82, alpha: 1)
                let node = SCNNode()
                node.light = light
                node.position = SCNVector3(Float(x), 3.15, Float(z))
                root.addChildNode(node)
            }
        }
        for z in [-1.8, 2.1] {
            let fan = makeCeilingFan(at: SCNVector3(0, 3.18, Float(z)))
            fanNodes.append(fan)
            root.addChildNode(fan)
        }
        return root
    }

    private func makeCeilingFan(at position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        root.opacity = 0.28
        root.addChildNode(capsule(radius: 0.018, height: 0.24, color: NSColor(calibratedWhite: 0.42, alpha: 1), position: SCNVector3(0, 0.12, 0)))
        let hub = sphere(radius: 0.055, color: NSColor(calibratedWhite: 0.34, alpha: 1), position: SCNVector3(0, 0, 0))
        root.addChildNode(hub)
        for angle in [0.0, Double.pi * 2 / 3, Double.pi * 4 / 3] {
            let blade = box(width: 0.62, height: 0.012, length: 0.075, color: NSColor(calibratedWhite: 0.5, alpha: 1), position: SCNVector3(0.31, 0, 0))
            let bladeRoot = SCNNode()
            bladeRoot.eulerAngles.y = CGFloat(angle)
            bladeRoot.addChildNode(blade)
            root.addChildNode(bladeRoot)
        }
        return root
    }

    private func updateFans(game: GameManager) {
        let active = game.currentPeriod == .third || game.classroomLightLevel < 0.6
        guard active != lastFanActive else {
            for fan in fanNodes {
                fan.opacity = active ? 0.62 : 0.28
            }
            return
        }
        lastFanActive = active
        for fan in fanNodes {
            fan.removeAction(forKey: "spin")
            fan.opacity = active ? 0.62 : 0.28
            if active {
                fan.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: game.currentPeriod == .third ? 0.42 : 0.85)), forKey: "spin")
            }
        }
    }

    private func emissionColor(for state: ClassmateState) -> NSColor {
        switch state {
        case .anxious:
            return NSColor(calibratedRed: 0.18, green: 0.08, blue: 0.02, alpha: 1)
        case .crying:
            return NSColor(calibratedRed: 0.26, green: 0.04, blue: 0.04, alpha: 1)
        case .offeringHelp, .covering, .lookingAtPlayer:
            return NSColor(calibratedRed: 0.02, green: 0.14, blue: 0.12, alpha: 1)
        case .usingPhone:
            return NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.18, alpha: 1)
        default:
            return NSColor.black
        }
    }

    private func box(width: CGFloat, height: CGFloat, length: CGFloat, color: NSColor, position: SCNVector3) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.01)
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private func capsule(radius: CGFloat, height: CGFloat, color: NSColor, position: SCNVector3, rotation: SCNVector4? = nil) -> SCNNode {
        let geometry = SCNCapsule(capRadius: radius, height: height)
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        if let rotation {
            node.rotation = rotation
        }
        return node
    }

    private func sphere(radius: CGFloat, color: NSColor, position: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 12
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.scale = scale
        return node
    }

    private func gazeCone() -> SCNNode {
        let geometry = SCNCone(topRadius: 0.06, bottomRadius: 0.62, height: 2.7)
        geometry.radialSegmentCount = 24
        geometry.firstMaterial = material(NSColor(calibratedRed: 1.0, green: 0.46, blue: 0.22, alpha: 0.18))
        geometry.firstMaterial?.blendMode = .add
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.writesToDepthBuffer = false
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(0, 0, -1.35)
        return node
    }

    private func makeGlasses() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.09, height: 0.012, length: 0.018, color: NSColor(calibratedWhite: 0.04, alpha: 1), position: SCNVector3(-0.045, 0.805, -0.118)))
        root.addChildNode(box(width: 0.09, height: 0.012, length: 0.018, color: NSColor(calibratedWhite: 0.04, alpha: 1), position: SCNVector3(0.045, 0.805, -0.118)))
        root.addChildNode(box(width: 0.028, height: 0.008, length: 0.014, color: NSColor(calibratedWhite: 0.04, alpha: 1), position: SCNVector3(0, 0.805, -0.12)))
        return root
    }

    private func studentUniformColor(seed: Int, profile: ClassmateProfile?, fallback: NSColor) -> NSColor {
        guard let profile else { return fallback }
        if profile.rebelliousness > 72 {
            return NSColor(calibratedRed: 0.46, green: 0.18, blue: 0.28, alpha: 1)
        }
        if profile.orderliness > 72 {
            return NSColor(calibratedRed: 0.15, green: 0.2, blue: 0.46, alpha: 1)
        }
        if profile.empathy > 72 {
            return NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.38, alpha: 1)
        }
        if profile.anxiety > 68 {
            return NSColor(calibratedRed: 0.36, green: 0.34, blue: 0.46, alpha: 1)
        }
        return fallback
    }

    private func hairScale(seed: Int, profile: ClassmateProfile?) -> SCNVector3 {
        if profile?.rebelliousness ?? 0 > 72 {
            return SCNVector3(1.12, 0.58, 0.92)
        }
        if profile?.orderliness ?? 0 > 72 {
            return SCNVector3(0.94, 0.36, 0.94)
        }
        if profile?.empathy ?? 0 > 72 {
            return SCNVector3(1.02, 0.52, 1.12)
        }
        return SCNVector3(1, 0.45 + Float(seed % 3) * 0.04, 1)
    }

    private func material(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.78
        return material
    }

    private func skinColor(_ seed: Int) -> NSColor {
        let colors = [
            NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.76, green: 0.56, blue: 0.4, alpha: 1)
        ]
        return colors[seed % colors.count]
    }

    private var wallColor: NSColor {
        NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.78, alpha: 1)
    }

    private var skinTone: NSColor {
        NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.58, alpha: 1)
    }
}
