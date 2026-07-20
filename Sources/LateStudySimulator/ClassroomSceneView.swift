import AppKit
import CoreGraphics
import SceneKit
import SwiftUI

@MainActor
final class StudentInputSCNView: SCNView {
    var onKeyChanged: ((NSEvent, Bool) -> Void)?
    var onModifierChanged: ((NSEvent) -> Void)?
    var onWindowChanged: ((NSWindow?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyChanged?(event, true)
    }

    override func keyUp(with event: NSEvent) {
        onKeyChanged?(event, false)
    }

    override func flagsChanged(with event: NSEvent) {
        onModifierChanged?(event)
    }
}

@MainActor
struct ClassroomSceneView: NSViewRepresentable {
    @ObservedObject var game: GameManager

    func makeNSView(context: Context) -> SCNView {
        let view = StudentInputSCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraRig
        view.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.05, alpha: 1)
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        context.coordinator.installInput(on: view)
        context.coordinator.update(game: game)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(game: game)
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: ClassroomCoordinator) {
        coordinator.teardownInput()
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
    private let playerSeatedPropsNode = SCNNode()
    private let blackboardStatusNode = SCNNode()
    private let clockHourHandNode = SCNNode()
    private let clockMinuteHandNode = SCNNode()
    private let homeworkProgressNode = SCNNode()
    private let homeworkSheetNode = SCNNode()
    private let penNode = SCNNode()
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
    private let outsideCloudNode = SCNNode()
    private let outsideRainNode = SCNNode()
    private let outsideSunNode = SCNNode()
    private let outsideMoonNode = SCNNode()
    private let frontDoorLeftNode = SCNNode()
    private let frontDoorRightNode = SCNNode()
    private let rearDoorLeftNode = SCNNode()
    private let rearDoorRightNode = SCNNode()
    private let playerLockerDoorNode = SCNNode()
    private var fanNodes: [SCNNode] = []
    private var classmateNodes: [Int: SCNNode] = [:]
    private var classmateStates: [Int: ClassmateState] = [:]
    private var classmateProfileSignature = ""
    private var lastFanSpinDuration: Double = 0
    private var lastPose: CameraPose = .forward
    private var lastViewMode: ViewMode = .student
    private var lastFreeRoamActive = false
    private var lastStudentLookYaw: Double = 0
    private var lastStudentLookPitch: Double = 0
    private weak var currentGame: GameManager?
    private weak var inputView: StudentInputSCNView?
    private var pressedKeys: Set<Character> = []
    private var movementTimer: Timer?
    private var lastMovementTick = Date()
    private var pendingMouseDeltaX = 0.0
    private var pendingMouseDeltaY = 0.0
    private var wantsMouseLook = true
    private var isMouseLookCaptured = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        buildScene()
    }

    func installInput(on view: StudentInputSCNView) {
        view.onKeyChanged = { [weak self] event, isDown in
            self?.handleKey(event, isDown: isDown)
        }
        view.onModifierChanged = { [weak self] event in
            self?.handleModifier(event)
        }
        view.onWindowChanged = { [weak self] window in
            self?.observeWindow(window)
        }
        inputView = view
        installMouseLookKeyMonitor()
        installMouseLookMouseMonitor()
        movementTimer?.invalidate()
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMovement()
            }
        }
    }

    func update(game: GameManager) {
        currentGame = game
        observeWindow(inputView?.window)
        synchronizeMouseLook(for: game)
        let signature = profileSignature(for: game.classmates)
        if !game.classmates.isEmpty && signature != classmateProfileSignature {
            rebuildClassmates(with: game.classmates)
            classmateProfileSignature = signature
        }

        let cameraContextChanged = lastViewMode != game.viewMode || lastFreeRoamActive != game.freeRoam.isActive
        let poseChanged = lastPose != game.cameraPose
        let studentLookChanged = game.viewMode == .student && (
            lastStudentLookYaw != game.studentLookYaw || lastStudentLookPitch != game.studentLookPitch
        )
        lastStudentLookYaw = game.studentLookYaw
        lastStudentLookPitch = game.studentLookPitch

        if cameraContextChanged {
            lastPose = game.cameraPose
            lastViewMode = game.viewMode
            lastFreeRoamActive = game.freeRoam.isActive
            SCNTransaction.begin()
            SCNTransaction.animationDuration = cameraTurnDuration(game: game)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyCameraMode(game: game, teacherPosition: teacherNode.position)
            SCNTransaction.commit()
        } else if poseChanged || studentLookChanged || game.freeRoam.isActive {
            lastPose = game.cameraPose
            lastViewMode = game.viewMode
            lastFreeRoamActive = game.freeRoam.isActive
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
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
        updateClock(game: game)
        updateBlackboard(game: game)
        updateTimeAtmosphere(game: game)
        updateFans(game: game)
        updateDoors(game: game)
        updatePlayerLocker(game: game)
        updateDeskState(game: game)
        if let camera = cameraRig.camera {
            let fatigue = game.viewMode == .teacher ? game.teacher.fatigue / 140 : 1 - game.player.focusQuality
            let eventIntensity = eventVisualIntensity(game: game)
            camera.fStop = 1.6 + fatigue * 7.0 + eventIntensity.blur
            camera.focusDistance = game.viewMode == .teacher ? 4.2 : studentFocusDistance(game: game)
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
        scene.rootNode.addChildNode(makeCorridor())
        scene.rootNode.addChildNode(makeFurniture())
        scene.rootNode.addChildNode(makeInteriorDetails())
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
            if game.freeRoam.isActive {
                cameraRig.position = SCNVector3(Float(game.freeRoam.positionX), 1.58, Float(game.freeRoam.positionZ))
                cameraRig.eulerAngles = SCNVector3(Float(game.freeRoam.pitch), Float(game.freeRoam.yaw), game.freeRoam.isSideways ? 0.08 : 0)
                cameraRig.camera?.fieldOfView = 92
            } else {
                let height: Float = game.player.posture == .standing ? 1.58 : 1.18
                let stressSway = Float(min(0.035, game.player.stress / 2_500))
                let attentionDip = Float(max(0, 35 - game.player.visualAttention) / 1_200)
                cameraRig.position = SCNVector3(-0.6 + stressSway, height - attentionDip, 1.5)
                cameraRig.eulerAngles = SCNVector3(Float(game.studentLookPitch), Float(game.studentLookYaw), 0)
                cameraRig.camera?.fieldOfView = 100
            }
        case .teacher:
            cameraRig.position = SCNVector3(teacherPosition.x, 1.48, teacherPosition.z + 0.18)
            let target = teacherCameraTarget(game: game)
            cameraRig.eulerAngles = teacherEulerAngles(from: cameraRig.position, to: target)
            cameraRig.camera?.fieldOfView = game.teacher.focusMode == .wholeClass ? 88 : 74
        }
    }

    private func cameraTurnDuration(game: GameManager) -> Double {
        game.viewMode == .student ? 0.16 : 0.28
    }

    private func studentFocusDistance(game: GameManager) -> Double {
        if abs(game.studentLookYaw) > 2.35 {
            return 2.4
        }
        if game.studentLookPitch < 0 {
            let deskAmount = (-game.studentLookPitch / 0.72).clamped(to: 0...1)
            return 1.5 + (0.55 - 1.5) * deskAmount
        }
        let boardAmount = (game.studentLookPitch / 0.48).clamped(to: 0...1)
        return 1.5 + (5.8 - 1.5) * boardAmount
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

    private func teacherCameraTarget(game: GameManager) -> SCNVector3 {
        switch game.teacher.focusMode {
        case .wholeClass:
            return SCNVector3(0, 0.88, 0.15)
        case .selectedStudent:
            if let target = game.selectedTeacherTarget {
                return classmateHeadPosition(seat: target.seat)
            }
            return SCNVector3(0, 0.88, 0.15)
        case .blackboard:
            return SCNVector3(0, 1.88, -5.7)
        case .rearDoor:
            return SCNVector3(-3.9, 1.25, 4.25)
        }
    }

    private func handleMouseMovement(_ event: NSEvent) {
        guard isMouseLookCaptured else { return }
        guard let game = currentGame, game.activeRole.isTeacher == false else { return }
        guard case .playing = game.gameState, game.isReturningToSeat == false else { return }
        guard event.deltaX != 0 || event.deltaY != 0 else { return }
        pendingMouseDeltaX += event.deltaX
        pendingMouseDeltaY += event.deltaY
    }

    private func handleKey(_ event: NSEvent, isDown: Bool) {
        if isMouseLookToggle(event), isDown {
            toggleMouseLook()
            return
        }
        if event.keyCode == 14 {
            if isDown && event.isARepeat == false {
                currentGame?.interactWithNearbyDoor()
            }
            return
        }
        guard let character = movementCharacter(for: event) else { return }
        if isDown {
            pressedKeys.insert(character)
        } else {
            pressedKeys.remove(character)
        }
    }

    private func movementCharacter(for event: NSEvent) -> Character? {
        switch event.keyCode {
        case 13: return "w"
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first,
                  "wasd".contains(character) else {
                return nil
            }
            return character
        }
    }

    private func handleModifier(_ event: NSEvent) {
        synchronizeMovementModifiers(event.modifierFlags)
    }

    private func synchronizeMovementModifiers(_ flags: NSEvent.ModifierFlags) {
        currentGame?.setFreeRoamSideways(flags.contains(.shift))
        currentGame?.setFreeRoamSprinting(flags.contains(.control))
    }

    private func tickMovement() {
        applyPendingMouseLook()
        guard let game = currentGame, game.freeRoam.isActive else {
            lastMovementTick = Date()
            return
        }
        synchronizeMovementModifiers(NSEvent.modifierFlags)
        let now = Date()
        let delta = min(0.05, now.timeIntervalSince(lastMovementTick))
        lastMovementTick = now

        let forward = (pressedKeys.contains("w") ? 1.0 : 0.0) - (pressedKeys.contains("s") ? 1.0 : 0.0)
        let strafe = (pressedKeys.contains("d") ? 1.0 : 0.0) - (pressedKeys.contains("a") ? 1.0 : 0.0)
        if forward != 0 || strafe != 0 {
            game.moveStudentFreeRoam(forward: forward, strafe: strafe, deltaTime: delta)
        }
    }

    private func applyPendingMouseLook() {
        guard pendingMouseDeltaX != 0 || pendingMouseDeltaY != 0 else { return }
        guard let game = currentGame, game.activeRole.isTeacher == false else {
            pendingMouseDeltaX = 0
            pendingMouseDeltaY = 0
            return
        }
        guard case .playing = game.gameState else {
            pendingMouseDeltaX = 0
            pendingMouseDeltaY = 0
            return
        }
        let deltaX = pendingMouseDeltaX
        let deltaY = pendingMouseDeltaY
        pendingMouseDeltaX = 0
        pendingMouseDeltaY = 0
        game.rotateStudentView(deltaX: deltaX, deltaY: deltaY)
    }

    private func installMouseLookKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isMouseLookToggle(event) else { return event }
            self.toggleMouseLook()
            return nil
        }
    }

    private func installMouseLookMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved,
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged
            ]
        ) { [weak self] event in
            guard let self else { return event }
            self.handleMouseMovement(event)
            return event
        }
    }

    private func isMouseLookToggle(_ event: NSEvent) -> Bool {
        event.keyCode == 50 || event.charactersIgnoringModifiers == "`" || event.charactersIgnoringModifiers == "~"
    }

    private func canCaptureMouse(for game: GameManager) -> Bool {
        guard game.activeRole.isTeacher == false else { return false }
        guard case .playing = game.gameState else { return false }
        guard game.isReturningToSeat == false else { return false }
        return inputView?.window?.isKeyWindow == true
    }

    private func synchronizeMouseLook(for game: GameManager) {
        wantsMouseLook = game.mouseLookEnabled
        setMouseLookCaptured(wantsMouseLook && canCaptureMouse(for: game))
    }

    private func toggleMouseLook() {
        guard let game = currentGame, game.activeRole.isTeacher == false else { return }
        guard case .playing = game.gameState else { return }
        wantsMouseLook.toggle()
        game.mouseLookEnabled = wantsMouseLook
        synchronizeMouseLook(for: game)
        game.message = isMouseLookCaptured
            ? "鼠标视角已捕获。移动鼠标可自由环视；按 ~ 释放鼠标以操作界面。"
            : "鼠标已释放。按 ~ 重新捕获鼠标，继续用移动鼠标控制视角。"
    }

    private func setMouseLookCaptured(_ captured: Bool) {
        guard isMouseLookCaptured != captured else { return }
        isMouseLookCaptured = captured
        if captured == false {
            pendingMouseDeltaX = 0
            pendingMouseDeltaY = 0
            pressedKeys.removeAll()
            currentGame?.clearFreeRoamMovementModifiers()
        }
        if captured {
            inputView?.window?.makeFirstResponder(inputView)
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
            recenterMouseCursor()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            inputView?.window?.makeFirstResponder(nil)
        }
        currentGame?.mouseLookCaptured = captured
    }

    private func recenterMouseCursor() {
        guard let inputView, let window = inputView.window else { return }
        let viewCenter = NSPoint(x: inputView.bounds.midX, y: inputView.bounds.midY)
        let windowPoint = inputView.convert(viewCenter, to: nil)
        CGWarpMouseCursorPosition(window.convertPoint(toScreen: windowPoint))
    }

    private func observeWindow(_ window: NSWindow?) {
        guard observedWindow !== window else { return }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        observedWindow = window
        guard let window else {
            setMouseLookCaptured(false)
            return
        }
        window.acceptsMouseMovedEvents = true
        let notificationCenter = NotificationCenter.default
        windowObservers = [
            notificationCenter.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setMouseLookCaptured(false)
                }
            },
            notificationCenter.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let game = self.currentGame else { return }
                    self.synchronizeMouseLook(for: game)
                }
            }
        ]
    }

    func teardownInput() {
        movementTimer?.invalidate()
        movementTimer = nil
        setMouseLookCaptured(false)
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    private func classmateHeadPosition(seat: (row: Int, column: Int)) -> SCNVector3 {
        let x = Float(seat.column) * 1.2 - 2.4
        let z = Float(seat.row) * 1.45 - 2.0
        return SCNVector3(x, 1.22, z)
    }

    private func makeEnvironment() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 8, height: 0.04, length: 12, color: NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.28, alpha: 1), position: SCNVector3(0, -0.02, 0)))
        root.addChildNode(box(width: 8, height: 3.5, length: 0.06, color: wallColor, position: SCNVector3(0, 1.75, -6)))
        root.addChildNode(box(width: 8, height: 3.5, length: 0.06, color: wallColor, position: SCNVector3(0, 1.75, 6)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 12, color: wallColor, position: SCNVector3(-4, 1.75, 0)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 0.88, color: wallColor, position: SCNVector3(4, 1.75, -5.56)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 1.68, color: wallColor, position: SCNVector3(4, 1.75, -3.34)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 1.45, color: wallColor, position: SCNVector3(4, 1.75, -1.775)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 2.05, color: wallColor, position: SCNVector3(4, 1.75, 3.025)))
        root.addChildNode(box(width: 0.06, height: 3.5, length: 0.78, color: wallColor, position: SCNVector3(4, 1.75, 5.61)))
        root.addChildNode(box(width: 0.06, height: 0.62, length: 5.4, color: wallColor, position: SCNVector3(4, 0.31, 0.85)))
        root.addChildNode(box(width: 0.06, height: 0.72, length: 5.4, color: wallColor, position: SCNVector3(4, 3.14, 0.85)))
        root.addChildNode(box(width: 8, height: 0.04, length: 12, color: NSColor(calibratedWhite: 0.93, alpha: 1), position: SCNVector3(0, 3.52, 0)))
        root.addChildNode(makeDoors())

        root.addChildNode(box(width: 4.2, height: 1.2, length: 0.05, color: NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.09, alpha: 1), position: SCNVector3(0, 1.95, -5.94)))
        root.addChildNode(box(width: 1.9, height: 0.9, length: 0.05, color: NSColor(calibratedRed: 0.64, green: 0.48, blue: 0.31, alpha: 1), position: SCNVector3(0, 0.55, -4.7)))
        root.addChildNode(makeBlackboardDetails())
        root.addChildNode(makeSmartFrontWallDetails())
        root.addChildNode(makeWallClock())

        root.addChildNode(makeWindowLayer())

        return root
    }

    private func makeCorridor() -> SCNNode {
        let root = SCNNode()
        let floorColor = NSColor(calibratedRed: 0.34, green: 0.35, blue: 0.36, alpha: 1)
        let wall = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.7, alpha: 1)
        let dimWall = NSColor(calibratedRed: 0.52, green: 0.55, blue: 0.55, alpha: 1)

        root.addChildNode(box(width: 2.8, height: 0.035, length: 20.8, color: floorColor, position: SCNVector3(5.25, -0.018, -1.8)))
        root.addChildNode(box(width: 2.8, height: 0.035, length: 20.8, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(5.25, 2.96, -1.8)))
        root.addChildNode(box(width: 0.06, height: 2.95, length: 20.8, color: dimWall, position: SCNVector3(6.62, 1.46, -1.8)))
        root.addChildNode(box(width: 2.8, height: 2.95, length: 0.06, color: wall, position: SCNVector3(5.25, 1.46, -12.15)))
        root.addChildNode(box(width: 2.8, height: 2.95, length: 0.06, color: wall, position: SCNVector3(5.25, 1.46, 8.45)))
        root.addChildNode(makeCorridorWallDetails())

        for z in [-5.2, -4.55, -3.25] {
            root.addChildNode(box(width: 0.42, height: 1.05, length: 0.36, color: NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.42, alpha: 1), position: SCNVector3(6.55, 0.62, Float(z))))
            root.addChildNode(box(width: 0.03, height: 0.92, length: 0.28, color: NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.2, alpha: 1), position: SCNVector3(6.32, 0.63, Float(z))))
        }
        root.addChildNode(makePlayerLocker())
        for z in [-7.55, -6.85, 6.75, 7.45] {
            root.addChildNode(box(width: 0.42, height: 1.05, length: 0.36, color: NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.42, alpha: 1), position: SCNVector3(6.55, 0.62, Float(z))))
            root.addChildNode(box(width: 0.03, height: 0.92, length: 0.28, color: NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.2, alpha: 1), position: SCNVector3(6.32, 0.63, Float(z))))
        }
        for z in [-0.9, -0.2, 0.5, 1.2, 1.9, 2.6] {
            root.addChildNode(box(width: 0.36, height: 0.95, length: 0.32, color: NSColor(calibratedRed: 0.19, green: 0.27, blue: 0.36, alpha: 1), position: SCNVector3(6.55, 0.58, Float(z))))
            root.addChildNode(box(width: 0.024, height: 0.82, length: 0.24, color: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1), position: SCNVector3(6.32, 0.58, Float(z))))
        }

        let corridorLight = SCNLight()
        corridorLight.type = .omni
        corridorLight.intensity = 210
        corridorLight.color = NSColor(calibratedRed: 0.86, green: 0.92, blue: 1.0, alpha: 1)
        let lightNode = SCNNode()
        lightNode.light = corridorLight
        lightNode.position = SCNVector3(5.15, 2.72, -4.35)
        root.addChildNode(lightNode)
        root.addChildNode(box(width: 0.9, height: 0.02, length: 0.18, color: NSColor(calibratedWhite: 0.92, alpha: 1), position: SCNVector3(5.15, 2.9, -4.35)))
        for z in [-0.6, 1.35, 2.85] {
            let windowLight = SCNLight()
            windowLight.type = .omni
            windowLight.intensity = 120
            windowLight.color = NSColor(calibratedRed: 0.86, green: 0.92, blue: 1.0, alpha: 1)
            let windowLightNode = SCNNode()
            windowLightNode.light = windowLight
            windowLightNode.position = SCNVector3(5.15, 2.55, Float(z))
            root.addChildNode(windowLightNode)
            root.addChildNode(box(width: 0.72, height: 0.018, length: 0.14, color: NSColor(calibratedWhite: 0.92, alpha: 1), position: SCNVector3(5.15, 2.88, Float(z))))
        }

        root.addChildNode(makeNeighborClassroom(label: "高一(1)班", z: -7.25))
        root.addChildNode(makeCurrentClassPlaque(z: -4.65))
        root.addChildNode(makeNeighborClassroom(label: "高一(3)班", z: 7.25))
        root.addChildNode(makeRestroomSign())
        root.addChildNode(makeCorridorNoticeArea())
        root.addChildNode(makeWaterDispenser())
        root.addChildNode(makeTrashBin())
        root.addChildNode(makeOutdoorConnector())
        root.addChildNode(makeText("走廊", size: 0.09, color: NSColor(calibratedWhite: 0.12, alpha: 1), position: SCNVector3(4.72, 1.75, -5.9)))
        return root
    }

    private func makeCorridorWallDetails() -> SCNNode {
        let root = SCNNode()
        let baseColor = NSColor(calibratedRed: 0.46, green: 0.49, blue: 0.47, alpha: 1)
        root.addChildNode(box(width: 0.05, height: 0.42, length: 20.5, color: baseColor, position: SCNVector3(6.585, 0.22, -1.8)))
        root.addChildNode(box(width: 2.65, height: 0.38, length: 0.04, color: baseColor, position: SCNVector3(5.25, 0.2, -8.39)))
        root.addChildNode(box(width: 2.65, height: 0.38, length: 0.04, color: baseColor, position: SCNVector3(5.25, 0.2, 8.39)))
        let seam = NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.27, alpha: 1)
        for z in stride(from: -12.0, through: 8.0, by: 1.0) {
            root.addChildNode(box(width: 2.55, height: 0.004, length: 0.012, color: seam, position: SCNVector3(5.25, 0.005, Float(z))))
        }
        for x in [4.35, 5.25, 6.15] {
            root.addChildNode(box(width: 0.012, height: 0.004, length: 20.5, color: seam, position: SCNVector3(Float(x), 0.006, -1.8)))
        }
        return root
    }

    private func makeCorridorDoor(label: String, z: Float) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.05, height: 1.7, length: 0.78, color: NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.16, alpha: 1), position: SCNVector3(4.11, 0.92, z)))
        root.addChildNode(box(width: 0.055, height: 0.22, length: 0.72, color: NSColor(calibratedWhite: 0.88, alpha: 1), position: SCNVector3(4.08, 1.92, z)))
        root.addChildNode(makePlaqueText(label, position: SCNVector3(4.145, 1.9, z)))
        root.addChildNode(sphere(radius: 0.026, color: NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(4.05, 0.98, z + 0.25)))
        return root
    }

    private func makeNeighborClassroom(label: String, z: Float) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(makeCorridorDoor(label: label, z: z))
        root.addChildNode(makeNeighborWindow(z: z + 0.82))
        root.addChildNode(makeNeighborWindow(z: z - 0.82))
        root.addChildNode(makeNeighborRoomInterior(z: z))
        return root
    }

    private func makeCurrentClassPlaque(z: Float) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.055, height: 0.24, length: 0.82, color: NSColor(calibratedWhite: 0.92, alpha: 1), position: SCNVector3(4.1, 2.2, z)))
        root.addChildNode(box(width: 0.006, height: 0.12, length: 0.54, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(4.142, 2.18, z)))
        root.addChildNode(makePlaqueText("高一(2)班", position: SCNVector3(4.145, 2.18, z)))
        return root
    }

    private func makePlaqueText(_ string: String, position: SCNVector3) -> SCNNode {
        let text = SCNText(string: string, extrusionDepth: 0.001)
        text.font = NSFont.systemFont(ofSize: 0.16, weight: .bold)
        text.flatness = 0.2
        text.firstMaterial = material(NSColor(calibratedWhite: 0.02, alpha: 1))
        text.firstMaterial?.isDoubleSided = true

        let textNode = SCNNode(geometry: text)
        let (minBounds, maxBounds) = text.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation(
            (minBounds.x + maxBounds.x) / 2,
            (minBounds.y + maxBounds.y) / 2,
            0
        )
        textNode.scale = SCNVector3(0.75, 0.75, 0.75)
        textNode.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0)
        textNode.position = position
        return textNode
    }

    private func makePlayerLocker() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.42, height: 1.05, length: 0.36, color: NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.5, alpha: 1), position: SCNVector3(6.55, 0.62, -3.9)))
        root.addChildNode(box(width: 0.032, height: 0.92, length: 0.28, color: NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.18, alpha: 1), position: SCNVector3(6.315, 0.63, -3.9)))
        playerLockerDoorNode.addChildNode(box(width: 0.026, height: 0.86, length: 0.26, color: NSColor(calibratedRed: 0.18, green: 0.44, blue: 0.66, alpha: 1), position: SCNVector3Zero))
        playerLockerDoorNode.addChildNode(sphere(radius: 0.018, color: NSColor(calibratedRed: 0.88, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(-0.018, 0.08, 0.09)))
        root.addChildNode(playerLockerDoorNode)
        updatePlayerLocker(isOpen: false)
        let label = makeText("我的柜", size: 0.04, color: NSColor(calibratedWhite: 0.96, alpha: 1), position: SCNVector3(6.275, 1.18, -4.02))
        label.eulerAngles.y = -CGFloat.pi / 2
        root.addChildNode(label)
        return root
    }

    private func makeNeighborWindow(z: Float) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(glassPane(width: 0.04, height: 0.82, length: 0.58, position: SCNVector3(4.06, 1.55, z)))
        root.addChildNode(box(width: 0.055, height: 0.9, length: 0.035, color: NSColor(calibratedWhite: 0.76, alpha: 1), position: SCNVector3(4.075, 1.55, z - 0.31)))
        root.addChildNode(box(width: 0.055, height: 0.9, length: 0.035, color: NSColor(calibratedWhite: 0.76, alpha: 1), position: SCNVector3(4.075, 1.55, z + 0.31)))
        root.addChildNode(box(width: 0.055, height: 0.035, length: 0.66, color: NSColor(calibratedWhite: 0.76, alpha: 1), position: SCNVector3(4.075, 1.98, z)))
        root.addChildNode(box(width: 0.055, height: 0.035, length: 0.66, color: NSColor(calibratedWhite: 0.76, alpha: 1), position: SCNVector3(4.075, 1.12, z)))
        return root
    }

    private func makeNeighborRoomInterior(z: Float) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 2.1, height: 0.035, length: 3.7, color: NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.28, alpha: 1), position: SCNVector3(3.0, -0.01, z)))
        root.addChildNode(box(width: 0.035, height: 2.2, length: 3.7, color: NSColor(calibratedRed: 0.68, green: 0.69, blue: 0.64, alpha: 1), position: SCNVector3(3.78, 1.08, z)))
        root.addChildNode(box(width: 2.1, height: 2.2, length: 0.035, color: NSColor(calibratedRed: 0.66, green: 0.67, blue: 0.62, alpha: 1), position: SCNVector3(2.9, 1.08, z - 1.84)))
        root.addChildNode(box(width: 2.1, height: 2.2, length: 0.035, color: NSColor(calibratedRed: 0.66, green: 0.67, blue: 0.62, alpha: 1), position: SCNVector3(2.9, 1.08, z + 1.84)))
        for row in 0..<2 {
            for column in 0..<3 {
                let deskX = 2.52 + Float(column) * 0.48
                let deskZ = z - 0.95 + Float(row) * 0.78
                root.addChildNode(box(width: 0.34, height: 0.055, length: 0.22, color: NSColor(calibratedRed: 0.58, green: 0.44, blue: 0.3, alpha: 1), position: SCNVector3(deskX, 0.78, deskZ)))
                root.addChildNode(box(width: 0.12, height: 0.22, length: 0.06, color: NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.44, alpha: 1), position: SCNVector3(deskX + 0.02, 0.96, deskZ + 0.08)))
            }
        }
        root.addChildNode(box(width: 0.036, height: 0.52, length: 1.15, color: NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.08, alpha: 1), position: SCNVector3(3.73, 1.72, z - 1.32)))
        root.addChildNode(box(width: 0.5, height: 0.72, length: 0.035, color: NSColor(calibratedRed: 0.76, green: 0.74, blue: 0.68, alpha: 1), position: SCNVector3(2.85, 1.56, z + 1.82)))
        return root
    }

    private func makeOutdoorConnector() -> SCNNode {
        let root = SCNNode()
        let floor = NSColor(calibratedRed: 0.36, green: 0.37, blue: 0.36, alpha: 1)
        let wall = NSColor(calibratedRed: 0.69, green: 0.71, blue: 0.67, alpha: 1)
        let frame = NSColor(calibratedWhite: 0.72, alpha: 1)

        root.addChildNode(box(width: 1.85, height: 0.035, length: 2.2, color: floor, position: SCNVector3(3.12, -0.018, -9.35)))
        root.addChildNode(box(width: 1.85, height: 0.035, length: 2.2, color: NSColor(calibratedWhite: 0.78, alpha: 1), position: SCNVector3(3.12, 2.92, -9.35)))
        root.addChildNode(box(width: 0.06, height: 2.9, length: 2.2, color: wall, position: SCNVector3(2.18, 1.45, -9.35)))
        root.addChildNode(box(width: 1.86, height: 2.9, length: 0.06, color: wall, position: SCNVector3(3.12, 1.45, -10.42)))
        root.addChildNode(box(width: 1.86, height: 2.9, length: 0.06, color: wall, position: SCNVector3(3.12, 1.45, -8.28)))

        root.addChildNode(box(width: 0.08, height: 2.35, length: 0.12, color: frame, position: SCNVector3(4.03, 1.18, -10.23)))
        root.addChildNode(box(width: 0.08, height: 2.35, length: 0.12, color: frame, position: SCNVector3(4.03, 1.18, -8.47)))
        root.addChildNode(box(width: 0.08, height: 0.1, length: 1.86, color: frame, position: SCNVector3(4.03, 2.33, -9.35)))
        root.addChildNode(box(width: 0.08, height: 0.46, length: 1.86, color: wall, position: SCNVector3(4.03, 2.7, -9.35)))

        root.addChildNode(glassPane(width: 0.04, height: 1.55, length: 1.55, position: SCNVector3(2.16, 1.46, -9.35)))
        root.addChildNode(box(width: 0.05, height: 1.66, length: 0.045, color: frame, position: SCNVector3(2.14, 1.46, -10.14)))
        root.addChildNode(box(width: 0.05, height: 1.66, length: 0.045, color: frame, position: SCNVector3(2.14, 1.46, -8.56)))
        root.addChildNode(box(width: 0.05, height: 0.05, length: 1.64, color: frame, position: SCNVector3(2.14, 2.26, -9.35)))
        root.addChildNode(box(width: 0.05, height: 0.05, length: 1.64, color: frame, position: SCNVector3(2.14, 0.68, -9.35)))

        root.addChildNode(box(width: 0.035, height: 1.9, length: 1.75, color: NSColor(calibratedRed: 0.48, green: 0.72, blue: 0.96, alpha: 1), position: SCNVector3(1.95, 1.43, -9.35)))
        root.addChildNode(box(width: 0.035, height: 0.34, length: 1.1, color: NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.22, alpha: 1), position: SCNVector3(1.92, 0.35, -9.45)))
        root.addChildNode(box(width: 0.035, height: 0.9, length: 0.12, color: NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.22, alpha: 1), position: SCNVector3(1.91, 0.8, -8.85)))
        root.addChildNode(sphere(radius: 0.26, color: NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.2, alpha: 1), position: SCNVector3(1.9, 1.35, -8.85)))

        for index in 0..<4 {
            let x = 2.35 - Float(index) * 0.22
            let y = 0.04 + Float(index) * 0.045
            root.addChildNode(box(width: 0.22, height: 0.09, length: 1.35, color: NSColor(calibratedRed: 0.44, green: 0.44, blue: 0.42, alpha: 1), position: SCNVector3(x, y, -9.35)))
        }

        root.addChildNode(makeText("门厅", size: 0.075, color: NSColor(calibratedWhite: 0.12, alpha: 1), position: SCNVector3(3.95, 1.95, -10.1)))
        return root
    }

    private func makeRestroomSign() -> SCNNode {
        let root = SCNNode()
        let tile = NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.84, alpha: 1)
        let partition = NSColor(calibratedRed: 0.28, green: 0.42, blue: 0.55, alpha: 1)
        let porcelain = NSColor(calibratedWhite: 0.93, alpha: 1)
        root.addChildNode(box(width: 1.18, height: 0.035, length: 1.18, color: NSColor(calibratedRed: 0.58, green: 0.64, blue: 0.64, alpha: 1), position: SCNVector3(6.7, 0.0, 5.85)))
        root.addChildNode(box(width: 0.05, height: 2.05, length: 1.2, color: tile, position: SCNVector3(7.3, 1.02, 5.85)))
        root.addChildNode(box(width: 1.2, height: 2.05, length: 0.05, color: tile, position: SCNVector3(6.7, 1.02, 5.25)))
        root.addChildNode(box(width: 1.2, height: 2.05, length: 0.05, color: tile, position: SCNVector3(6.7, 1.02, 6.45)))
        root.addChildNode(box(width: 0.06, height: 1.75, length: 0.12, color: partition, position: SCNVector3(6.2, 0.9, 5.31)))
        root.addChildNode(box(width: 0.06, height: 1.75, length: 0.12, color: partition, position: SCNVector3(6.2, 0.9, 6.39)))
        root.addChildNode(box(width: 0.06, height: 0.18, length: 0.98, color: partition, position: SCNVector3(6.2, 1.72, 5.85)))
        root.addChildNode(box(width: 0.065, height: 0.24, length: 0.88, color: NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.0, alpha: 1), position: SCNVector3(6.14, 1.84, 5.85)))
        root.addChildNode(makeText("洗手间", size: 0.055, color: NSColor(calibratedWhite: 0.05, alpha: 1), position: SCNVector3(6.09, 1.79, 5.58)))
        root.addChildNode(box(width: 0.018, height: 0.9, length: 0.1, color: NSColor(calibratedWhite: 0.95, alpha: 1), position: SCNVector3(6.1, 0.82, 5.42)))
        root.addChildNode(box(width: 0.018, height: 0.9, length: 0.1, color: NSColor(calibratedWhite: 0.95, alpha: 1), position: SCNVector3(6.1, 0.82, 6.28)))
        root.addChildNode(box(width: 0.5, height: 0.04, length: 0.42, color: porcelain, position: SCNVector3(7.02, 0.66, 5.5)))
        root.addChildNode(box(width: 0.36, height: 0.08, length: 0.28, color: porcelain, position: SCNVector3(7.05, 0.72, 5.5)))
        root.addChildNode(capsule(radius: 0.018, height: 0.18, color: NSColor(calibratedWhite: 0.55, alpha: 1), position: SCNVector3(7.02, 0.86, 5.5), rotation: SCNVector4(1, 0, 0, Float.pi / 2)))
        root.addChildNode(box(width: 0.34, height: 0.42, length: 0.38, color: porcelain, position: SCNVector3(7.02, 0.26, 6.12)))
        root.addChildNode(sphere(radius: 0.16, color: porcelain, position: SCNVector3(7.02, 0.53, 6.12), scale: SCNVector3(1.0, 0.35, 1.16)))
        root.addChildNode(box(width: 0.06, height: 0.65, length: 0.42, color: partition, position: SCNVector3(6.78, 0.78, 6.12)))
        root.addChildNode(box(width: 0.06, height: 1.1, length: 0.34, color: NSColor(calibratedRed: 0.36, green: 0.5, blue: 0.62, alpha: 1), position: SCNVector3(6.46, 0.78, 6.12)))
        root.addChildNode(sphere(radius: 0.018, color: NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(6.42, 0.78, 5.99)))
        return root
    }

    private func makeCorridorNoticeArea() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.055, height: 0.7, length: 1.25, color: NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.22, alpha: 1), position: SCNVector3(6.56, 1.62, -2.2)))
        root.addChildNode(box(width: 0.06, height: 0.52, length: 1.04, color: NSColor(calibratedRed: 0.9, green: 0.86, blue: 0.64, alpha: 1), position: SCNVector3(6.525, 1.62, -2.2)))
        root.addChildNode(makeText("年级通知", size: 0.052, color: NSColor(calibratedWhite: 0.08, alpha: 1), position: SCNVector3(6.49, 1.82, -2.58)))
        root.addChildNode(makeText("保持安静", size: 0.048, color: NSColor(calibratedWhite: 0.08, alpha: 1), position: SCNVector3(6.49, 1.56, -2.58)))
        root.addChildNode(box(width: 0.058, height: 0.34, length: 0.62, color: NSColor(calibratedRed: 0.15, green: 0.48, blue: 0.34, alpha: 1), position: SCNVector3(6.53, 2.12, 1.8)))
        root.addChildNode(makeText("EXIT", size: 0.08, color: NSColor(calibratedWhite: 0.96, alpha: 1), position: SCNVector3(6.49, 2.1, 1.55)))
        return root
    }

    private func makeWaterDispenser() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.34, height: 0.78, length: 0.32, color: NSColor(calibratedWhite: 0.86, alpha: 1), position: SCNVector3(6.38, 0.42, 3.9)))
        root.addChildNode(box(width: 0.24, height: 0.24, length: 0.25, color: NSColor(calibratedRed: 0.4, green: 0.72, blue: 0.95, alpha: 1), position: SCNVector3(6.36, 0.94, 3.9)))
        root.addChildNode(box(width: 0.035, height: 0.08, length: 0.045, color: NSColor(calibratedRed: 0.84, green: 0.16, blue: 0.12, alpha: 1), position: SCNVector3(6.18, 0.58, 3.83)))
        root.addChildNode(box(width: 0.035, height: 0.08, length: 0.045, color: NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.72, alpha: 1), position: SCNVector3(6.18, 0.58, 3.97)))
        return root
    }

    private func makeTrashBin() -> SCNNode {
        let root = SCNNode()
        let body = SCNCylinder(radius: 0.16, height: 0.46)
        body.radialSegmentCount = 14
        body.firstMaterial = material(NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.28, alpha: 1))
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(6.32, 0.23, -6.15)
        root.addChildNode(bodyNode)
        root.addChildNode(box(width: 0.28, height: 0.04, length: 0.28, color: NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.18, alpha: 1), position: SCNVector3(6.32, 0.48, -6.15)))
        return root
    }

    private func makeWindowLayer() -> SCNNode {
        let root = SCNNode()
        for z in [-2.9, 1.2] {
            root.addChildNode(glassPane(width: 0.035, height: 1.05, length: 1.4, position: SCNVector3(-3.955, 1.7, Float(z))))
            root.addChildNode(windowFrame(at: SCNVector3(-3.97, 1.7, Float(z))))
        }
        for z in [-0.85, 1.2, 2.75] {
            root.addChildNode(glassPane(width: 0.035, height: 1.32, length: 1.15, position: SCNVector3(3.955, 1.78, Float(z))))
            root.addChildNode(windowFrame(at: SCNVector3(3.97, 1.78, Float(z)), height: 1.38, length: 1.21))
        }

        outsideSkyNode.addChildNode(box(width: 0.03, height: 1.5, length: 6.4, color: NSColor(calibratedRed: 0.45, green: 0.72, blue: 0.96, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideSkyNode.addChildNode(box(width: 0.035, height: 0.42, length: 0.7, color: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.28, alpha: 1), position: SCNVector3(-0.008, -0.38, -2.1)))
        outsideSkyNode.addChildNode(box(width: 0.035, height: 0.62, length: 0.85, color: NSColor(calibratedRed: 0.16, green: 0.2, blue: 0.26, alpha: 1), position: SCNVector3(-0.008, -0.28, -0.9)))
        outsideSkyNode.addChildNode(box(width: 0.035, height: 0.52, length: 0.72, color: NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.24, alpha: 1), position: SCNVector3(-0.008, -0.33, 0.55)))
        outsideSkyNode.addChildNode(box(width: 0.035, height: 0.68, length: 0.9, color: NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.22, alpha: 1), position: SCNVector3(-0.008, -0.24, 1.85)))
        outsideSkyNode.position = SCNVector3(-4.08, 1.75, -0.85)
        root.addChildNode(outsideSkyNode)

        outsideCloudNode.addChildNode(box(width: 0.032, height: 0.16, length: 0.9, color: NSColor(calibratedWhite: 0.95, alpha: 0.72), position: SCNVector3(0, 0.28, -1.7)))
        outsideCloudNode.addChildNode(box(width: 0.032, height: 0.12, length: 1.15, color: NSColor(calibratedWhite: 0.9, alpha: 0.66), position: SCNVector3(0, 0.1, 1.1)))
        outsideCloudNode.position = SCNVector3(-4.115, 1.78, -0.85)
        root.addChildNode(outsideCloudNode)

        outsideSunNode.addChildNode(sphere(radius: 0.13, color: NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.28, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideSunNode.position = SCNVector3(-4.13, 2.13, -2.2)
        root.addChildNode(outsideSunNode)

        outsideMoonNode.addChildNode(sphere(radius: 0.1, color: NSColor(calibratedRed: 0.88, green: 0.92, blue: 1.0, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideMoonNode.position = SCNVector3(-4.13, 2.22, 1.7)
        outsideMoonNode.opacity = 0
        root.addChildNode(outsideMoonNode)

        for z in stride(from: -2.9, through: 2.5, by: 0.45) {
            let rain = box(width: 0.018, height: 0.32, length: 0.012, color: NSColor(calibratedRed: 0.68, green: 0.82, blue: 1.0, alpha: 0.58), position: SCNVector3(0, 0, Float(z)))
            rain.eulerAngles.x = -0.22
            outsideRainNode.addChildNode(rain)
        }
        outsideRainNode.position = SCNVector3(-4.14, 1.78, -0.15)
        outsideRainNode.opacity = 0
        root.addChildNode(outsideRainNode)

        outsideLampNode.addChildNode(box(width: 0.022, height: 0.72, length: 0.08, color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1), position: SCNVector3(0, 0, 0)))
        outsideLampNode.addChildNode(box(width: 0.024, height: 0.18, length: 0.9, color: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.18, alpha: 1), position: SCNVector3(0, 0.28, 0)))
        outsideLampNode.position = SCNVector3(-4.14, 1.42, 2.45)
        outsideLampNode.opacity = 0.18
        root.addChildNode(outsideLampNode)
        return root
    }

    private func glassPane(width: CGFloat, height: CGFloat, length: CGFloat, position: SCNVector3) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.004)
        let glass = SCNMaterial()
        glass.diffuse.contents = NSColor(calibratedRed: 0.68, green: 0.88, blue: 1.0, alpha: 0.2)
        glass.specular.contents = NSColor.white
        glass.emission.contents = NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.5, alpha: 0.05)
        glass.transparency = 0.28
        glass.blendMode = .alpha
        glass.isDoubleSided = true
        geometry.firstMaterial = glass
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private func windowFrame(at position: SCNVector3, height: CGFloat = 1.12, length: CGFloat = 1.46) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let frameColor = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.72, alpha: 1)
        root.addChildNode(box(width: 0.055, height: height, length: 0.04, color: frameColor, position: SCNVector3(0, 0, -Float(length / 2))))
        root.addChildNode(box(width: 0.055, height: height, length: 0.04, color: frameColor, position: SCNVector3(0, 0, Float(length / 2))))
        root.addChildNode(box(width: 0.055, height: 0.04, length: length, color: frameColor, position: SCNVector3(0, Float(height / 2), 0)))
        root.addChildNode(box(width: 0.055, height: 0.04, length: length, color: frameColor, position: SCNVector3(0, -Float(height / 2), 0)))
        root.addChildNode(box(width: 0.058, height: height - 0.06, length: 0.025, color: frameColor, position: SCNVector3(0, 0, 0)))
        return root
    }

    private func makeDoors() -> SCNNode {
        let root = SCNNode()
        let doorColor = NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.15, alpha: 1)
        let trimColor = NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.08, alpha: 1)
        let knobColor = NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.28, alpha: 1)

        addDoorFrame(to: root, centerZ: -4.65, color: trimColor)
        configureDoorLeaf(frontDoorLeftNode, doorColor: doorColor, knobColor: knobColor, knobOffsetZ: 0.13)
        configureDoorLeaf(frontDoorRightNode, doorColor: doorColor, knobColor: knobColor, knobOffsetZ: -0.13)
        root.addChildNode(frontDoorLeftNode)
        root.addChildNode(frontDoorRightNode)

        addDoorFrame(to: root, centerZ: 4.65, color: trimColor)
        configureDoorLeaf(rearDoorLeftNode, doorColor: doorColor, knobColor: knobColor, knobOffsetZ: 0.13)
        configureDoorLeaf(rearDoorRightNode, doorColor: doorColor, knobColor: knobColor, knobOffsetZ: -0.13)
        root.addChildNode(rearDoorLeftNode)
        root.addChildNode(rearDoorRightNode)
        updateDoors(frontOpen: false, rearOpen: false)
        return root
    }

    private func configureDoorLeaf(_ node: SCNNode, doorColor: NSColor, knobColor: NSColor, knobOffsetZ: Float) {
        node.addChildNode(box(width: 0.08, height: 2.0, length: 0.37, color: doorColor, position: SCNVector3Zero))
        node.addChildNode(sphere(radius: 0.028, color: knobColor, position: SCNVector3(-0.055, 0.02, knobOffsetZ)))
    }

    private func addDoorFrame(to root: SCNNode, centerZ: Float, color: NSColor) {
        root.addChildNode(box(width: 0.1, height: 2.14, length: 0.06, color: color, position: SCNVector3(4.0, 1.07, centerZ - 0.45)))
        root.addChildNode(box(width: 0.1, height: 2.14, length: 0.06, color: color, position: SCNVector3(4.0, 1.07, centerZ + 0.45)))
        root.addChildNode(box(width: 0.1, height: 0.08, length: 0.96, color: color, position: SCNVector3(4.0, 2.12, centerZ)))
    }

    private func updateDoors(game: GameManager) {
        updateDoors(frontOpen: game.frontDoorOpen, rearOpen: game.rearDoorOpen)
    }

    private func updateDoors(frontOpen: Bool, rearOpen: Bool) {
        updateDoorLeaves(leftNode: frontDoorLeftNode, rightNode: frontDoorRightNode, isOpen: frontOpen, centerZ: Float(StudentDoor.front.centerZ))
        updateDoorLeaves(leftNode: rearDoorLeftNode, rightNode: rearDoorRightNode, isOpen: rearOpen, centerZ: Float(StudentDoor.rear.centerZ))
    }

    private func updateDoorLeaves(leftNode: SCNNode, rightNode: SCNNode, isOpen: Bool, centerZ: Float) {
        if isOpen {
            leftNode.position = SCNVector3(4.31, 1.0, centerZ - 0.43)
            leftNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            rightNode.position = SCNVector3(4.31, 1.0, centerZ + 0.43)
            rightNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        } else {
            leftNode.position = SCNVector3(4.02, 1.0, centerZ - 0.19)
            leftNode.eulerAngles = SCNVector3Zero
            rightNode.position = SCNVector3(4.02, 1.0, centerZ + 0.19)
            rightNode.eulerAngles = SCNVector3Zero
        }
    }

    private func updatePlayerLocker(game: GameManager) {
        updatePlayerLocker(isOpen: game.playerLockerOpen)
    }

    private func updatePlayerLocker(isOpen: Bool) {
        if isOpen {
            playerLockerDoorNode.position = SCNVector3(6.19, 0.63, -3.76)
            playerLockerDoorNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        } else {
            playerLockerDoorNode.position = SCNVector3(6.3, 0.63, -3.9)
            playerLockerDoorNode.eulerAngles = SCNVector3Zero
        }
    }

    private func makeFurniture() -> SCNNode {
        let root = SCNNode()
        for row in 0..<5 {
            for column in 0..<4 {
                let x = Float(column) * 1.2 - 2.4
                let z = Float(row) * 1.45 - 2.25
                let isPlayerSeat = row == 2 && column == 1
                root.addChildNode(makeDesk(at: SCNVector3(x, 0, z), isPlayer: isPlayerSeat))
                let chair = makeChair(at: SCNVector3(x, 0, z + 0.55))
                if isPlayerSeat {
                    chair.name = "playerGroundedChair"
                }
                root.addChildNode(chair)
            }
        }
        return root
    }

    private func makeInteriorDetails() -> SCNNode {
        let root = SCNNode()
        let seamColor = NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.22, alpha: 1)
        for x in stride(from: -3.0, through: 3.0, by: 1.0) {
            root.addChildNode(box(width: 0.012, height: 0.006, length: 11.4, color: seamColor, position: SCNVector3(Float(x), 0.006, 0)))
        }
        for z in stride(from: -5.0, through: 5.0, by: 1.0) {
            root.addChildNode(box(width: 7.4, height: 0.006, length: 0.012, color: seamColor, position: SCNVector3(0, 0.007, Float(z))))
        }

        let baseboard = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.24, alpha: 1)
        root.addChildNode(box(width: 7.8, height: 0.12, length: 0.035, color: baseboard, position: SCNVector3(0, 0.08, -5.96)))
        root.addChildNode(box(width: 7.8, height: 0.12, length: 0.035, color: baseboard, position: SCNVector3(0, 0.08, 5.96)))
        root.addChildNode(box(width: 0.035, height: 0.12, length: 11.8, color: baseboard, position: SCNVector3(-3.96, 0.08, 0)))

        root.addChildNode(makeNoticeBoard())
        root.addChildNode(makeCleaningCorner())
        root.addChildNode(makeCeilingLights())
        root.addChildNode(makeRightStorageCabinet())
        root.addChildNode(makeRearNewspaperWall())
        root.addChildNode(makeAirConditioningDetails())
        return root
    }

    private func makeNoticeBoard() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.045, height: 0.92, length: 1.55, color: NSColor(calibratedRed: 0.5, green: 0.28, blue: 0.16, alpha: 1), position: SCNVector3(-3.92, 1.72, 3.75)))
        root.addChildNode(box(width: 0.048, height: 0.72, length: 1.35, color: NSColor(calibratedRed: 0.86, green: 0.78, blue: 0.52, alpha: 1), position: SCNVector3(-3.895, 1.72, 3.75)))
        for (index, z) in [3.28, 3.58, 3.92, 4.18].enumerated() {
            let paperColor = index % 2 == 0
                ? NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.9, alpha: 1)
                : NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1)
            root.addChildNode(box(width: 0.052, height: 0.28, length: 0.22, color: paperColor, position: SCNVector3(-3.86, 1.82 - Float(index % 2) * 0.22, Float(z))))
        }
        root.addChildNode(makeText("值日表", size: 0.055, color: NSColor(calibratedWhite: 0.08, alpha: 1), position: SCNVector3(-3.84, 2.14, 3.2)))
        return root
    }

    private func makeCleaningCorner() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.42, height: 0.32, length: 0.34, color: NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.36, alpha: 1), position: SCNVector3(-3.58, 0.16, 5.38)))
        root.addChildNode(box(width: 0.12, height: 0.72, length: 0.08, color: NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.22, alpha: 1), position: SCNVector3(-3.74, 0.62, 5.12)))
        root.addChildNode(box(width: 0.035, height: 1.18, length: 0.035, color: NSColor(calibratedRed: 0.5, green: 0.34, blue: 0.2, alpha: 1), position: SCNVector3(-3.52, 0.74, 5.18)))
        root.addChildNode(box(width: 0.22, height: 0.1, length: 0.04, color: NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.56, alpha: 1), position: SCNVector3(-3.52, 1.32, 5.18)))
        return root
    }

    private func makeCeilingLights() -> SCNNode {
        let root = SCNNode()
        for z in [-3.2, 0.0, 3.2] {
            let lightPanel = box(width: 1.35, height: 0.025, length: 0.22, color: NSColor(calibratedWhite: 0.96, alpha: 1), position: SCNVector3(0, 3.47, Float(z)))
            lightPanel.geometry?.firstMaterial?.emission.contents = NSColor(calibratedWhite: 0.72, alpha: 1)
            root.addChildNode(lightPanel)
            root.addChildNode(box(width: 1.46, height: 0.018, length: 0.03, color: NSColor(calibratedWhite: 0.62, alpha: 1), position: SCNVector3(0, 3.45, Float(z) - 0.14)))
            root.addChildNode(box(width: 1.46, height: 0.018, length: 0.03, color: NSColor(calibratedWhite: 0.62, alpha: 1), position: SCNVector3(0, 3.45, Float(z) + 0.14)))
        }
        return root
    }

    private func makeRightStorageCabinet() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.08, height: 1.55, length: 0.78, color: NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.3, alpha: 1), position: SCNVector3(3.92, 0.9, -2.35)))
        for (index, y) in [0.44, 0.78, 1.12, 1.46].enumerated() {
            root.addChildNode(box(width: 0.09, height: 0.035, length: 0.72, color: NSColor(calibratedRed: 0.06, green: 0.1, blue: 0.13, alpha: 1), position: SCNVector3(3.86, Float(y), -2.35)))
            root.addChildNode(box(width: 0.11, height: 0.16, length: 0.11, color: index % 2 == 0 ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.72, alpha: 1) : NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.18, alpha: 1), position: SCNVector3(3.8, Float(y + 0.09), -2.58)))
            root.addChildNode(box(width: 0.11, height: 0.2, length: 0.1, color: index % 2 == 0 ? NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.62, alpha: 1) : NSColor(calibratedRed: 0.12, green: 0.46, blue: 0.42, alpha: 1), position: SCNVector3(3.8, Float(y + 0.1), -2.22)))
        }
        root.addChildNode(makeText("备品柜", size: 0.045, color: NSColor(calibratedWhite: 0.9, alpha: 1), position: SCNVector3(3.78, 1.72, -2.7)))
        return root
    }

    private func makeRearNewspaperWall() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 2.4, height: 0.78, length: 0.045, color: NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.14, alpha: 1), position: SCNVector3(-1.15, 1.78, 5.92)))
        root.addChildNode(makeText("班级黑板报", size: 0.078, color: NSColor(calibratedWhite: 0.88, alpha: 1), position: SCNVector3(-2.18, 2.02, 5.86)))
        for (index, x) in [-1.92, -1.42, -0.92, -0.42].enumerated() {
            let paperColor = index % 2 == 0 ? NSColor(calibratedRed: 0.92, green: 0.9, blue: 0.76, alpha: 1) : NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.92, alpha: 1)
            root.addChildNode(box(width: 0.34, height: 0.26, length: 0.02, color: paperColor, position: SCNVector3(Float(x), 1.68, 5.86)))
            root.addChildNode(box(width: 0.26, height: 0.035, length: 0.022, color: NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.62, alpha: 1), position: SCNVector3(Float(x), 1.78, 5.84)))
        }
        return root
    }

    private func makeAirConditioningDetails() -> SCNNode {
        let root = SCNNode()
        for z in [-3.15, 2.55] {
            root.addChildNode(box(width: 0.08, height: 0.26, length: 0.82, color: NSColor(calibratedWhite: 0.86, alpha: 1), position: SCNVector3(3.93, 2.62, Float(z))))
            root.addChildNode(box(width: 0.085, height: 0.035, length: 0.66, color: NSColor(calibratedWhite: 0.62, alpha: 1), position: SCNVector3(3.875, 2.52, Float(z))))
            root.addChildNode(box(width: 0.035, height: 0.38, length: 0.035, color: NSColor(calibratedWhite: 0.72, alpha: 1), position: SCNVector3(3.91, 2.16, Float(z) + 0.34)))
        }
        root.addChildNode(box(width: 0.04, height: 0.42, length: 0.24, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(3.92, 1.45, -3.18)))
        for (index, y) in [1.56, 1.44, 1.32].enumerated() {
            root.addChildNode(box(width: 0.045, height: 0.05, length: 0.05, color: index == 0 ? NSColor(calibratedRed: 0.08, green: 0.44, blue: 0.48, alpha: 1) : NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1), position: SCNVector3(3.885, Float(y), -3.18)))
        }
        return root
    }

    private func makeDesk(at position: SCNVector3, isPlayer: Bool) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let topColor = isPlayer ? NSColor(calibratedRed: 0.74, green: 0.62, blue: 0.46, alpha: 1) : NSColor(calibratedRed: 0.62, green: 0.48, blue: 0.34, alpha: 1)
        root.addChildNode(box(width: 0.82, height: 0.08, length: 0.55, color: topColor, position: SCNVector3(0, 0.72, 0)))
        root.addChildNode(box(width: 0.74, height: 0.035, length: 0.06, color: NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.11, alpha: 1), position: SCNVector3(0, 0.63, -0.25)))
        if isPlayer == false {
            root.addChildNode(makeDeskSupplies(seed: Int((position.x + 4) * 10 + (position.z + 6) * 7)))
        }
        for x in [-0.34, 0.34] {
            for z in [-0.2, 0.2] {
                root.addChildNode(box(width: 0.05, height: 0.68, length: 0.05, color: NSColor.darkGray, position: SCNVector3(Float(x), 0.36, Float(z))))
            }
        }
        return root
    }

    private func makeDeskSupplies(seed: Int) -> SCNNode {
        let root = SCNNode()
        let bookColors = [
            NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.66, alpha: 1),
            NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.46, blue: 0.28, alpha: 1)
        ]
        let stackCount = 1 + seed % 3
        for index in 0..<stackCount {
            root.addChildNode(box(width: 0.3, height: 0.026, length: 0.15, color: bookColors[(seed + index) % bookColors.count], position: SCNVector3(-0.18 + Float(index) * 0.03, 0.61 + Float(index) * 0.026, -0.25)))
        }
        if seed % 2 == 0 {
            root.addChildNode(box(width: 0.26, height: 0.012, length: 0.035, color: NSColor(calibratedRed: 0.1, green: 0.14, blue: 0.32, alpha: 1), position: SCNVector3(0.16, 0.615, -0.18)))
        } else {
            root.addChildNode(box(width: 0.22, height: 0.04, length: 0.11, color: NSColor(calibratedRed: 0.78, green: 0.68, blue: 0.42, alpha: 1), position: SCNVector3(0.18, 0.615, -0.18)))
        }
        return root
    }

    private func makeChair(at position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        root.addChildNode(box(width: 0.52, height: 0.06, length: 0.46, color: NSColor(calibratedRed: 0.28, green: 0.24, blue: 0.22, alpha: 1), position: SCNVector3(0, 0.45, 0)))
        root.addChildNode(box(width: 0.52, height: 0.5, length: 0.06, color: NSColor(calibratedRed: 0.25, green: 0.21, blue: 0.19, alpha: 1), position: SCNVector3(0, 0.75, 0.22)))
        let legColor = NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.17, alpha: 1)
        for (index, offset) in [(-0.2, -0.16), (0.2, -0.16), (-0.2, 0.16), (0.2, 0.16)].enumerated() {
            let leg = box(width: 0.045, height: 0.44, length: 0.045, color: legColor, position: SCNVector3(Float(offset.0), 0.22, Float(offset.1)))
            leg.name = "chairLeg_\(index)"
            root.addChildNode(leg)
        }
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
        let uniformColor = studentUniformColor(seed: seed, profile: profile, fallback: shirtColors[seed % shirtColors.count])
        root.addChildNode(makeStudentBody(uniformColor: uniformColor, seed: seed, profile: profile))

        let head = sphere(radius: 0.15, color: skinColor(seed), position: SCNVector3(0, 0.88, 0))
        head.name = "head"
        head.addChildNode(makeStudentFace(seed: seed, profile: profile))
        if profile?.orderliness ?? 0 > 72 {
            head.addChildNode(makeFaceGlasses())
        }
        root.addChildNode(head)

        let hair = sphere(radius: 0.152, color: NSColor(calibratedWhite: 0.04 + CGFloat(seed % 3) * 0.04, alpha: 1), position: SCNVector3(0, 0.98, 0.02), scale: hairScale(seed: seed, profile: profile))
        hair.name = "hair"
        root.addChildNode(hair)

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
        root.addChildNode(makeTeacherBody())
        let head = sphere(radius: 0.15, color: NSColor(calibratedRed: 0.9, green: 0.78, blue: 0.66, alpha: 1), position: SCNVector3(0, 1.28, 0))
        head.addChildNode(makeTeacherFace())
        root.addChildNode(head)
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
        let root = playerSeatedPropsNode
        root.name = "playerSeatedFirstPersonProps"
        homeworkSheetNode.addChildNode(box(width: 0.58, height: 0.018, length: 0.48, color: NSColor(calibratedWhite: 0.94, alpha: 1), position: SCNVector3(0, 0, 0)))
        homeworkSheetNode.addChildNode(box(width: 0.02, height: 0.004, length: 0.44, color: NSColor(calibratedRed: 0.76, green: 0.1, blue: 0.12, alpha: 1), position: SCNVector3(-0.25, 0.014, 0)))
        for index in 0..<7 {
            let z = -0.18 + Float(index) * 0.06
            let lineWidth = CGFloat(index % 3 == 0 ? 0.4 : 0.46)
            homeworkSheetNode.addChildNode(box(width: lineWidth, height: 0.004, length: 0.012, color: NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.78, alpha: 1), position: SCNVector3(0.03, 0.016, z)))
        }
        homeworkSheetNode.position = SCNVector3(-0.6, 0.79, 1.43)
        homeworkSheetNode.eulerAngles.y = 0.02
        root.addChildNode(homeworkSheetNode)

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
        penNode.addChildNode(capsule(radius: 0.012, height: 0.38, color: NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.38, alpha: 1), position: SCNVector3(0.03, -0.01, -0.04), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))
        penNode.addChildNode(sphere(radius: 0.018, color: NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.025, alpha: 1), position: SCNVector3(-0.17, -0.01, -0.04)))
        penNode.opacity = 0.45
        rightHandNode.addChildNode(penNode)
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
        root.addChildNode(makeText("55-SEAT CLASSROOM", size: 0.075, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(-0.72, 2.43, -5.9)))
        root.addChildNode(makeText("晚自习", size: 0.22, color: NSColor(calibratedWhite: 0.9, alpha: 1), position: SCNVector3(-1.75, 2.24, -5.9)))
        root.addChildNode(makeText("今日目标：完成作业  管理压力  允许求助", size: 0.075, color: NSColor(calibratedWhite: 0.82, alpha: 1), position: SCNVector3(-1.78, 1.98, -5.9)))
        root.addChildNode(makeText("抬头会暴露，低头会失去信息。", size: 0.068, color: NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.78, alpha: 1), position: SCNVector3(-1.78, 1.8, -5.9)))
        blackboardStatusNode.position = SCNVector3(-1.78, 1.62, -5.9)
        root.addChildNode(blackboardStatusNode)
        return root
    }

    private func makeSmartFrontWallDetails() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(makeTouchPanel(x: -3.08, title: "课程"))
        root.addChildNode(makeTouchPanel(x: 3.08, title: "数据"))

        root.addChildNode(box(width: 1.0, height: 0.5, length: 0.06, color: NSColor(calibratedRed: 0.78, green: 0.71, blue: 0.58, alpha: 1), position: SCNVector3(0, 0.72, -4.62)))
        root.addChildNode(box(width: 0.56, height: 0.24, length: 0.065, color: NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.055, alpha: 1), position: SCNVector3(0, 0.72, -4.57)))
        root.addChildNode(box(width: 0.42, height: 0.15, length: 0.07, color: NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.22, alpha: 1), position: SCNVector3(0, 0.76, -4.535)))
        root.addChildNode(box(width: 0.74, height: 0.035, length: 0.05, color: NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.1, alpha: 1), position: SCNVector3(0, 1.0, -4.55)))

        let portColors = [
            NSColor(calibratedRed: 0.1, green: 0.42, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.64, alpha: 1),
            NSColor(calibratedWhite: 0.84, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.18, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.45, blue: 0.14, alpha: 1)
        ]
        for (index, color) in portColors.enumerated() {
            root.addChildNode(box(width: 0.075, height: 0.055, length: 0.075, color: color, position: SCNVector3(-0.24 + Float(index) * 0.12, 0.58, -4.53)))
        }

        root.addChildNode(box(width: 2.6, height: 0.035, length: 0.18, color: NSColor(calibratedRed: 0.24, green: 0.22, blue: 0.2, alpha: 1), position: SCNVector3(0, 0.035, -4.92)))
        root.addChildNode(box(width: 0.08, height: 0.035, length: 1.5, color: NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.16, alpha: 1), position: SCNVector3(-1.2, 0.04, -4.25)))
        root.addChildNode(box(width: 0.08, height: 0.035, length: 1.5, color: NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.16, alpha: 1), position: SCNVector3(1.2, 0.04, -4.25)))
        return root
    }

    private func makeTouchPanel(x: Float, title: String) -> SCNNode {
        let root = SCNNode()
        root.addChildNode(box(width: 0.82, height: 0.94, length: 0.055, color: NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.12, alpha: 1), position: SCNVector3(x, 1.9, -5.91)))
        root.childNodes.last?.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.0, green: 0.18, blue: 0.26, alpha: 1)
        root.addChildNode(makeText(title, size: 0.065, color: NSColor(calibratedRed: 0.72, green: 0.92, blue: 1.0, alpha: 1), position: SCNVector3(x - 0.32, 2.24, -5.86)))
        for index in 0..<4 {
            root.addChildNode(box(width: 0.46 - CGFloat(index) * 0.05, height: 0.035, length: 0.025, color: NSColor(calibratedRed: 0.1 + CGFloat(index) * 0.08, green: 0.45, blue: 0.62, alpha: 1), position: SCNVector3(x - 0.12, 2.08 - Float(index) * 0.13, -5.85)))
        }
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

    private func updateClock(game: GameManager) {
        let startMinutes = 18 * 60 + 30
        let totalMinutes = Double(startMinutes + game.elapsedMinutes)
        let minuteAngle = -CGFloat((totalMinutes / 60) * 2 * Double.pi)
        let hourAngle = -CGFloat((totalMinutes / 720) * 2 * Double.pi)
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
        let progress = max(0, min(1, Double(game.elapsedMinutes) / Double(max(1, game.settings.totalMinutes))))
        let skyColor: NSColor
        let ambientColor: NSColor
        let lampOpacity: CGFloat

        switch period {
        case .first:
            skyColor = NSColor(calibratedRed: 0.58, green: 0.78, blue: 0.96, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.78, green: 0.8, blue: 0.76, alpha: 1)
            lampOpacity = 0.12
        case .breakOne, .breakTwo:
            skyColor = NSColor(calibratedRed: 0.72, green: 0.5, blue: 0.34, alpha: 1)
            ambientColor = NSColor(calibratedRed: 0.74, green: 0.7, blue: 0.62, alpha: 1)
            lampOpacity = 0.38
        case .second:
            skyColor = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.3, alpha: 1)
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
        outsideCloudNode.opacity = CGFloat((0.18 + progress * 0.72 + (lightLevel < 0.6 ? 0.22 : 0)).clamped(to: 0.18...0.95))
        outsideSunNode.opacity = CGFloat((1.0 - progress * 2.2).clamped(to: 0...1))
        outsideSunNode.position.y = CGFloat(2.13 - progress * 0.9)
        outsideMoonNode.opacity = CGFloat(((progress - 0.42) * 1.9).clamped(to: 0...0.88))
        outsideMoonNode.position.y = CGFloat(1.95 + progress * 0.38)
        let rainy = progress > 0.46 || lightLevel < 0.6
        outsideRainNode.opacity = rainy ? CGFloat((0.2 + progress * 0.48).clamped(to: 0.28...0.72)) : 0
        if rainy && outsideRainNode.action(forKey: "rain_fall") == nil {
            outsideRainNode.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: -0.22, z: 0.04, duration: 0.34),
                .moveBy(x: 0, y: 0.22, z: -0.04, duration: 0)
            ])), forKey: "rain_fall")
        } else if !rainy {
            outsideRainNode.removeAction(forKey: "rain_fall")
        }
        outsideLampNode.opacity = lightLevel < 0.6 ? 0.95 : lampOpacity
        outsideLampNode.childNodes.forEach {
            $0.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.18, alpha: lightLevel < 0.6 ? 0.85 : 0.38)
        }
    }

    private func updateDeskState(game: GameManager) {
        let shouldShowSeatedProps = game.viewMode == .student && game.player.posture == .seated && game.freeRoam.isActive == false
        playerSeatedPropsNode.isHidden = shouldShowSeatedProps == false
        guard shouldShowSeatedProps else {
            rightHandNode.removeAction(forKey: "write_homework")
            homeworkSheetNode.removeAction(forKey: "paper_focus")
            leftLegNode.removeAction(forKey: "bladder_fidget")
            rightLegNode.removeAction(forKey: "bladder_fidget")
            seatTensionNode.removeAction(forKey: "seat_tension")
            return
        }

        let progress = max(0.02, min(1.0, game.player.homework / 100))
        homeworkProgressNode.scale = SCNVector3(Float(progress) * 0.46, 1, 1)
        homeworkProgressNode.opacity = game.cameraPose == .desk ? 1.0 : 0.62
        homeworkSheetNode.opacity = game.cameraPose == .desk || game.audioCues.first?.kind == .paper ? 1.0 : 0.72

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
        penNode.opacity = phoneActive || snackActive ? 0.18 : (game.cameraPose == .desk || paperActive ? 1.0 : 0.52)
        leftHandNode.position = game.cameraPose == .desk
            ? SCNVector3(-0.85, 0.835, 1.52)
            : SCNVector3(-0.86, 0.83, 1.62)
        rightHandNode.position = paperActive
            ? SCNVector3(-0.45, 0.842, 1.38)
            : (game.cameraPose == .desk ? SCNVector3(-0.43, 0.835, 1.48) : SCNVector3(-0.38, 0.83, 1.6))

        if paperActive {
            leftHandNode.eulerAngles.x = 0.04
            leftHandNode.eulerAngles.z = 0.14 + bodyTension * 0.04
            rightHandNode.eulerAngles.x = -0.18
            rightHandNode.eulerAngles.z = -0.24
            if rightHandNode.action(forKey: "write_homework") == nil {
                let stroke = SCNAction.sequence([
                    .moveBy(x: 0.12, y: 0.002, z: -0.012, duration: 0.12),
                    .moveBy(x: -0.1, y: -0.002, z: 0.022, duration: 0.1),
                    .moveBy(x: 0.07, y: 0, z: -0.01, duration: 0.09),
                    .moveBy(x: -0.09, y: 0, z: 0, duration: 0.12)
                ])
                rightHandNode.runAction(.repeat(stroke, count: 5), forKey: "write_homework")
                homeworkSheetNode.runAction(.sequence([
                    .fadeOpacity(to: 1.0, duration: 0.05),
                    .wait(duration: 0.8),
                    .fadeOpacity(to: game.cameraPose == .desk ? 1.0 : 0.72, duration: 0.4)
                ]), forKey: "paper_focus")
            }
        } else {
            rightHandNode.removeAction(forKey: "write_homework")
            leftHandNode.eulerAngles.x = phoneActive ? -0.08 : stressTilt + bodyTension * 0.04
            leftHandNode.eulerAngles.z = phoneActive ? -0.2 : stressTilt + bodyTension * 0.05
            rightHandNode.eulerAngles.x = snackActive ? -0.34 : (phoneActive ? -0.2 : -stressTilt - bodyTension * 0.04)
            rightHandNode.eulerAngles.z = snackActive ? 0.34 : (phoneActive ? 0.24 : -stressTilt - bodyTension * 0.05)
        }

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

    var playerSeatedPropsVisible: Bool {
        playerSeatedPropsNode.isHidden == false
    }

    var playerGroundedChairVisible: Bool {
        scene.rootNode.childNode(withName: "playerGroundedChair", recursively: true)?.isHidden == false
    }

    var playerGroundedChairLegCount: Int {
        guard let chair = scene.rootNode.childNode(withName: "playerGroundedChair", recursively: true) else { return 0 }
        return chair.childNodes.filter { $0.name?.hasPrefix("chairLeg_") == true }.count
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
            node.eulerAngles.x = -0.03
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
        let spinDuration: Double
        switch game.currentPeriod {
        case .first:
            spinDuration = 1.55
        case .breakOne, .breakTwo:
            spinDuration = 1.25
        case .second:
            spinDuration = 0.95
        case .third:
            spinDuration = 0.48
        }
        let adjustedDuration = game.classroomLightLevel < 0.6 ? min(spinDuration, 0.72) : spinDuration
        guard abs(adjustedDuration - lastFanSpinDuration) > 0.02 else {
            for fan in fanNodes {
                fan.opacity = game.currentPeriod == .first ? 0.42 : 0.58
            }
            return
        }
        lastFanSpinDuration = adjustedDuration
        for fan in fanNodes {
            fan.removeAction(forKey: "spin")
            fan.opacity = game.currentPeriod == .first ? 0.42 : 0.58
            fan.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: adjustedDuration)), forKey: "spin")
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

    private func makeStudentBody(uniformColor: NSColor, seed: Int, profile: ClassmateProfile?) -> SCNNode {
        let root = SCNNode()
        let skin = skinColor(seed)
        let shirtLight = uniformColor.blended(withFraction: 0.28, of: .white) ?? uniformColor
        let pantsColor = NSColor(calibratedRed: 0.1, green: 0.13, blue: 0.19, alpha: 1)
        let shoeColor = NSColor(calibratedWhite: 0.045, alpha: 1)

        let neck = capsule(radius: 0.035, height: 0.13, color: skin, position: SCNVector3(0, 0.73, 0))
        root.addChildNode(neck)

        let torso = box(width: 0.29, height: 0.43, length: 0.17, color: uniformColor, position: SCNVector3(0, 0.49, 0))
        torso.name = "body"
        root.addChildNode(torso)
        root.addChildNode(box(width: 0.32, height: 0.07, length: 0.18, color: shirtLight, position: SCNVector3(0, 0.68, -0.005)))
        root.addChildNode(box(width: 0.055, height: 0.11, length: 0.018, color: NSColor(calibratedWhite: 0.94, alpha: 1), position: SCNVector3(-0.035, 0.63, -0.091)))
        root.addChildNode(box(width: 0.055, height: 0.11, length: 0.018, color: NSColor(calibratedWhite: 0.94, alpha: 1), position: SCNVector3(0.035, 0.63, -0.091)))

        let leftArm = capsule(radius: 0.033, height: 0.38, color: uniformColor, position: SCNVector3(-0.21, 0.48, -0.015), rotation: SCNVector4(0, 0, 1, 0.12))
        let rightArm = capsule(radius: 0.033, height: 0.38, color: uniformColor, position: SCNVector3(0.21, 0.48, -0.015), rotation: SCNVector4(0, 0, 1, -0.12))
        root.addChildNode(leftArm)
        root.addChildNode(rightArm)
        root.addChildNode(sphere(radius: 0.04, color: skin, position: SCNVector3(-0.24, 0.27, -0.035), scale: SCNVector3(0.8, 1.0, 0.75)))
        root.addChildNode(sphere(radius: 0.04, color: skin, position: SCNVector3(0.24, 0.27, -0.035), scale: SCNVector3(0.8, 1.0, 0.75)))

        root.addChildNode(capsule(radius: 0.04, height: 0.34, color: pantsColor, position: SCNVector3(-0.07, 0.18, 0)))
        root.addChildNode(capsule(radius: 0.04, height: 0.34, color: pantsColor, position: SCNVector3(0.07, 0.18, 0)))
        root.addChildNode(box(width: 0.11, height: 0.045, length: 0.17, color: shoeColor, position: SCNVector3(-0.07, -0.02, -0.025)))
        root.addChildNode(box(width: 0.11, height: 0.045, length: 0.17, color: shoeColor, position: SCNVector3(0.07, -0.02, -0.025)))

        if profile?.rebelliousness ?? 0 > 72 {
            root.addChildNode(box(width: 0.2, height: 0.025, length: 0.185, color: NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.2, alpha: 1), position: SCNVector3(0, 0.7, -0.015)))
        }
        return root
    }

    private func makeTeacherBody() -> SCNNode {
        let root = SCNNode()
        let skin = NSColor(calibratedRed: 0.9, green: 0.78, blue: 0.66, alpha: 1)
        let jacket = NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.2, alpha: 1)
        let shirt = NSColor(calibratedWhite: 0.9, alpha: 1)
        let pants = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)

        root.addChildNode(capsule(radius: 0.04, height: 0.15, color: skin, position: SCNVector3(0, 1.12, 0)))
        root.addChildNode(box(width: 0.36, height: 0.52, length: 0.18, color: jacket, position: SCNVector3(0, 0.83, 0)))
        root.addChildNode(box(width: 0.16, height: 0.45, length: 0.022, color: shirt, position: SCNVector3(0, 0.85, -0.095)))
        root.addChildNode(box(width: 0.06, height: 0.18, length: 0.024, color: NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.08, alpha: 1), position: SCNVector3(0, 0.92, -0.11)))
        root.addChildNode(box(width: 0.42, height: 0.08, length: 0.19, color: jacket, position: SCNVector3(0, 1.04, 0)))

        let leftArm = capsule(radius: 0.037, height: 0.52, color: jacket, position: SCNVector3(-0.27, 0.82, -0.015), rotation: SCNVector4(0, 0, 1, 0.1))
        let rightArm = capsule(radius: 0.037, height: 0.52, color: jacket, position: SCNVector3(0.27, 0.82, -0.015), rotation: SCNVector4(0, 0, 1, -0.1))
        root.addChildNode(leftArm)
        root.addChildNode(rightArm)
        root.addChildNode(sphere(radius: 0.042, color: skin, position: SCNVector3(-0.3, 0.52, -0.025), scale: SCNVector3(0.8, 1.0, 0.75)))
        root.addChildNode(sphere(radius: 0.042, color: skin, position: SCNVector3(0.3, 0.52, -0.025), scale: SCNVector3(0.8, 1.0, 0.75)))

        root.addChildNode(capsule(radius: 0.045, height: 0.48, color: pants, position: SCNVector3(-0.09, 0.34, 0)))
        root.addChildNode(capsule(radius: 0.045, height: 0.48, color: pants, position: SCNVector3(0.09, 0.34, 0)))
        root.addChildNode(box(width: 0.13, height: 0.05, length: 0.19, color: NSColor(calibratedWhite: 0.035, alpha: 1), position: SCNVector3(-0.09, 0.06, -0.035)))
        root.addChildNode(box(width: 0.13, height: 0.05, length: 0.19, color: NSColor(calibratedWhite: 0.035, alpha: 1), position: SCNVector3(0.09, 0.06, -0.035)))

        let notebook = box(width: 0.18, height: 0.025, length: 0.25, color: NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.34, alpha: 1), position: SCNVector3(-0.36, 0.65, -0.08))
        notebook.eulerAngles.z = -0.28
        root.addChildNode(notebook)
        return root
    }

    private func makeStudentFace(seed: Int, profile: ClassmateProfile?) -> SCNNode {
        let root = SCNNode()
        let eyeColor = NSColor(calibratedWhite: 0.035, alpha: 1)
        let eyeWhite = NSColor(calibratedWhite: 0.94, alpha: 1)
        let browColor = NSColor(calibratedWhite: 0.035 + CGFloat(seed % 2) * 0.025, alpha: 1)
        let mouthColor = NSColor(calibratedRed: 0.36, green: 0.12, blue: 0.11, alpha: 1)
        let noseColor = NSColor(calibratedRed: 0.78, green: 0.55, blue: 0.43, alpha: 1)
        let anxious = (profile?.anxiety ?? 0) > 68
        let calm = (profile?.empathy ?? 0) > 72

        root.addChildNode(sphere(radius: 0.02, color: eyeWhite, position: SCNVector3(-0.052, 0.034, -0.139), scale: SCNVector3(1.25, anxious ? 0.58 : 0.78, 0.2)))
        root.addChildNode(sphere(radius: 0.02, color: eyeWhite, position: SCNVector3(0.052, 0.034, -0.139), scale: SCNVector3(1.25, anxious ? 0.58 : 0.78, 0.2)))
        root.addChildNode(sphere(radius: 0.009, color: eyeColor, position: SCNVector3(-0.052, 0.032, -0.157), scale: SCNVector3(0.85, 1.0, 0.25)))
        root.addChildNode(sphere(radius: 0.009, color: eyeColor, position: SCNVector3(0.052, 0.032, -0.157), scale: SCNVector3(0.85, 1.0, 0.25)))

        let leftBrow = capsule(radius: 0.005, height: 0.065, color: browColor, position: SCNVector3(-0.052, 0.076, -0.15), rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        let rightBrow = capsule(radius: 0.005, height: 0.065, color: browColor, position: SCNVector3(0.052, 0.076, -0.15), rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        leftBrow.eulerAngles.z = CGFloat.pi / 2 + (anxious ? -0.18 : (calm ? 0.06 : 0))
        rightBrow.eulerAngles.z = CGFloat.pi / 2 + (anxious ? 0.18 : (calm ? -0.06 : 0))
        root.addChildNode(leftBrow)
        root.addChildNode(rightBrow)

        root.addChildNode(capsule(radius: 0.006, height: 0.045, color: noseColor, position: SCNVector3(0, 0.004, -0.155)))
        root.addChildNode(sphere(radius: 0.014, color: noseColor, position: SCNVector3(0, -0.022, -0.158), scale: SCNVector3(0.86, 0.72, 0.5)))

        let mouth = capsule(radius: 0.006, height: calm ? 0.078 : 0.066, color: mouthColor, position: SCNVector3(0, -0.062, -0.154), rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        mouth.eulerAngles.z = CGFloat.pi / 2 + (calm ? 0.04 : (anxious ? -0.04 : 0))
        root.addChildNode(mouth)

        if anxious {
            let shadowColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
            root.addChildNode(capsule(radius: 0.004, height: 0.046, color: shadowColor, position: SCNVector3(-0.052, 0.01, -0.154), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))
            root.addChildNode(capsule(radius: 0.004, height: 0.046, color: shadowColor, position: SCNVector3(0.052, 0.01, -0.154), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))
        }

        return root
    }

    private func makeTeacherFace() -> SCNNode {
        let root = SCNNode()
        let eyeColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        let eyeWhite = NSColor(calibratedWhite: 0.94, alpha: 1)
        let browColor = NSColor(calibratedWhite: 0.02, alpha: 1)

        root.addChildNode(sphere(radius: 0.02, color: eyeWhite, position: SCNVector3(-0.055, 0.035, -0.143), scale: SCNVector3(1.35, 0.72, 0.2)))
        root.addChildNode(sphere(radius: 0.02, color: eyeWhite, position: SCNVector3(0.055, 0.035, -0.143), scale: SCNVector3(1.35, 0.72, 0.2)))
        root.addChildNode(sphere(radius: 0.009, color: eyeColor, position: SCNVector3(-0.055, 0.033, -0.16), scale: SCNVector3(0.85, 1, 0.25)))
        root.addChildNode(sphere(radius: 0.009, color: eyeColor, position: SCNVector3(0.055, 0.033, -0.16), scale: SCNVector3(0.85, 1, 0.25)))

        let leftBrow = capsule(radius: 0.005, height: 0.072, color: browColor, position: SCNVector3(-0.056, 0.078, -0.154), rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        let rightBrow = capsule(radius: 0.005, height: 0.072, color: browColor, position: SCNVector3(0.056, 0.078, -0.154), rotation: SCNVector4(0, 0, 1, Float.pi / 2))
        leftBrow.eulerAngles.z = CGFloat.pi / 2 - 0.08
        rightBrow.eulerAngles.z = CGFloat.pi / 2 + 0.08
        root.addChildNode(leftBrow)
        root.addChildNode(rightBrow)

        let noseColor = NSColor(calibratedRed: 0.75, green: 0.52, blue: 0.42, alpha: 1)
        root.addChildNode(capsule(radius: 0.006, height: 0.048, color: noseColor, position: SCNVector3(0, 0.003, -0.158)))
        root.addChildNode(sphere(radius: 0.014, color: noseColor, position: SCNVector3(0, -0.024, -0.161), scale: SCNVector3(0.82, 0.72, 0.48)))
        root.addChildNode(capsule(radius: 0.006, height: 0.074, color: NSColor(calibratedRed: 0.32, green: 0.1, blue: 0.1, alpha: 1), position: SCNVector3(0, -0.064, -0.157), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))
        root.addChildNode(makeFaceGlasses())
        return root
    }

    private func makeFaceGlasses() -> SCNNode {
        let root = SCNNode()
        let frame = NSColor(calibratedWhite: 0.025, alpha: 1)
        root.addChildNode(box(width: 0.064, height: 0.008, length: 0.012, color: frame, position: SCNVector3(-0.055, 0.054, -0.169)))
        root.addChildNode(box(width: 0.064, height: 0.008, length: 0.012, color: frame, position: SCNVector3(0.055, 0.054, -0.169)))
        root.addChildNode(box(width: 0.064, height: 0.008, length: 0.012, color: frame, position: SCNVector3(-0.055, 0.017, -0.169)))
        root.addChildNode(box(width: 0.064, height: 0.008, length: 0.012, color: frame, position: SCNVector3(0.055, 0.017, -0.169)))
        root.addChildNode(box(width: 0.008, height: 0.045, length: 0.012, color: frame, position: SCNVector3(-0.088, 0.035, -0.169)))
        root.addChildNode(box(width: 0.008, height: 0.045, length: 0.012, color: frame, position: SCNVector3(-0.022, 0.035, -0.169)))
        root.addChildNode(box(width: 0.008, height: 0.045, length: 0.012, color: frame, position: SCNVector3(0.022, 0.035, -0.169)))
        root.addChildNode(box(width: 0.008, height: 0.045, length: 0.012, color: frame, position: SCNVector3(0.088, 0.035, -0.169)))
        root.addChildNode(box(width: 0.026, height: 0.007, length: 0.012, color: frame, position: SCNVector3(0, 0.035, -0.171)))
        return root
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
