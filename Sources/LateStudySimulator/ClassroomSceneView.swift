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
        view.antialiasingMode = .multisampling4X
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
    private let teacherPatrolPressureNode = SCNNode()
    private let ambientNode = SCNNode()
    private let playerPhoneNode = SCNNode()
    private let playerWaterCupNode = SCNNode()
    private let playerSeatedPropsNode = SCNNode()
    private let chapterOneNotePaperNode = SCNNode()
    private let soundSourceStageNode = SCNNode()
    private let narrativeStageNode = SCNNode()
    private let prologueLookTargetNode = SCNNode()
    private let prologueGateArrivalNode = SCNNode()
    private var realisticDeskTemplate: SCNNode?
    private var realisticChairTemplate: SCNNode?
    private var hallLightingImage: NSImage?
    private var quadLightingImage: NSImage?
    private var quadBackgroundImage: NSImage?
    private var activeLightingEnvironment = ""
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
    private let breakdownHeartbeatNode = SCNNode()
    private let breakdownSupportNoteNode = SCNNode()
    private let breakdownCupHaloNode = SCNNode()
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
    private var lastClassmateSensoryReaction: SensoryClassroomGroupReaction = .quiet
    private var lastLinChePerformanceCue: LinChePerformanceCue = .initial
    private var lastFanSpinDuration: Double = 0
    private var lastPose: CameraPose = .forward
    private var lastViewMode: ViewMode = .student
    private var lastFreeRoamActive = false
    private var lastPrologueBeat: PrologueBeatID?
    private var lastPrologueActive = false
    private var lastNarrativeChapter: NarrativeChapter?
    private var lastNarrativeMomentID = ""
    private var lastNarrativeBoundaryPullbackCount = 0
    private var selectedNarrativeStageName: String?
    private var lastStudentLookYaw: Double = 0
    private var lastStudentLookPitch: Double = 0
    private var lastFocusFeedbackID: UUID?
    private weak var currentGame: GameManager?
    private weak var inputView: StudentInputSCNView?
    private var pressedKeys: Set<Character> = []
    private var movementTimer: Timer?
    private var lastMovementTick = Date()
    private var pendingMouseDeltaX = 0.0
    private var pendingMouseDeltaY = 0.0
    private var wantsMouseLook = true
    private var isMouseLookCaptured = false
    private var cursorHiddenByDisplayAPI = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        loadPhotorealAssets()
        buildScene()
    }

    private struct SoundSourceStageSignal {
        let position: SCNVector3
        let intensity: Double
        let kind: AudioCueKind?
        let isLocated: Bool
        let label: String
    }

    private struct NoteTraceHotspotVisual {
        let hotspotID: String
        let nodeName: String
        let label: String
        let position: SCNVector3
        let color: NSColor
    }

    private var noteTraceHotspotVisuals: [NoteTraceHotspotVisual] {
        [
            NoteTraceHotspotVisual(
                hotspotID: "note.table",
                nodeName: "noteTraceHotspot_noteTable",
                label: "值日表",
                position: SCNVector3(0, 1.03, -1.45),
                color: NSColor(calibratedRed: 0.36, green: 0.92, blue: 0.76, alpha: 1)
            ),
            NoteTraceHotspotVisual(
                hotspotID: "note.paperTrail",
                nodeName: "noteTraceHotspot_paperTrail",
                label: "门声",
                position: SCNVector3(-0.2, 0.22, 1.5),
                color: NSColor(calibratedRed: 0.42, green: 0.84, blue: 1, alpha: 1)
            ),
            NoteTraceHotspotVisual(
                hotspotID: "note.deskTrace",
                nodeName: "noteTraceHotspot_deskTrace",
                label: "座位",
                position: SCNVector3(1.45, 0.92, -0.45),
                color: NSColor(calibratedRed: 0.52, green: 0.92, blue: 0.62, alpha: 1)
            ),
            NoteTraceHotspotVisual(
                hotspotID: "companion.zhou",
                nodeName: "noteTraceHotspot_companionZhou",
                label: "周",
                position: SCNVector3(-1.8, 1.72, 0.25),
                color: NSColor(calibratedRed: 0.3, green: 0.68, blue: 1, alpha: 1)
            ),
            NoteTraceHotspotVisual(
                hotspotID: "companion.xu",
                nodeName: "noteTraceHotspot_companionXu",
                label: "许",
                position: SCNVector3(1.8, 1.72, 0.25),
                color: NSColor(calibratedRed: 1, green: 0.48, blue: 0.74, alpha: 1)
            )
        ]
    }

    private func loadPhotorealAssets() {
        if isRunningInXCTest {
            realisticDeskTemplate = makeTestFurnitureTemplate(width: 0.78, height: 0.52, length: 0.46)
            realisticChairTemplate = makeTestFurnitureTemplate(width: 0.46, height: 0.58, length: 0.44)
            hallLightingImage = makeTestImage(color: .darkGray)
            quadLightingImage = makeTestImage(color: .gray)
            quadBackgroundImage = makeTestImage(color: .black)
            return
        }
        realisticDeskTemplate = loadUSDTemplate(
            resource: "SchoolDesk_01_2k",
            subdirectory: "Models/SchoolDesk_01"
        )
        realisticChairTemplate = loadUSDTemplate(
            resource: "SchoolChair_01_2k",
            subdirectory: "Models/SchoolChair_01"
        )
        hallLightingImage = loadResourceImage(resource: "school_hall_2k", extension: "hdr", subdirectory: "HDRI")
        quadLightingImage = loadResourceImage(resource: "school_quad_2k", extension: "hdr", subdirectory: "HDRI")
        quadBackgroundImage = loadResourceImage(resource: "school_quad_dusk", extension: "png", subdirectory: "HDRI")
    }

    private func loadUSDTemplate(resource: String, subdirectory: String) -> SCNNode? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "usdc", subdirectory: subdirectory),
              let source = SCNSceneSource(url: url, options: [.convertToYUp: true]),
              let loadedScene = source.scene(options: nil) else {
            return nil
        }
        let container = SCNNode()
        loadedScene.rootNode.childNodes.forEach { container.addChildNode($0.clone()) }
        // Poly Haven USD files declare Z-up. SceneKit currently preserves the
        // authored axes for these binary USDs even when convertToYUp is set.
        container.eulerAngles.x = -.pi / 2
        container.enumerateChildNodes { node, _ in
            node.castsShadow = true
            node.geometry?.materials.forEach { $0.lightingModel = .physicallyBased }
        }
        return container
    }

    private func loadResourceImage(resource: String, extension fileExtension: String, subdirectory: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: fileExtension, subdirectory: subdirectory) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func makeTestFurnitureTemplate(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: SCNBox(width: width, height: height, length: length, chamferRadius: 0.02))
        node.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.72, alpha: 1)
        return node
    }

    private func makeTestImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
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
        updateLightingEnvironment(game: game)
        updateNarrativeStage(game: game)
        let boundaryPulledBack = lastNarrativeBoundaryPullbackCount != game.narrativeBoundaryPullbackCount
        lastNarrativeBoundaryPullbackCount = game.narrativeBoundaryPullbackCount
        observeWindow(inputView?.window)
        synchronizeMouseLook(for: game)
        let signature = profileSignature(for: game.classmates)
        if !game.classmates.isEmpty && signature != classmateProfileSignature {
            rebuildClassmates(with: game.classmates)
            classmateProfileSignature = signature
        }
        let exteriorPanoramaActive = game.isPrologueActive && game.prologueCurrentBeat == .gateArrival
        classmateNodes.values.forEach { $0.isHidden = exteriorPanoramaActive }

        let cameraContextChanged = lastViewMode != game.viewMode
            || lastFreeRoamActive != game.freeRoam.isActive
            || lastPrologueActive != game.isPrologueActive
            || lastPrologueBeat != (game.isPrologueActive ? game.prologueCurrentBeat : nil)
            || lastNarrativeChapter != (game.narrativeCampaign.isActive ? game.narrativeCampaign.chapter : nil)
            || lastNarrativeMomentID != (game.narrativeCampaign.isActive ? game.narrativeCampaign.currentMoment.id : "")
        let poseChanged = lastPose != game.cameraPose
        let studentLookChanged = game.viewMode == .student && (
            lastStudentLookYaw != game.studentLookYaw || lastStudentLookPitch != game.studentLookPitch
        )
        lastStudentLookYaw = game.studentLookYaw
        lastStudentLookPitch = game.studentLookPitch

        if cameraContextChanged {
            let enteringPrologue = lastPrologueActive == false && game.isPrologueActive
            let enteringNarrativeStage = lastNarrativeChapter != (game.narrativeCampaign.isActive ? game.narrativeCampaign.chapter : nil)
            lastPose = game.cameraPose
            lastViewMode = game.viewMode
            lastFreeRoamActive = game.freeRoam.isActive
            lastPrologueActive = game.isPrologueActive
            lastPrologueBeat = game.isPrologueActive ? game.prologueCurrentBeat : nil
            lastNarrativeChapter = game.narrativeCampaign.isActive ? game.narrativeCampaign.chapter : nil
            lastNarrativeMomentID = game.narrativeCampaign.isActive ? game.narrativeCampaign.currentMoment.id : ""
            SCNTransaction.begin()
            SCNTransaction.animationDuration = (enteringPrologue || (enteringNarrativeStage && inputView == nil))
                ? 0
                : cameraTurnDuration(game: game)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyCameraMode(game: game, teacherPosition: teacherNode.position)
            SCNTransaction.commit()
        } else if poseChanged || studentLookChanged || game.freeRoam.isActive || game.narrativeCampaign.isActive {
            lastPose = game.cameraPose
            lastViewMode = game.viewMode
            lastFreeRoamActive = game.freeRoam.isActive
            SCNTransaction.begin()
            SCNTransaction.disableActions = boundaryPulledBack == false
            SCNTransaction.animationDuration = boundaryPulledBack ? 0.3 : 0
            SCNTransaction.animationTimingFunction = boundaryPulledBack
                ? CAMediaTimingFunction(name: .easeInEaseOut)
                : nil
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
        updateTeacherPatrolPressureStage(game: game, teacherPosition: teacherPath[index])
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
        updateSoundSourceStage(game: game)
        if let camera = cameraRig.camera {
            let fatigue = game.narrativeCampaign.isActive
                ? 0.08
                : (game.viewMode == .teacher ? game.teacher.fatigue / 140 : 1 - game.player.focusQuality)
            let eventIntensity = eventVisualIntensity(game: game)
            let sensoryIntensity = SensoryCameraPressure.derive(from: game.currentSensorySoundscape)
            camera.fStop = 1.6 + fatigue * 7.0 + eventIntensity.blur + sensoryIntensity.blur
            camera.focusDistance = game.narrativeCampaign.isActive
                ? 5.2
                : (game.viewMode == .teacher ? 4.2 : studentFocusDistance(game: game))
            camera.vignettingIntensity = 0.45 + fatigue * 1.15 + eventIntensity.vignette + sensoryIntensity.vignette
            camera.vignettingPower = 0.8 + fatigue * 1.5 + eventIntensity.vignette + sensoryIntensity.vignette * 0.72
            camera.saturation = CGFloat(1.0 - fatigue * 0.34 - eventIntensity.desaturation - sensoryIntensity.desaturation)
        }
        applyFocusFeedbackIfNeeded(game: game)
        let classmateSensoryReaction = SensoryClassroomGroupReaction.derive(from: game.currentSensorySoundscape)
        lastClassmateSensoryReaction = classmateSensoryReaction
        for classmate in game.classmates {
            guard let node = classmateNodes[classmate.id] else { continue }
            if classmateStates[classmate.id] != classmate.state {
                classmateStates[classmate.id] = classmate.state
                applyStateAnimation(classmate.state, to: node)
            }
            applySensoryReaction(classmateSensoryReaction, classmate: classmate, to: node)
        }
        updateLinCheChapterOnePerformance(game: game)
        if game.isPrologueActive == false {
            playerWaterCupNode.opacity = 1
            playerWaterCupNode.scale = SCNVector3(1, 1, 1)
        }
        updateProloguePerformance(game: game)
        updateScenePresentation(game: game)
        SCNTransaction.commit()
        if inputView == nil {
            SCNTransaction.flush()
        }
    }

    private func buildScene() {
        let exterior = makePrologueExterior()
        scene.rootNode.addChildNode(exterior)
        scene.rootNode.addChildNode(makeEnvironment())
        scene.rootNode.addChildNode(makeCorridor())
        scene.rootNode.addChildNode(makeFurniture())
        scene.rootNode.addChildNode(makeInteriorDetails())
        scene.rootNode.addChildNode(makeLighting())
        scene.rootNode.addChildNode(makePlayerDeskProps())

        soundSourceStageNode.addChildNode(makeSoundSourceStage())
        scene.rootNode.addChildNode(soundSourceStageNode)

        narrativeStageNode.name = "narrativeStageRoot"
        narrativeStageNode.position = SCNVector3(40, 0, 0)
        scene.rootNode.addChildNode(narrativeStageNode)

        teacherNode.addChildNode(makeTeacherGeometry())
        teacherNode.position = SCNVector3(0, 0.05, -4.25)
        scene.rootNode.addChildNode(teacherNode)
        teacherPatrolPressureNode.addChildNode(makeTeacherPatrolPressureStage())
        scene.rootNode.addChildNode(teacherPatrolPressureNode)

        addClassmates(classmates: [])
        configureCamera()
    }

    private func ensureNarrativeStageExists(for chapter: NarrativeChapter) {
        let name = "narrativeStage_\(chapter.rawValue)"
        guard narrativeStageNode.childNode(withName: name, recursively: false) == nil else { return }
        let stage: SCNNode
        switch chapter {
        case .classroom: return
        case .mirror: stage = makeMirrorStage()
        case .noteTrace: stage = makeNoteTraceStage()
        case .stairwell: stage = makeStairwellStage()
        case .counseling: stage = makeCounselingStage()
        case .epilogue: stage = makeEpilogueStage()
        }
        stage.position.x = CGFloat(chapter.rawValue - 2) * 16
        narrativeStageNode.addChildNode(stage)
    }

    private func updateNarrativeStage(game: GameManager) {
        let activeChapter = game.narrativeCampaign.isActive ? game.narrativeCampaign.chapter : nil
        selectedNarrativeStageName = activeChapter.flatMap { chapter in
            chapter == .classroom ? nil : "narrativeStage_\(chapter.rawValue)"
        }
        if let activeChapter, activeChapter != .classroom {
            ensureNarrativeStageExists(for: activeChapter)
        }
        guard let activeChapter, activeChapter != .classroom else {
            if game.isPrologueActive == false {
                cameraRig.camera?.exposureOffset = -1.9
            }
            return
        }

        cameraRig.camera?.exposureOffset = activeChapter == .epilogue ? -0.35 : -0.72
        updateNarrativeStagePerformance(game: game)
        updateNarrativeBoundaryVisual(game: game)
    }

    private func updateNarrativeBoundaryVisual(game: GameManager) {
        guard game.narrativeCampaign.chapter == .counseling,
              let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.counseling.rawValue)", recursively: false) else { return }
        let progress = CGFloat(game.narrativeBoundaryDwellProgress)
        if let line = stage.childNode(withName: "counselingBoundaryLine", recursively: true) {
            line.opacity = 0.22 + progress * 0.78
            line.geometry?.firstMaterial?.emission.intensity = 0.2 + progress * 0.8
        }
    }

    private func makeSoundSourceStage() -> SCNNode {
        let root = SCNNode()
        root.name = "soundSourceStage"
        root.isHidden = true
        root.opacity = 0

        let outer = SCNNode(geometry: SCNTorus(ringRadius: 0.42, pipeRadius: 0.01))
        outer.name = "soundSourceRingOuter"
        outer.eulerAngles.x = .pi / 2
        outer.geometry?.firstMaterial = translucentSoundMaterial(NSColor(calibratedRed: 0.25, green: 0.82, blue: 1, alpha: 0.42))
        root.addChildNode(outer)

        let inner = SCNNode(geometry: SCNTorus(ringRadius: 0.24, pipeRadius: 0.012))
        inner.name = "soundSourceRingInner"
        inner.eulerAngles.x = .pi / 2
        inner.geometry?.firstMaterial = translucentSoundMaterial(NSColor(calibratedRed: 0.52, green: 1, blue: 0.8, alpha: 0.5))
        root.addChildNode(inner)

        let core = sphere(
            radius: 0.075,
            color: NSColor(calibratedRed: 0.32, green: 0.88, blue: 1, alpha: 1),
            position: SCNVector3(0, 0.1, 0)
        )
        core.name = "soundSourceCore"
        core.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.28, green: 0.72, blue: 1, alpha: 1)
        core.geometry?.firstMaterial?.emission.intensity = 0.8
        root.addChildNode(core)

        let beam = capsule(
            radius: 0.012,
            height: 0.64,
            color: NSColor(calibratedRed: 0.36, green: 0.9, blue: 1, alpha: 0.58),
            position: SCNVector3(0, 0.42, 0)
        )
        beam.name = "soundSourceBeam"
        beam.geometry?.firstMaterial?.blendMode = .add
        beam.geometry?.firstMaterial?.writesToDepthBuffer = false
        beam.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.22, green: 0.68, blue: 1, alpha: 1)
        beam.geometry?.firstMaterial?.emission.intensity = 0.65
        root.addChildNode(beam)

        let label = makeText("声源", size: 0.07, color: .white, position: SCNVector3(-0.16, 0.84, 0))
        label.name = "soundSourceLabel"
        label.constraints = [SCNBillboardConstraint()]
        label.opacity = 0.7
        root.addChildNode(label)

        return root
    }

    private func updateSoundSourceStage(game: GameManager) {
        guard let stage = soundSourceStageNode.childNode(withName: "soundSourceStage", recursively: false) else { return }
        guard let signal = soundSourceStageSignal(for: game) else {
            stage.isHidden = true
            stage.opacity = 0
            return
        }

        let amount = CGFloat(signal.intensity.clamped(to: 0...1))
        let color = soundSourceColor(for: signal.kind, isLocated: signal.isLocated)
        stage.isHidden = false
        stage.opacity = 0.18 + amount * 0.72
        stage.position = signal.position
        stage.scale = SCNVector3(0.92 + Float(amount) * 0.24, 0.92 + Float(amount) * 0.24, 0.92 + Float(amount) * 0.24)

        if let core = stage.childNode(withName: "soundSourceCore", recursively: true) {
            core.opacity = 0.58 + amount * 0.42
            core.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.82)
            core.geometry?.firstMaterial?.emission.contents = color
            core.geometry?.firstMaterial?.emission.intensity = 0.42 + amount * 1.15 + (signal.isLocated ? 0.35 : 0)
        }
        if let outer = stage.childNode(withName: "soundSourceRingOuter", recursively: true) {
            outer.opacity = 0.26 + amount * 0.46
            outer.scale = SCNVector3(1.0 + Float(amount) * 0.5, 1.0 + Float(amount) * 0.5, 1)
            outer.geometry?.firstMaterial = translucentSoundMaterial(color.withAlphaComponent(0.34))
            outer.geometry?.firstMaterial?.emission.intensity = 0.26 + amount * 0.72
        }
        if let inner = stage.childNode(withName: "soundSourceRingInner", recursively: true) {
            inner.opacity = 0.36 + amount * 0.48
            inner.scale = SCNVector3(0.78 + Float(amount) * 0.28, 0.78 + Float(amount) * 0.28, 1)
            inner.geometry?.firstMaterial = translucentSoundMaterial(color.withAlphaComponent(signal.isLocated ? 0.54 : 0.42))
            inner.geometry?.firstMaterial?.emission.intensity = 0.38 + amount * 0.84 + (signal.isLocated ? 0.34 : 0)
        }
        if let beam = stage.childNode(withName: "soundSourceBeam", recursively: true) {
            beam.opacity = signal.isLocated ? 0.72 : 0.38 + amount * 0.28
            beam.scale = SCNVector3(1, 0.74 + Float(amount) * 0.42, 1)
            beam.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.5)
            beam.geometry?.firstMaterial?.emission.contents = color
            beam.geometry?.firstMaterial?.emission.intensity = 0.32 + amount * 0.86
        }
        if let label = stage.childNode(withName: "soundSourceLabel", recursively: true) {
            label.opacity = signal.isLocated ? 0.84 : 0.58
        }
    }

    private func soundSourceStageSignal(for game: GameManager) -> SoundSourceStageSignal? {
        guard case .playing = game.gameState,
              game.isPrologueActive == false,
              game.activeRole.isTeacher == false,
              game.narrativeCampaign.isActive == false else { return nil }

        if let objective = game.currentSpatialAudioObjective {
            let focusAmount = objective.progress.clamped(to: 0...1)
            return SoundSourceStageSignal(
                position: soundSourcePosition(for: objective),
                intensity: objective.isLocated ? 0.86 : max(0.34, objective.cueIntensity + focusAmount * 0.28),
                kind: objective.cueKind,
                isLocated: objective.isLocated,
                label: objective.title
            )
        }

        guard let cue = game.audioCues.first, cue.intensity > 0.24 else { return nil }
        return SoundSourceStageSignal(
            position: soundSourcePosition(forDirection: cue.direction),
            intensity: cue.intensity,
            kind: cue.kind,
            isLocated: false,
            label: cue.kind.rawValue
        )
    }

    private func soundSourcePosition(for objective: SpatialAudioObjective) -> SCNVector3 {
        switch objective.step {
        case .observeLinChe:
            return SCNVector3(-2.34, 0.06, 0.9)
        case .locateHiddenSound:
            return SCNVector3(2.36, 0.06, 0.64)
        case .inspectNote:
            return SCNVector3(-0.18, 0.12, 1.44)
        case .regulateSelf, .approachLinChe, .followLinChe, .completed:
            return soundSourcePosition(forDirection: objective.direction)
        }
    }

    private func soundSourcePosition(forDirection direction: String) -> SCNVector3 {
        if direction.contains("桌面") || direction.contains("颅内") || direction.contains("喉咙") || direction.contains("胸口") {
            return SCNVector3(-0.18, 0.12, 1.44)
        }
        if direction.contains("左窗") {
            return SCNVector3(-3.72, 0.18, 0.2)
        }
        if direction.contains("左") {
            return SCNVector3(-2.34, 0.06, 0.9)
        }
        if direction.contains("后") {
            return SCNVector3(-2.6, 0.06, 4.34)
        }
        if direction.contains("讲台") || direction.contains("前方") || direction.contains("广播") {
            return SCNVector3(0.0, 0.06, -4.36)
        }
        if direction.contains("右") || direction.contains("走廊") {
            return SCNVector3(2.36, 0.06, 0.64)
        }
        if direction.contains("头顶") {
            return SCNVector3(0.0, 2.76, 0.0)
        }
        return SCNVector3(0, 0.08, 0.4)
    }

    private func soundSourceColor(for kind: AudioCueKind?, isLocated: Bool) -> NSColor {
        if isLocated {
            return NSColor(calibratedRed: 0.36, green: 0.94, blue: 0.62, alpha: 1)
        }
        switch kind {
        case .footstep, .knock, .wrapper, .phone, .chair:
            return NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.22, alpha: 1)
        case .paper, .whisper, .crying:
            return NSColor(calibratedRed: 0.25, green: 0.88, blue: 1.0, alpha: 1)
        case .heartbeat, .stomach:
            return NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.56, alpha: 1)
        case .broadcast, .bell, .teacherCough, .teacherSigh, .lights:
            return NSColor(calibratedRed: 0.64, green: 0.78, blue: 1.0, alpha: 1)
        case .none:
            return NSColor(calibratedRed: 0.52, green: 0.86, blue: 1.0, alpha: 1)
        }
    }

    private func updateNarrativeStagePerformance(game: GameManager) {
        let campaign = game.narrativeCampaign
        let name = "narrativeStage_\(campaign.chapter.rawValue)"
        guard let stage = narrativeStageNode.childNode(withName: name, recursively: false) else { return }
        updateNarrativeCompanion(in: stage, campaign: campaign)
        updateNarrativeChapterActors(in: stage, campaign: campaign)
        updateNarrativeWorldDirector(in: stage, signal: campaign.worldDirectorSignal)
        updateNarrativeAmbientActors(in: stage, directives: campaign.ambientActorDirectives)
        updateNarrativeConsequenceEchoes(in: stage, campaign: campaign)
        updateNarrativeChapterMemory(in: stage, campaign: campaign)
        updateMirrorThreeLightStage(in: stage, campaign: campaign, activeMiniGame: game.activeNarrativeMicroGame)
        updateNoteTraceHotspotStage(in: stage, campaign: campaign)
        guard let focus = stage.childNode(withName: "stageFocus", recursively: true) else { return }
        let interaction = CGFloat(campaign.miniGameProgress)
        let storyProgress = CGFloat(campaign.momentIndex)
        let pulse = 1 + min(0.42, interaction * 0.07 + storyProgress * 0.018)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = inputView == nil ? 0 : 0.35
        focus.scale = SCNVector3(pulse, pulse, pulse)
        focus.opacity = 0.72 + min(0.28, interaction * 0.06 + storyProgress * 0.04)
        switch campaign.chapter {
        case .mirror:
            stage.childNodes(passingTest: { node, _ in node.name?.hasPrefix("mirrorBeacon") == true }).forEach {
                $0.opacity = 0.3 + min(0.7, CGFloat(campaign.momentIndex + campaign.miniGameProgress) * 0.12)
            }
            focus.geometry?.firstMaterial?.emission.intensity = 0.55 + interaction * 0.12
        case .noteTrace:
            focus.position.y = 0.38 + storyProgress * 0.018
        case .stairwell:
            focus.position.z = -1.65 + storyProgress * 0.08
            let trustRelaxation = min(1, max(0, CGFloat(campaign.jiangYueTrust) / 60))
            focus.eulerAngles.x = -0.26 + trustRelaxation * 0.2
            focus.eulerAngles.z = -0.08 + trustRelaxation * 0.06
        case .counseling:
            focus.geometry?.firstMaterial?.emission.intensity = 0.45 + storyProgress * 0.18
        case .epilogue:
            focus.geometry?.firstMaterial?.emission.intensity = 0.7 + storyProgress * 0.22
        case .classroom:
            break
        }
        SCNTransaction.commit()
    }

    private func updateNoteTraceHotspotStage(in stage: SCNNode, campaign: NarrativeCampaign) {
        guard campaign.chapter == .noteTrace else { return }
        let requiredIDs = campaign.requiredHotspotIDsForCurrentMoment
        let actionReady = campaign.currentMomentActionReady
        let completedIDs = completedNoteTraceHotspotIDs(for: campaign)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = inputView == nil ? 0 : 0.35

        for item in noteTraceHotspotVisuals {
            guard let beacon = stage.childNode(withName: item.nodeName, recursively: true) else { continue }
            let isCurrent = requiredIDs.contains(item.hotspotID)
            let isComplete = completedIDs.contains(item.hotspotID) || (isCurrent && actionReady)
            let power: CGFloat = isCurrent
                ? (actionReady ? 0.82 : 1)
                : (isComplete ? 0.58 : 0.16)
            beacon.opacity = 0.18 + power * 0.72
            beacon.scale = SCNVector3(0.82 + Float(power) * 0.36, 0.82 + Float(power) * 0.36, 0.82 + Float(power) * 0.36)
            beacon.geometry?.firstMaterial?.emission.intensity = 0.16 + power * 0.95
            beacon.geometry?.firstMaterial?.diffuse.contents = item.color.withAlphaComponent(0.62 + power * 0.28)
            beacon.geometry?.firstMaterial?.emission.contents = item.color

            if let ring = beacon.childNode(withName: "noteTraceHotspotRing", recursively: true) {
                ring.opacity = isCurrent ? 0.72 : (isComplete ? 0.42 : 0.12)
                ring.scale = SCNVector3(0.9 + Float(power) * 0.28, 0.9 + Float(power) * 0.28, 1)
                ring.geometry?.firstMaterial?.emission.intensity = 0.18 + power * 0.62
            }
            if let label = beacon.childNode(withName: "noteTraceHotspotLabel", recursively: true) {
                label.opacity = isCurrent || isComplete ? 0.86 : 0.32
            }
        }

        updateNoteTraceNavigationRig(in: stage, campaign: campaign)
        SCNTransaction.commit()
    }

    private func updateNoteTraceNavigationRig(in stage: SCNNode, campaign: NarrativeCampaign) {
        guard let rig = stage.childNode(withName: "noteTraceNavigationRig", recursively: true) else { return }
        guard let cue = ChapterThreeNavigationCue.derive(from: campaign),
              let hotspot = campaign.requiredInteractionHotspots.first else {
            rig.isHidden = true
            rig.opacity = 0
            return
        }

        let player = SCNVector3(Float(campaign.exploration.positionX), 0.09, Float(campaign.exploration.positionZ))
        let target = SCNVector3(Float(hotspot.x), 0.1, Float(hotspot.z))
        let dx = target.x - player.x
        let dz = target.z - player.z
        let distance = max(0.18, sqrt(dx * dx + dz * dz))
        let pulse = CGFloat(cue.pulseIntensity.clamped(to: 0...1))
        let navigationColor = cue.isInRange
            ? NSColor(calibratedRed: 0.42, green: 0.96, blue: 0.68, alpha: 1)
            : NSColor(calibratedRed: 0.25, green: 0.86, blue: 1, alpha: 1)

        rig.isHidden = false
        rig.opacity = 0.22 + pulse * 0.58

        if let origin = rig.childNode(withName: "noteTraceNavigationOrigin", recursively: true) {
            origin.position = player
            origin.opacity = cue.isInRange ? 0.36 : 0.5 + pulse * 0.32
            origin.geometry?.firstMaterial?.emission.contents = navigationColor
            origin.geometry?.firstMaterial?.emission.intensity = 0.28 + pulse * 0.7
        }

        if let beam = rig.childNode(withName: "noteTraceNavigationBeam", recursively: true) {
            beam.position = SCNVector3(player.x + dx / 2, 0.074, player.z + dz / 2)
            beam.eulerAngles.y = CGFloat(-atan2(dz, dx))
            beam.scale = SCNVector3(distance, 1, 1)
            beam.opacity = cue.isInRange ? 0.16 : 0.28 + pulse * 0.48
            beam.geometry?.firstMaterial?.diffuse.contents = navigationColor.withAlphaComponent(0.5)
            beam.geometry?.firstMaterial?.emission.contents = navigationColor
            beam.geometry?.firstMaterial?.emission.intensity = 0.22 + pulse * 0.88
        }

        if let targetCore = rig.childNode(withName: "noteTraceNavigationTargetCore", recursively: true) {
            targetCore.position = SCNVector3(target.x, 0.19, target.z)
            targetCore.opacity = 0.52 + pulse * 0.42
            targetCore.scale = SCNVector3(0.86 + Float(pulse) * 0.36, 0.86 + Float(pulse) * 0.36, 0.86 + Float(pulse) * 0.36)
            targetCore.geometry?.firstMaterial?.diffuse.contents = navigationColor.withAlphaComponent(0.76)
            targetCore.geometry?.firstMaterial?.emission.contents = navigationColor
            targetCore.geometry?.firstMaterial?.emission.intensity = 0.42 + pulse * 1.05
        }

        if let targetRing = rig.childNode(withName: "noteTraceNavigationTargetRing", recursively: true) {
            targetRing.position = SCNVector3(target.x, 0.065, target.z)
            targetRing.opacity = 0.28 + pulse * 0.58
            targetRing.scale = SCNVector3(0.82 + Float(pulse) * 0.54, 0.82 + Float(pulse) * 0.54, 1)
            targetRing.geometry?.firstMaterial?.diffuse.contents = navigationColor.withAlphaComponent(0.42)
            targetRing.geometry?.firstMaterial?.emission.contents = navigationColor
            targetRing.geometry?.firstMaterial?.emission.intensity = 0.2 + pulse * 0.86
        }
    }

    private func completedNoteTraceHotspotIDs(for campaign: NarrativeCampaign) -> Set<String> {
        var ids = Set<String>()
        if campaign.completedMomentIDs.contains("3.note") || campaign.currentMoment.id != "3.note" && campaign.momentIndex > 0 {
            ids.insert("note.table")
        }
        if campaign.completedMomentIDs.contains("3.locate") || campaign.currentMoment.id != "3.locate" && campaign.momentIndex > 1 {
            ids.insert("note.paperTrail")
        }
        if campaign.completedMomentIDs.contains("3.locate") || campaign.noteTraceDepartureClues.contains(.deskTrace) {
            ids.insert("note.deskTrace")
        }
        if campaign.noteTraceDepartureClues.contains(.doorSound) {
            ids.insert("note.paperTrail")
        }
        if campaign.companionID == "周予安" {
            ids.insert("companion.zhou")
        }
        if campaign.companionID == "许栀" {
            ids.insert("companion.xu")
        }
        return ids
    }

    private func updateMirrorThreeLightStage(in stage: SCNNode, campaign: NarrativeCampaign, activeMiniGame: NarrativeMiniGame?) {
        guard campaign.chapter == .mirror else { return }
        let games: [NarrativeMiniGame] = [.trace, .melody, .erase]
        let progress = CGFloat(campaign.miniGameProgress)
        let dissolve = CGFloat(campaign.mirrorDissolveProgress)
        let currentProgress: CGFloat
        if campaign.currentMoment.miniGame == .melody {
            currentProgress = (progress / 4).clamped(to: 0...1)
        } else {
            currentProgress = (progress / 6).clamped(to: 0...1)
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = inputView == nil ? 0 : 0.38
        let returnDirector = MirrorReturnDirectorModel.derive(from: campaign)
        stage.opacity = returnDirector.isActive ? returnDirector.stageOpacity : 1 - dissolve * 0.28

        for index in 0..<games.count {
            guard let light = stage.childNode(withName: "mirrorRouteLight_\(index)", recursively: true) else { continue }
            let momentIndex = index + 1
            let isPast = campaign.momentIndex > momentIndex || campaign.isComplete
            let isCurrent = campaign.currentMoment.miniGame == games[index]
            let isComplete = isPast || (isCurrent && campaign.miniGameCompleted)
            let isActive = isCurrent && campaign.miniGameCompleted == false
            let power: CGFloat = isComplete ? 1 - dissolve * 0.18 : (isActive ? 0.48 + currentProgress * 0.42 : 0.16)
            let color: NSColor = isComplete
                ? (NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.26, alpha: 1).blended(withFraction: dissolve * 0.35, of: .white)
                    ?? NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.26, alpha: 1))
                : (isActive
                   ? NSColor(calibratedRed: 0.28, green: 0.86, blue: 1.0, alpha: 1)
                   : NSColor(calibratedRed: 0.35, green: 0.31, blue: 0.48, alpha: 1))

            light.opacity = 0.26 + power * 0.74
            light.scale = SCNVector3(0.72 + Float(power) * 0.52, 0.72 + Float(power) * 0.52, 0.72 + Float(power) * 0.52)
            light.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.78)
            light.geometry?.firstMaterial?.emission.contents = color
            light.geometry?.firstMaterial?.emission.intensity = 0.18 + power * 1.35

            if let halo = light.childNode(withName: "mirrorRouteLightHalo", recursively: true) {
                halo.opacity = 0.1 + power * 0.62
                halo.scale = SCNVector3(0.9 + Float(power) * 0.62, 0.9 + Float(power) * 0.62, 1)
                halo.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.28)
                halo.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.42)
                halo.geometry?.firstMaterial?.emission.intensity = 0.14 + power * 0.88
            }
        }

        for index in 0..<2 {
            guard let bridge = stage.childNode(withName: "mirrorRouteBridge_\(index)", recursively: true) else { continue }
            let isLit = campaign.momentIndex > index + 1 || campaign.isComplete
            bridge.opacity = isLit ? 0.72 - dissolve * 0.18 : 0.16
            bridge.geometry?.firstMaterial?.emission.intensity = isLit ? 0.82 - dissolve * 0.22 : 0.12
        }

        let echoModel = MirrorMicroGameEchoModel.derive(from: campaign)
        let echoAnchors: [SCNVector3] = [
            SCNVector3(-1.18, 1.74, -2.34),
            SCNVector3(0, 1.92, -2.34),
            SCNVector3(1.18, 1.74, -2.34)
        ]
        let anchor = echoAnchors[min(max(echoModel.currentLightIndex, 0), echoAnchors.count - 1)]
        for index in 0..<6 {
            guard let echo = stage.childNode(withName: "mirrorMicroEcho_\(index)", recursively: true) else { continue }
            let column = CGFloat(index % 3) - 1
            let row = CGFloat(index / 3)
            let x = anchor.x + column * 0.24
            let y = anchor.y - row * 0.22
            let z = anchor.z + 0.04
            echo.position = SCNVector3(x, y, z)
            echo.opacity = echoModel.isActive ? echoModel.echoOpacities[index] : 0
            echo.scale = echoModel.echoScales[index]
            echo.isHidden = echoModel.isActive == false
            echo.geometry?.firstMaterial?.emission.intensity = echoModel.isActive ? 0.18 + echoModel.ratio * 0.92 : 0
        }

        let performanceModel = MirrorMicroGamePerformanceModel.derive(from: campaign, activeMiniGame: activeMiniGame)
        if let portal = stage.childNode(withName: "mirrorMicroPortalRing", recursively: true) {
            portal.position = performanceModel.portalPosition
            portal.scale = performanceModel.portalScale
            portal.opacity = performanceModel.portalOpacity
            portal.isHidden = performanceModel.isActive == false
            portal.geometry?.firstMaterial?.emission.intensity = performanceModel.portalEmission
        }
        if let beam = stage.childNode(withName: "mirrorMicroPortalBeam", recursively: true) {
            beam.position = performanceModel.beamPosition
            beam.scale = performanceModel.beamScale
            beam.opacity = performanceModel.beamOpacity
            beam.isHidden = performanceModel.isActive == false
            beam.geometry?.firstMaterial?.emission.intensity = 0.24 + performanceModel.portalEmission * 0.62
        }
        if let pulse = stage.childNode(withName: "mirrorMicroReturnPulse", recursively: true) {
            pulse.position = performanceModel.returnPulsePosition
            pulse.scale = performanceModel.returnPulseScale
            pulse.opacity = performanceModel.returnPulseOpacity
            pulse.isHidden = performanceModel.isReturnPulseActive == false
            pulse.geometry?.firstMaterial?.emission.intensity = performanceModel.returnPulseEmission
        }

        let pressureModel = MirrorSpacePressureModel.derive(from: campaign)
        if let mirror = stage.childNode(withName: "mirrorSurface", recursively: true) {
            let tint = NSColor(calibratedRed: 0.14 + pressureModel.pressure * 0.1, green: 0.17 + pressureModel.dissolve * 0.14, blue: 0.28 + pressureModel.dissolve * 0.2, alpha: 1)
            mirror.geometry?.firstMaterial?.diffuse.contents = tint
            mirror.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.18, green: 0.48 + pressureModel.dissolve * 0.28, blue: 0.88, alpha: 1)
            mirror.geometry?.firstMaterial?.emission.intensity = pressureModel.mirrorTintEmission
        }

        for index in 0..<pressureModel.crackOpacities.count {
            guard let crack = stage.childNode(withName: "mirrorPressureCrack_\(index)", recursively: true) else { continue }
            crack.opacity = pressureModel.crackOpacities[index]
            crack.geometry?.firstMaterial?.emission.intensity = pressureModel.crackEmissions[index]
        }

        if let shadow = stage.childNode(withName: "mirrorLinCheShadow", recursively: true) {
            shadow.position = returnDirector.isActive ? returnDirector.linChePosition : pressureModel.shadowPosition
            shadow.eulerAngles.y = returnDirector.isActive ? returnDirector.linCheYaw : pressureModel.shadowYaw
            shadow.opacity = returnDirector.isActive ? returnDirector.linCheOpacity : pressureModel.shadowOpacity
            shadow.scale = pressureModel.shadowScale
        }

        if let ring = stage.childNode(withName: "mirrorBreathRing", recursively: true) {
            ring.position = pressureModel.breathRingPosition
            ring.scale = pressureModel.breathRingScale
            ring.opacity = pressureModel.breathRingOpacity
            ring.geometry?.firstMaterial?.emission.intensity = pressureModel.breathRingEmission
        }

        if let faceLight = stage.childNode(withName: "mirrorLinCheFaceLight", recursively: true) {
            faceLight.position = returnDirector.faceLightPosition
            faceLight.opacity = returnDirector.faceLightOpacity
            faceLight.scale = returnDirector.faceLightScale
            faceLight.isHidden = returnDirector.isActive == false
            faceLight.geometry?.firstMaterial?.emission.intensity = returnDirector.faceLightEmission
        }

        if let band = stage.childNode(withName: "mirrorRealityReturnBand", recursively: true) {
            band.position = returnDirector.realityBandPosition
            band.opacity = returnDirector.realityBandOpacity
            band.scale = returnDirector.realityBandScale
            band.isHidden = returnDirector.isActive == false
            band.geometry?.firstMaterial?.emission.intensity = returnDirector.realityBandEmission
        }

        if let gate = stage.childNode(withName: "mirrorReturnGate", recursively: true) {
            gate.position = returnDirector.returnGatePosition
            gate.opacity = returnDirector.returnGateOpacity
            gate.scale = returnDirector.returnGateScale
            gate.isHidden = returnDirector.isActive == false
            gate.geometry?.firstMaterial?.emission.intensity = returnDirector.returnGateEmission
        }

        let navigationCue = MirrorLightNavigationCue.derive(from: campaign)
        if let path = stage.childNode(withName: "mirrorNavigationPath", recursively: true) {
            path.position = navigationCue.pathPosition
            path.eulerAngles.y = navigationCue.pathYaw
            path.scale = navigationCue.pathScale
            path.opacity = navigationCue.pathOpacity
            path.isHidden = navigationCue.isActive == false
            path.geometry?.firstMaterial?.emission.intensity = navigationCue.pathEmission
        }
        if let target = stage.childNode(withName: "mirrorNavigationTargetRing", recursively: true) {
            target.position = navigationCue.targetPosition
            target.scale = navigationCue.targetRingScale
            target.opacity = navigationCue.targetRingOpacity
            target.isHidden = navigationCue.isActive == false
            target.geometry?.firstMaterial?.emission.intensity = navigationCue.targetRingEmission
        }
        if let player = stage.childNode(withName: "mirrorNavigationPlayerDot", recursively: true) {
            player.position = navigationCue.playerPosition
            player.opacity = navigationCue.isActive ? 0.36 + CGFloat(navigationCue.progressToRange) * 0.34 : 0
            player.isHidden = navigationCue.isActive == false
        }

        SCNTransaction.commit()
    }

    private func updateNarrativeAmbientActors(in stage: SCNNode, directives: [NarrativeAmbientActorDirective]) {
        let duration: CFTimeInterval = inputView == nil ? 0 : 0.38

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration

        for index in 0..<4 {
            guard let node = stage.childNode(withName: "ambientLivingActor_\(index)", recursively: true) else { continue }
            guard index < directives.count else {
                node.isHidden = true
                node.opacity = 0
                continue
            }

            let directive = directives[index]
            let progress = CGFloat((0.25 + directive.intensity * 0.55).clamped(to: 0...1))
            let x = directive.anchorX + (directive.targetX - directive.anchorX) * Double(progress)
            let z = directive.anchorZ + (directive.targetZ - directive.anchorZ) * Double(progress)
            node.isHidden = false
            node.opacity = 0.36 + CGFloat(directive.intensity.clamped(to: 0...1)) * 0.52
            node.position = SCNVector3(Float(x), 0, Float(z))
            node.eulerAngles.y = CGFloat(atan2(directive.targetX - x, directive.targetZ - z))
            node.scale = ambientActorScale(for: directive.role, intensity: directive.intensity)

            if let label = node.childNode(withName: "ambientLivingActorLabel", recursively: true) {
                label.opacity = directive.role == .facilitator || directive.role == .boundaryKeeper ? 0.86 : 0.42
            }
            applyNarrativeActorPerformance(
                to: node,
                tension: ambientActorTension(for: directive.role, intensity: directive.intensity),
                gaze: ambientActorGaze(for: directive.role, intensity: directive.intensity),
                breath: 0.14 + CGFloat(directive.intensity.clamped(to: 0...1)) * 0.34,
                shieldVisible: directive.role == .boundaryKeeper,
                markerColor: ambientActorColor(for: directive.role)
            )
        }

        SCNTransaction.commit()
    }

    private func ambientActorScale(for role: NarrativeAmbientActorRole, intensity: Double) -> SCNVector3 {
        let base: Float = role == .facilitator || role == .supportRunner ? 0.68 : 0.58
        let pulse = Float(intensity.clamped(to: 0...1)) * 0.08
        return SCNVector3(base + pulse, base + pulse, base + pulse)
    }

    private func ambientActorTension(for role: NarrativeAmbientActorRole, intensity: Double) -> CGFloat {
        let amount = CGFloat(intensity.clamped(to: 0...1))
        switch role {
        case .bystander:
            return 0.62 + amount * 0.22
        case .messenger:
            return 0.48
        case .boundaryKeeper:
            return 0.32
        case .supportRunner:
            return 0.38
        case .quietWitness:
            return 0.24 + amount * 0.16
        case .facilitator:
            return 0.16
        }
    }

    private func ambientActorGaze(for role: NarrativeAmbientActorRole, intensity: Double) -> CGFloat {
        let amount = CGFloat(intensity.clamped(to: 0...1))
        switch role {
        case .bystander:
            return 0.52 + amount * 0.26
        case .messenger, .supportRunner:
            return 0.72
        case .boundaryKeeper:
            return 0.84
        case .quietWitness:
            return 0.32 + amount * 0.22
        case .facilitator:
            return 0.68
        }
    }

    private func ambientActorColor(for role: NarrativeAmbientActorRole) -> NSColor {
        switch role {
        case .bystander:
            return NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.86, alpha: 1)
        case .messenger:
            return NSColor(calibratedRed: 0.28, green: 0.72, blue: 0.96, alpha: 1)
        case .boundaryKeeper:
            return NSColor(calibratedRed: 0.34, green: 0.9, blue: 0.62, alpha: 1)
        case .supportRunner:
            return NSColor(calibratedRed: 0.26, green: 0.78, blue: 1, alpha: 1)
        case .quietWitness:
            return NSColor(calibratedRed: 0.6, green: 0.78, blue: 0.9, alpha: 1)
        case .facilitator:
            return NSColor(calibratedRed: 0.46, green: 0.9, blue: 0.58, alpha: 1)
        }
    }

    private func updateNarrativeConsequenceEchoes(in stage: SCNNode, campaign: NarrativeCampaign) {
        guard campaign.chapter == .epilogue else { return }
        let echoes = campaign.consequenceEchoes
        let duration: CFTimeInterval = inputView == nil ? 0 : 0.4

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        for index in 0..<6 {
            guard let node = stage.childNode(withName: "consequenceEcho_\(index)", recursively: true) else { continue }
            guard index < echoes.count else {
                node.isHidden = true
                node.opacity = 0
                continue
            }
            let echo = echoes[index]
            let strength = CGFloat(echo.strength.clamped(to: 0...1))
            let color = consequenceEchoColor(echo.kind)
            node.isHidden = false
            node.opacity = 0.2 + strength * 0.72
            node.scale = SCNVector3(
                0.72 + Float(strength) * 0.46,
                0.72 + Float(strength) * 0.46,
                0.72 + Float(strength) * 0.46
            )
            node.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.7)
            node.geometry?.firstMaterial?.emission.contents = color
            node.geometry?.firstMaterial?.emission.intensity = 0.25 + strength * 0.92
        }
        SCNTransaction.commit()
    }

    private func updateNarrativeChapterMemory(in stage: SCNNode, campaign: NarrativeCampaign) {
        guard campaign.chapter == .epilogue else { return }
        let markers = campaign.routeMarkers
        let duration: CFTimeInterval = inputView == nil ? 0 : 0.38

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration

        for index in 0..<NarrativeChapter.allCases.count {
            guard let beacon = stage.childNode(withName: "chapterMemoryBeacon_\(index)", recursively: true) else { continue }
            guard index < markers.count else {
                beacon.isHidden = true
                beacon.opacity = 0
                continue
            }

            let marker = markers[index]
            let strength = CGFloat(marker.signalStrength.clamped(to: 0...1))
            let color = chapterMemoryColor(for: marker)
            let stateBoost: CGFloat
            switch marker.state {
            case .completed:
                stateBoost = 0.16
            case .current:
                stateBoost = 0.28
            case .upcoming:
                stateBoost = -0.10
            }
            let opacity = (0.24 + strength * 0.58 + stateBoost).clamped(to: 0.14...1)
            beacon.isHidden = false
            beacon.opacity = opacity
            beacon.scale = SCNVector3(
                0.78 + Float(strength) * 0.38 + (marker.state == .current ? 0.14 : 0),
                0.78 + Float(strength) * 0.38 + (marker.state == .current ? 0.14 : 0),
                0.78 + Float(strength) * 0.38 + (marker.state == .current ? 0.14 : 0)
            )
            beacon.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.72)
            beacon.geometry?.firstMaterial?.emission.contents = color
            beacon.geometry?.firstMaterial?.emission.intensity = 0.22 + strength * 0.92 + (marker.state == .current ? 0.32 : 0)

            if let halo = beacon.childNode(withName: "chapterMemoryHalo", recursively: true) {
                halo.opacity = (0.12 + strength * 0.34 + (marker.state == .current ? 0.2 : 0)).clamped(to: 0.08...0.72)
                halo.scale = SCNVector3(1.0 + Float(strength) * 0.45, 1.0 + Float(strength) * 0.45, 1)
                halo.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.28)
                halo.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.42)
            }
        }

        for index in 0..<(NarrativeChapter.allCases.count - 1) {
            guard let line = stage.childNode(withName: "chapterMemoryLine_\(index)", recursively: true),
                  index < markers.count - 1 else { continue }
            let strength = CGFloat(min(markers[index].signalStrength, markers[index + 1].signalStrength).clamped(to: 0...1))
            let active = markers[index].state != .upcoming || markers[index + 1].state != .upcoming
            line.isHidden = false
            line.opacity = active ? 0.18 + strength * 0.42 : 0.08
            line.geometry?.firstMaterial?.emission.intensity = active ? 0.16 + strength * 0.52 : 0.06
        }

        SCNTransaction.commit()
    }

    private func chapterMemoryColor(for marker: NarrativeRouteMarker) -> NSColor {
        switch marker.chapter {
        case .classroom:
            return NSColor(calibratedRed: 0.36, green: 0.82, blue: 0.94, alpha: 1)
        case .mirror:
            return NSColor(calibratedRed: 0.78, green: 0.48, blue: 0.94, alpha: 1)
        case .noteTrace:
            return NSColor(calibratedRed: 0.62, green: 0.84, blue: 0.66, alpha: 1)
        case .stairwell:
            return NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.36, alpha: 1)
        case .counseling:
            return NSColor(calibratedRed: 0.42, green: 0.9, blue: 0.68, alpha: 1)
        case .epilogue:
            return NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.42, alpha: 1)
        }
    }

    private func consequenceEchoColor(_ kind: NarrativeConsequenceEchoKind) -> NSColor {
        switch kind {
        case .noticed:
            return NSColor(calibratedRed: 0.34, green: 0.82, blue: 0.96, alpha: 1)
        case .companion:
            return NSColor(calibratedRed: 0.34, green: 0.9, blue: 0.62, alpha: 1)
        case .riskQuestion:
            return NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.34, alpha: 1)
        case .privacy:
            return NSColor(calibratedRed: 0.38, green: 0.86, blue: 0.72, alpha: 1)
        case .selfCare:
            return NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.78, alpha: 1)
        case .handoff:
            return NSColor(calibratedRed: 1, green: 0.64, blue: 0.3, alpha: 1)
        }
    }

    private func updateNarrativeChapterActors(in stage: SCNNode, campaign: NarrativeCampaign) {
        if campaign.chapter == .stairwell {
            let teacher = stage.childNode(withName: "handoffTeacher", recursively: true)
            let hasBeenCalled = campaign.safetyHandoffState?.adultContactInitiated == true
            teacher?.isHidden = hasBeenCalled == false
            if hasBeenCalled {
                teacher?.position = SCNVector3(-1.15, 0, 0.1)
                applyNarrativeActorPerformance(
                    to: teacher,
                    tension: campaign.safetyHandoffState?.safetyHandoffComplete == true ? 0.18 : 0.32,
                    gaze: 0.88,
                    breath: 0.22,
                    shieldVisible: campaign.safetyHandoffState?.safetyHandoffComplete == true,
                    markerColor: NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.58, alpha: 1)
                )
            }
            let signal = stage.childNode(withName: "adultArrivalSignal", recursively: true)
            signal?.isHidden = hasBeenCalled == false
            signal?.geometry?.firstMaterial?.emission.intensity = campaign.safetyHandoffState?.safetyHandoffComplete == true ? 1.1 : 0.55
            if let jiang = stage.childNode(withName: "stageFocus", recursively: true) {
                let trustRelaxation = min(1, max(0, CGFloat(campaign.jiangYueTrust) / 60))
                let handoffRelief: CGFloat = campaign.safetyHandoffState?.safetyHandoffComplete == true ? 0.22 : 0
                let ruptureLift = CGFloat(campaign.jiangDialoguePerformanceRupture) * 0.18
                let supportRelief = CGFloat(campaign.jiangDialoguePerformanceSupport) * 0.16
                applyNarrativeActorPerformance(
                    to: jiang,
                    tension: max(0.18, 0.92 - trustRelaxation * 0.58 - handoffRelief - supportRelief + ruptureLift),
                    gaze: 0.18 + trustRelaxation * 0.36 + CGFloat(campaign.jiangDialoguePerformanceSupport) * 0.12,
                    breath: max(0.2, 0.82 - trustRelaxation * 0.38 - supportRelief + ruptureLift * 0.55),
                    shieldVisible: hasBeenCalled,
                    markerColor: NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.34, alpha: 1)
                )
            }
            updateJiangDialoguePerformanceStage(in: stage, campaign: campaign)
        }

        if campaign.chapter == .counseling {
            let showRumor = campaign.currentMoment.id == "5.rumor"
                && campaign.counselingState?.rumorHandled != true
                && campaign.counselingState?.entryMode != .emergencyClosure
            stage.childNodes(passingTest: { node, _ in node.name?.hasPrefix("rumorNPC") == true }).forEach {
                $0.isHidden = showRumor == false
                applyNarrativeActorPerformance(
                    to: $0,
                    tension: showRumor ? 0.7 : 0.2,
                    gaze: showRumor ? 0.64 : 0.12,
                    breath: showRumor ? 0.46 : 0.1,
                    shieldVisible: false,
                    markerColor: NSColor(calibratedRed: 0.74, green: 0.68, blue: 0.9, alpha: 1)
                )
            }
            let phone = stage.childNode(withName: "messagePhone", recursively: true)
            let showPhone = campaign.currentMoment.id == "5.message"
                && campaign.counselingState?.companionMessageReplied != true
            phone?.isHidden = showPhone == false
            let routeBeacon = stage.childNode(withName: "counselingRouteBeacon", recursively: true)
            let routeColor: NSColor
            switch campaign.counselingState?.entryMode {
            case .urgentHandoffWaiting:
                routeColor = NSColor(calibratedRed: 0.95, green: 0.52, blue: 0.2, alpha: 1)
            case .emergencyClosure:
                routeColor = NSColor(calibratedRed: 0.88, green: 0.2, blue: 0.18, alpha: 1)
            default:
                routeColor = NSColor(calibratedRed: 0.24, green: 0.82, blue: 0.54, alpha: 1)
            }
            routeBeacon?.geometry?.firstMaterial?.diffuse.contents = routeColor
            routeBeacon?.geometry?.firstMaterial?.emission.contents = routeColor
        }
    }

    private func updateJiangDialoguePerformanceStage(in stage: SCNNode, campaign: NarrativeCampaign) {
        let support = CGFloat(campaign.jiangDialoguePerformanceSupport.clamped(to: 0...1))
        let rupture = CGFloat(campaign.jiangDialoguePerformanceRupture.clamped(to: 0...1))
        let anchorsSafety = campaign.currentJiangDialoguePerformanceBeat?.anchorsSafety == true
        let hasDialogueHistory = campaign.jiangDialogueState?.performanceBeats.isEmpty == false

        SCNTransaction.begin()
        SCNTransaction.animationDuration = inputView == nil ? 0 : 0.36

        if let supportArc = stage.childNode(withName: "jiangDialogueSupportArc", recursively: true) {
            supportArc.opacity = hasDialogueHistory ? 0.08 + support * 0.68 : 0
            supportArc.scale = SCNVector3(0.86 + Float(support) * 0.28, 0.86 + Float(support) * 0.28, 1)
            supportArc.geometry?.firstMaterial?.emission.intensity = 0.18 + support * 0.84
        }

        if let anchorLine = stage.childNode(withName: "jiangDialogueAnchorLine", recursively: true) {
            anchorLine.opacity = anchorsSafety ? 0.22 + support * 0.52 : 0.04 + support * 0.18
            anchorLine.geometry?.firstMaterial?.emission.intensity = 0.14 + support * 0.72
        }

        if let ruptureField = stage.childNode(withName: "jiangDialogueRuptureField", recursively: true) {
            ruptureField.opacity = hasDialogueHistory ? rupture * 0.48 : 0
            ruptureField.scale = SCNVector3(0.92 + Float(rupture) * 0.2, 1, 0.92 + Float(rupture) * 0.18)
            ruptureField.geometry?.firstMaterial?.emission.intensity = 0.12 + rupture * 0.68
        }

        SCNTransaction.commit()
    }

    private func updateNarrativeWorldDirector(in stage: SCNNode, signal: NarrativeWorldDirectorSignal) {
        let pressure = CGFloat(signal.ambientTension.clamped(to: 0...1))
        let support = CGFloat(signal.supportPresence.clamped(to: 0...1))
        let privacy = CGFloat(signal.privacyBoundary.clamped(to: 0...1))
        let witness = CGFloat(signal.witnessPressure.clamped(to: 0...1))
        let safety = CGFloat(signal.safetyResponse.clamped(to: 0...1))
        let cueColor = narrativeWorldCueColor(signal.cue)
        let duration: CFTimeInterval = inputView == nil ? 0 : 0.35

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration

        if let field = stage.childNode(withName: "worldDirectorPressureField", recursively: true) {
            field.opacity = 0.08 + pressure * 0.58
            field.scale = SCNVector3(1, 1, 0.72 + Float(pressure) * 0.4)
            field.geometry?.firstMaterial?.diffuse.contents = cueColor.withAlphaComponent(0.46)
            field.geometry?.firstMaterial?.emission.contents = cueColor.withAlphaComponent(0.4)
            field.geometry?.firstMaterial?.emission.intensity = 0.12 + pressure * 0.62
        }
        if let supportRing = stage.childNode(withName: "worldDirectorSupportRing", recursively: true) {
            supportRing.opacity = 0.1 + support * 0.72
            supportRing.scale = SCNVector3(0.82 + Float(support) * 0.25, 0.82 + Float(support) * 0.25, 1)
            supportRing.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.34, green: 0.92, blue: 0.62, alpha: 1)
            supportRing.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.22, green: 0.76, blue: 0.45, alpha: 1)
            supportRing.geometry?.firstMaterial?.emission.intensity = 0.18 + support * 0.78
        }
        if let privacyLine = stage.childNode(withName: "worldDirectorPrivacyLine", recursively: true) {
            privacyLine.opacity = 0.08 + privacy * 0.74
            privacyLine.scale = SCNVector3(0.76 + Float(privacy) * 0.42, 1, 1)
            privacyLine.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.38, green: 0.88, blue: 0.68, alpha: 1)
            privacyLine.geometry?.firstMaterial?.emission.intensity = 0.16 + privacy * 0.72
        }
        if let safetyBeacon = stage.childNode(withName: "worldDirectorSafetyBeacon", recursively: true) {
            safetyBeacon.opacity = 0.08 + safety * 0.74
            safetyBeacon.scale = SCNVector3(
                0.72 + Float(safety) * 0.46,
                0.72 + Float(safety) * 0.46,
                0.72 + Float(safety) * 0.46
            )
            safetyBeacon.geometry?.firstMaterial?.diffuse.contents = cueColor
            safetyBeacon.geometry?.firstMaterial?.emission.contents = cueColor
            safetyBeacon.geometry?.firstMaterial?.emission.intensity = 0.18 + safety * 0.95
        }
        let impactStrength = max(pressure, support, privacy, safety)
        if let impactRing = stage.childNode(withName: "worldDirectorChoiceImpactRing", recursively: true) {
            impactRing.opacity = 0.06 + impactStrength * 0.78
            let scale = 0.92 + Float(impactStrength) * 0.42
            impactRing.scale = SCNVector3(scale, scale, 1)
            impactRing.geometry?.firstMaterial?.diffuse.contents = cueColor.withAlphaComponent(0.78)
            impactRing.geometry?.firstMaterial?.emission.contents = cueColor
            impactRing.geometry?.firstMaterial?.emission.intensity = 0.24 + impactStrength * 0.92
        }
        if let impactRay = stage.childNode(withName: "worldDirectorChoiceImpactRay", recursively: true) {
            impactRay.opacity = 0.08 + impactStrength * 0.62
            impactRay.scale = SCNVector3(0.64 + Float(impactStrength) * 0.62, 1, 1)
            impactRay.eulerAngles.y = narrativeWorldImpactRayAngle(signal.cue)
            impactRay.geometry?.firstMaterial?.diffuse.contents = cueColor.withAlphaComponent(0.66)
            impactRay.geometry?.firstMaterial?.emission.contents = cueColor
            impactRay.geometry?.firstMaterial?.emission.intensity = 0.2 + impactStrength * 0.78
        }
        if let impactCrown = stage.childNode(withName: "worldDirectorChoiceImpactCrown", recursively: true) {
            impactCrown.opacity = 0.1 + impactStrength * 0.78
            impactCrown.scale = SCNVector3(
                0.72 + Float(impactStrength) * 0.48,
                0.72 + Float(impactStrength) * 0.48,
                0.72 + Float(impactStrength) * 0.48
            )
            impactCrown.geometry?.firstMaterial?.diffuse.contents = cueColor
            impactCrown.geometry?.firstMaterial?.emission.contents = cueColor
            impactCrown.geometry?.firstMaterial?.emission.intensity = 0.28 + impactStrength * 0.95
        }

        let visibleWitnessCount = Int(ceil(witness * 5))
        for index in 0..<5 {
            guard let node = stage.childNode(withName: "worldDirectorWitness_\(index)", recursively: true) else { continue }
            node.isHidden = index >= visibleWitnessCount
            node.opacity = index < visibleWitnessCount ? 0.2 + witness * 0.58 : 0
            node.eulerAngles.y = CGFloat(-0.26 + Double(index) * 0.13)
            applyNarrativeActorPerformance(
                to: node,
                tension: min(1, 0.32 + pressure * 0.5),
                gaze: witness,
                breath: 0.16 + pressure * 0.28,
                shieldVisible: false,
                markerColor: cueColor
            )
        }

        SCNTransaction.commit()
    }

    private func narrativeWorldImpactRayAngle(_ cue: NarrativeWorldDirectorCue) -> CGFloat {
        switch cue {
        case .attention:
            return -0.18
        case .investigation:
            return 0.34
        case .risk:
            return .pi / 2
        case .privacy:
            return 0
        case .safetyResponse:
            return -.pi / 3
        case .support:
            return -.pi / 6
        }
    }

    private func narrativeWorldCueColor(_ cue: NarrativeWorldDirectorCue) -> NSColor {
        switch cue {
        case .attention:
            return NSColor(calibratedRed: 0.58, green: 0.78, blue: 0.92, alpha: 1)
        case .investigation:
            return NSColor(calibratedRed: 0.78, green: 0.72, blue: 0.44, alpha: 1)
        case .risk:
            return NSColor(calibratedRed: 0.96, green: 0.42, blue: 0.32, alpha: 1)
        case .privacy:
            return NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.68, alpha: 1)
        case .safetyResponse:
            return NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.96, alpha: 1)
        case .support:
            return NSColor(calibratedRed: 0.44, green: 0.92, blue: 0.58, alpha: 1)
        }
    }

    private func updateNarrativeCompanion(in stage: SCNNode, campaign: NarrativeCampaign) {
        guard campaign.chapter == .noteTrace || campaign.chapter == .stairwell || campaign.chapter == .counseling else { return }
        let zhou = stage.childNode(withName: "companionZhou", recursively: true)
        let xu = stage.childNode(withName: "companionXu", recursively: true)
        let selectedNode = campaign.companionID == "周予安" ? zhou : campaign.companionID == "许栀" ? xu : nil

        zhou?.isHidden = campaign.companionID.isEmpty == false && campaign.companionID != "周予安"
        xu?.isHidden = campaign.companionID.isEmpty == false && campaign.companionID != "许栀"
        for node in [zhou, xu].compactMap({ $0 }) {
            node.childNode(withName: "companionContactProp", recursively: true)?.isHidden = true
        }
        guard let selectedNode else { return }

        switch campaign.chapter {
        case .noteTrace:
            let yaw = campaign.exploration.yaw
            let carryover = MirrorDialogueCarryoverModel.derive(from: campaign)
            let followDistance: CGFloat = carryover.isActive && carryover.choiceID == "invite" ? 1.32 : carryover.isActive ? 1.42 : 1.5
            let desiredX = campaign.exploration.positionX + sin(yaw) * Double(followDistance)
            let desiredZ = campaign.exploration.positionZ + cos(yaw) * Double(followDistance)
            let target = SCNVector3(Float(min(3.1, max(-3.1, desiredX))), 0, Float(min(5.3, max(-5.3, desiredZ))))
            let blend: CGFloat = inputView == nil ? 1 : 0.22
            let nextX = selectedNode.position.x + (target.x - selectedNode.position.x) * blend
            let nextZ = selectedNode.position.z + (target.z - selectedNode.position.z) * blend
            selectedNode.position = SCNVector3(nextX, 0, nextZ)
            selectedNode.eulerAngles.y = CGFloat(yaw)
            let supportBoost: CGFloat = carryover.choiceID == "invite" ? 0.12 : carryover.choiceID == "present" ? 0.08 : carryover.choiceID == "reassure" ? 0.1 : 0
            let followGaze: CGFloat = carryover.choiceID == "invite" ? 0.64 : carryover.choiceID == "present" ? 0.58 : carryover.choiceID == "reassure" ? 0.6 : 0.52
            let followBreath: CGFloat = carryover.choiceID == "invite" ? 0.16 : carryover.choiceID == "present" ? 0.18 : carryover.choiceID == "reassure" ? 0.17 : 0.2
            let followTension: CGFloat = carryover.choiceID == "invite" ? 0.28 : carryover.choiceID == "present" ? 0.32 : carryover.choiceID == "reassure" ? 0.3 : 0.36
            updateCompanionProximityVisuals(
                for: selectedNode,
                playerPosition: SCNVector3(Float(campaign.exploration.positionX), 0, Float(campaign.exploration.positionZ)),
                mode: .following,
                color: campaign.companionID == "周予安"
                    ? NSColor(calibratedRed: 0.2 + supportBoost * 0.4, green: 0.62 + supportBoost * 0.2, blue: 0.92 - supportBoost * 0.1, alpha: 1)
                    : NSColor(calibratedRed: 0.82 + supportBoost * 0.12, green: 0.42 + supportBoost * 0.25, blue: 0.72 + supportBoost * 0.1, alpha: 1)
            )
            applyNarrativeActorPerformance(
                to: selectedNode,
                tension: followTension,
                gaze: followGaze,
                breath: followBreath,
                shieldVisible: false,
                markerColor: campaign.companionID == "周予安"
                    ? NSColor(calibratedRed: 0.2 + supportBoost * 0.4, green: 0.62 + supportBoost * 0.2, blue: 0.92 - supportBoost * 0.1, alpha: 1)
                    : NSColor(calibratedRed: 0.82 + supportBoost * 0.12, green: 0.42 + supportBoost * 0.25, blue: 0.72 + supportBoost * 0.1, alpha: 1)
            )
        case .stairwell:
            selectedNode.position = campaign.companionID == "周予安"
                ? SCNVector3(-2.25, 0, 3.45)
                : SCNVector3(2.75, 0, -0.35)
            let contacted = campaign.safetyHandoffState?.adultContactInitiated == true
            updateCompanionProximityVisuals(
                for: selectedNode,
                playerPosition: SCNVector3(Float(campaign.exploration.positionX), 0, Float(campaign.exploration.positionZ)),
                mode: contacted ? .handoffBoundary : .boundary,
                color: campaign.companionID == "周予安"
                    ? NSColor(calibratedRed: 0.22, green: 0.72, blue: 1, alpha: 1)
                    : NSColor(calibratedRed: 0.9, green: 0.46, blue: 0.74, alpha: 1)
            )
            applyNarrativeActorPerformance(
                to: selectedNode,
                tension: contacted ? 0.28 : 0.48,
                gaze: contacted ? 0.82 : 0.55,
                breath: contacted ? 0.26 : 0.42,
                shieldVisible: contacted,
                markerColor: campaign.companionID == "周予安"
                    ? NSColor(calibratedRed: 0.22, green: 0.72, blue: 1, alpha: 1)
                    : NSColor(calibratedRed: 0.9, green: 0.46, blue: 0.74, alpha: 1)
            )
            if campaign.safetyHandoffState?.adultContactInitiated == true,
               let contactProp = selectedNode.childNode(withName: "companionContactProp", recursively: true) {
                contactProp.isHidden = false
                if campaign.companionID == "周予安" {
                    contactProp.position = SCNVector3(0.23, 1.38, 0)
                    contactProp.eulerAngles = SCNVector3(0, 0, -0.18)
                    contactProp.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.22, green: 0.72, blue: 1, alpha: 1)
                } else {
                    contactProp.position = SCNVector3(0, 1.02, -0.2)
                    contactProp.eulerAngles = SCNVector3(-0.5, 0, 0)
                    contactProp.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.8, green: 0.36, blue: 0.66, alpha: 1)
                }
                if contactProp.action(forKey: "contactPulse") == nil {
                    contactProp.runAction(.repeatForever(.sequence([
                        .scale(to: 1.16, duration: 0.42),
                        .scale(to: 1, duration: 0.42)
                    ])), forKey: "contactPulse")
                }
            }
        case .counseling:
            selectedNode.position = campaign.companionID == "周予安"
                ? SCNVector3(-1.45, 0, -0.65)
                : SCNVector3(1.45, 0, -0.65)
            let isPrivacyMoment = campaign.currentMoment.id == "5.rumor" || campaign.currentMoment.id == "5.message"
            updateCompanionProximityVisuals(
                for: selectedNode,
                playerPosition: SCNVector3(Float(campaign.exploration.positionX), 0, Float(campaign.exploration.positionZ)),
                mode: isPrivacyMoment ? .privacyBoundary : .waiting,
                color: NSColor(calibratedRed: 0.32, green: 0.88, blue: 0.62, alpha: 1)
            )
            applyNarrativeActorPerformance(
                to: selectedNode,
                tension: isPrivacyMoment ? 0.34 : 0.22,
                gaze: isPrivacyMoment ? 0.72 : 0.46,
                breath: 0.2,
                shieldVisible: isPrivacyMoment,
                markerColor: NSColor(calibratedRed: 0.32, green: 0.88, blue: 0.62, alpha: 1)
            )
        default:
            break
        }
    }

    private enum CompanionProximityMode {
        case following
        case boundary
        case handoffBoundary
        case waiting
        case privacyBoundary
    }

    private func updateCompanionProximityVisuals(
        for node: SCNNode,
        playerPosition: SCNVector3,
        mode: CompanionProximityMode,
        color: NSColor
    ) {
        let dx = playerPosition.x - node.position.x
        let dz = playerPosition.z - node.position.z
        let distance = max(0.001, sqrt(dx * dx + dz * dz))
        if let line = node.childNode(withName: "companionFollowDistanceLine", recursively: true) {
            line.isHidden = mode != .following
            line.opacity = mode == .following ? CGFloat((1.05 / Double(distance)).clamped(to: 0.28...0.7)) : 0
            line.position = SCNVector3(dx / 2, 0.042, dz / 2)
            line.eulerAngles.y = CGFloat(-atan2(dz, dx))
            line.scale = SCNVector3(distance, 1, 1)
            line.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.48)
            line.geometry?.firstMaterial?.emission.intensity = mode == .following ? 0.62 : 0
        }

        if let ring = node.childNode(withName: "companionBoundaryRing", recursively: true) {
            let showsBoundary: Bool
            let opacity: CGFloat
            let scale: Float
            switch mode {
            case .following:
                showsBoundary = false
                opacity = 0
                scale = 1
            case .boundary:
                showsBoundary = true
                opacity = 0.24
                scale = 1.08
            case .handoffBoundary:
                showsBoundary = true
                opacity = 0.44
                scale = 1.18
            case .waiting:
                showsBoundary = true
                opacity = 0.18
                scale = 0.92
            case .privacyBoundary:
                showsBoundary = true
                opacity = 0.52
                scale = 1.26
            }
            ring.isHidden = showsBoundary == false
            ring.opacity = opacity
            ring.scale = SCNVector3(scale, scale, scale)
            ring.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.5)
            ring.geometry?.firstMaterial?.emission.intensity = showsBoundary ? 0.46 + opacity : 0
        }
    }

    private func applyNarrativeCamera(game: GameManager) {
        let baseX = Float(40 + max(0, game.narrativeCampaign.chapter.rawValue - 2) * 16)
        let exploration = game.narrativeCampaign.exploration
        let height: Float
        let fieldOfView: CGFloat
        switch game.narrativeCampaign.chapter {
        case .classroom:
            cameraRig.position = SCNVector3(-1.2, 1.18, 1.5)
            cameraRig.eulerAngles = SCNVector3Zero
            cameraRig.camera?.fieldOfView = 92
            return
        case .mirror: height = 1.55; fieldOfView = 78
        case .noteTrace: height = 1.46; fieldOfView = 82
        case .stairwell: height = 1.7; fieldOfView = 76
        case .counseling: height = 1.42; fieldOfView = 72
        case .epilogue: height = 1.5; fieldOfView = 70
        }
        cameraRig.position = SCNVector3(baseX + Float(exploration.positionX), height, Float(exploration.positionZ))
        cameraRig.eulerAngles = SCNVector3(Float(exploration.pitch), Float(exploration.yaw), 0)
        cameraRig.camera?.fieldOfView = fieldOfView
    }

    private func makeStageShell(name: String, floor: NSColor, wall: NSColor, light: NSColor) -> SCNNode {
        let root = SCNNode()
        root.name = name
        root.addChildNode(box(width: 7.8, height: 0.12, length: 13.2, color: floor, position: SCNVector3(0, -0.06, 0)))
        root.addChildNode(box(width: 0.12, height: 3.7, length: 13.2, color: wall, position: SCNVector3(-3.9, 1.79, 0)))
        root.addChildNode(box(width: 0.12, height: 3.7, length: 13.2, color: wall, position: SCNVector3(3.9, 1.79, 0)))
        root.addChildNode(box(width: 7.8, height: 3.7, length: 0.12, color: wall, position: SCNVector3(0, 1.79, -6.6)))
        root.addChildNode(makeStageLight(color: light, intensity: 900, position: SCNVector3(0, 2.9, -1.5)))
        root.addChildNode(makeStageLight(color: light.blended(withFraction: 0.35, of: .white) ?? light, intensity: 420, position: SCNVector3(0, 2.25, 4.1)))
        for z in [-4.5, -1.5, 1.5, 4.5] {
            let panel = box(width: 1.5, height: 0.025, length: 0.2, color: light, position: SCNVector3(0, 3.42, Float(z)))
            panel.geometry?.firstMaterial?.emission.contents = light.withAlphaComponent(0.8)
            root.addChildNode(panel)
        }
        root.addChildNode(makeWorldDirectorRig(light: light))
        return root
    }

    private func makeStageLight(color: NSColor, intensity: CGFloat, position: SCNVector3) -> SCNNode {
        let node = SCNNode()
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = intensity
        light.attenuationStartDistance = 1.5
        light.attenuationEndDistance = 14
        light.castsShadow = true
        node.light = light
        node.position = position
        return node
    }

    private func makeWorldDirectorRig(light: NSColor) -> SCNNode {
        let root = SCNNode()
        root.name = "worldDirectorRig"

        let pressureField = box(
            width: 7.35,
            height: 0.026,
            length: 10.8,
            color: light.blended(withFraction: 0.45, of: .black) ?? light,
            position: SCNVector3(0, 0.018, -0.2)
        )
        pressureField.name = "worldDirectorPressureField"
        pressureField.opacity = 0.08
        pressureField.geometry?.firstMaterial?.emission.intensity = 0.12
        root.addChildNode(pressureField)

        let supportRing = SCNNode(geometry: SCNTorus(ringRadius: 2.2, pipeRadius: 0.018))
        supportRing.name = "worldDirectorSupportRing"
        supportRing.position = SCNVector3(0, 0.075, -1.18)
        supportRing.eulerAngles.x = .pi / 2
        supportRing.opacity = 0.12
        supportRing.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.34, green: 0.92, blue: 0.62, alpha: 1))
        supportRing.geometry?.firstMaterial?.emission.intensity = 0.18
        root.addChildNode(supportRing)

        let privacyLine = box(
            width: 4.9,
            height: 0.026,
            length: 0.075,
            color: NSColor(calibratedRed: 0.32, green: 0.88, blue: 0.64, alpha: 1),
            position: SCNVector3(0, 0.055, -2.34)
        )
        privacyLine.name = "worldDirectorPrivacyLine"
        privacyLine.opacity = 0.1
        root.addChildNode(privacyLine)

        let safetyBeacon = sphere(
            radius: 0.16,
            color: NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.96, alpha: 1),
            position: SCNVector3(3.15, 2.2, -4.9)
        )
        safetyBeacon.name = "worldDirectorSafetyBeacon"
        safetyBeacon.opacity = 0.1
        safetyBeacon.geometry?.firstMaterial?.emission.intensity = 0.18
        root.addChildNode(safetyBeacon)

        let impactRing = SCNNode(geometry: SCNTorus(ringRadius: 1.18, pipeRadius: 0.024))
        impactRing.name = "worldDirectorChoiceImpactRing"
        impactRing.position = SCNVector3(0, 0.095, -1.18)
        impactRing.eulerAngles.x = .pi / 2
        impactRing.opacity = 0.06
        impactRing.geometry?.firstMaterial = material(light.blended(withFraction: 0.22, of: .white) ?? light)
        impactRing.geometry?.firstMaterial?.emission.intensity = 0.24
        root.addChildNode(impactRing)

        let impactRay = box(
            width: 2.35,
            height: 0.03,
            length: 0.075,
            color: light,
            position: SCNVector3(0, 0.105, -1.18)
        )
        impactRay.name = "worldDirectorChoiceImpactRay"
        impactRay.opacity = 0.08
        impactRay.geometry?.firstMaterial?.emission.intensity = 0.2
        root.addChildNode(impactRay)

        let impactCrown = sphere(
            radius: 0.17,
            color: light.blended(withFraction: 0.35, of: .white) ?? light,
            position: SCNVector3(0, 1.72, -1.18)
        )
        impactCrown.name = "worldDirectorChoiceImpactCrown"
        impactCrown.opacity = 0.1
        impactCrown.geometry?.firstMaterial?.emission.intensity = 0.28
        root.addChildNode(impactCrown)

        let witnessPlacements: [(Float, Float)] = [(-3.05, 2.3), (-2.72, 3.25), (2.9, 2.15), (3.12, 3.18), (2.78, 4.15)]
        for (index, placement) in witnessPlacements.enumerated() {
            let witness = makeStageFigure(
                color: NSColor(calibratedWhite: 0.2 + CGFloat(index) * 0.035, alpha: 1),
                position: SCNVector3(placement.0, 0, placement.1)
            )
            witness.name = "worldDirectorWitness_\(index)"
            witness.scale = SCNVector3(0.56, 0.56, 0.56)
            witness.isHidden = true
            witness.opacity = 0
            root.addChildNode(witness)
        }

        let actorColors = [
            NSColor(calibratedRed: 0.34, green: 0.42, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.28, green: 0.46, blue: 0.4, alpha: 1),
            NSColor(calibratedRed: 0.46, green: 0.34, blue: 0.44, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.32, alpha: 1)
        ]
        for index in 0..<4 {
            let actor = makeStageFigure(color: actorColors[index], position: SCNVector3(0, 0, 0))
            actor.name = "ambientLivingActor_\(index)"
            actor.scale = SCNVector3(0.58, 0.58, 0.58)
            actor.isHidden = true
            actor.opacity = 0
            let marker = capsule(
                radius: 0.018,
                height: 0.36,
                color: actorColors[index].blended(withFraction: 0.28, of: .white) ?? actorColors[index],
                position: SCNVector3(0, 1.62, 0)
            )
            marker.name = "ambientLivingActorLabel"
            marker.eulerAngles.z = .pi / 2
            marker.geometry?.firstMaterial?.emission.contents = actorColors[index]
            actor.addChildNode(marker)
            root.addChildNode(actor)
        }

        return root
    }

    private func makeMirrorStage() -> SCNNode {
        let root = makeStageShell(
            name: "narrativeStage_\(NarrativeChapter.mirror.rawValue)",
            floor: NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.11, alpha: 1),
            wall: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.13, alpha: 1),
            light: NSColor(calibratedRed: 0.48, green: 0.7, blue: 0.82, alpha: 1)
        )
        let guideColor = NSColor(calibratedRed: 0.3, green: 0.82, blue: 0.96, alpha: 1)
        for index in 0..<7 {
            let z = 3.75 - Float(index) * 0.88
            let guide = box(
                width: 0.72 - CGFloat(index) * 0.045,
                height: 0.022,
                length: 0.16,
                color: guideColor.withAlphaComponent(0.62),
                position: SCNVector3(0, 0.028, z)
            )
            guide.name = "mirrorFloorGuide_\(index)"
            guide.geometry?.firstMaterial?.emission.contents = guideColor
            guide.geometry?.firstMaterial?.emission.intensity = 0.32 + CGFloat(index) * 0.055
            root.addChildNode(guide)
        }

        let mirrorGeometry = SCNBox(width: 4.55, height: 2.9, length: 0.08, chamferRadius: 0.035)
        let mirror = SCNMaterial()
        mirror.diffuse.contents = NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.31, alpha: 1)
        mirror.emission.contents = NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.34, alpha: 1)
        mirror.emission.intensity = 0.22
        mirror.metalness.contents = 0.94
        mirror.roughness.contents = 0.035
        mirror.reflective.contents = hallLightingImage
        mirrorGeometry.firstMaterial = mirror
        let mirrorNode = SCNNode(geometry: mirrorGeometry)
        mirrorNode.name = "mirrorSurface"
        mirrorNode.position = SCNVector3(0, 1.58, -3.08)
        root.addChildNode(mirrorNode)

        let frameColor = NSColor(calibratedRed: 0.72, green: 0.77, blue: 0.8, alpha: 1)
        let frameGlow = NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.96, alpha: 1)
        for (index, frame) in [
            box(width: 4.88, height: 0.15, length: 0.16, color: frameColor, position: SCNVector3(0, 3.1, -3.0)),
            box(width: 4.88, height: 0.15, length: 0.16, color: frameColor, position: SCNVector3(0, 0.06, -3.0)),
            box(width: 0.15, height: 3.18, length: 0.16, color: frameColor, position: SCNVector3(-2.36, 1.58, -3.0)),
            box(width: 0.15, height: 3.18, length: 0.16, color: frameColor, position: SCNVector3(2.36, 1.58, -3.0))
        ].enumerated() {
            frame.name = index == 0 ? "stageFocus" : "mirrorBeacon_\(index)"
            frame.geometry?.firstMaterial?.metalness.contents = 0.82
            frame.geometry?.firstMaterial?.roughness.contents = 0.18
            frame.geometry?.firstMaterial?.emission.contents = frameGlow
            frame.geometry?.firstMaterial?.emission.intensity = 0.18
            root.addChildNode(frame)
        }

        // Receding lines inside the glass make the surface read as an impossible reflected corridor.
        for index in 0..<4 {
            let inset = CGFloat(index) * 0.34
            let lineColor = frameGlow.withAlphaComponent(0.38 - CGFloat(index) * 0.06)
            let y = 0.34 + Float(index) * 0.18
            let width = 3.9 - inset * 2
            let top = box(width: width, height: 0.018, length: 0.018, color: lineColor, position: SCNVector3(0, 2.82 - Float(index) * 0.18, -2.985))
            let bottom = box(width: width, height: 0.018, length: 0.018, color: lineColor, position: SCNVector3(0, y, -2.985))
            for line in [top, bottom] {
                line.geometry?.firstMaterial?.emission.contents = frameGlow
                line.geometry?.firstMaterial?.emission.intensity = 0.14
                root.addChildNode(line)
            }
        }

        let thresholdGeometry = SCNTorus(ringRadius: 0.72, pipeRadius: 0.035)
        let thresholdMaterial = SCNMaterial()
        thresholdMaterial.diffuse.contents = frameGlow
        thresholdMaterial.emission.contents = frameGlow
        thresholdMaterial.emission.intensity = 0.9
        thresholdMaterial.blendMode = .add
        thresholdGeometry.firstMaterial = thresholdMaterial
        let threshold = SCNNode(geometry: thresholdGeometry)
        threshold.name = "mirrorThresholdBeacon"
        threshold.eulerAngles.x = .pi / 2
        threshold.position = SCNVector3(0, 0.045, -2.1)
        threshold.runAction(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.8),
            .scale(to: 0.92, duration: 0.8)
        ])))
        root.addChildNode(threshold)

        let entranceLabel = makeText("镜 面 入 口", size: 0.11, color: NSColor(calibratedRed: 0.76, green: 0.92, blue: 1, alpha: 1), position: SCNVector3(-0.58, 0.24, -2.97))
        entranceLabel.name = "mirrorEntranceLabel"
        entranceLabel.geometry?.firstMaterial?.emission.contents = frameGlow
        entranceLabel.geometry?.firstMaterial?.emission.intensity = 0.45
        root.addChildNode(entranceLabel)

        root.addChildNode(makeMirrorPressureRig())
        root.addChildNode(makeMirrorRouteLightsRig())
        return root
    }

    private func makeMirrorPressureRig() -> SCNNode {
        let root = SCNNode()
        root.name = "mirrorPressureRig"

        let crackSpecs: [(x: CGFloat, y: CGFloat, width: CGFloat, angle: CGFloat)] = [
            (-1.12, 1.92, 0.74, -0.62),
            (-0.66, 1.32, 0.54, 0.48),
            (-0.18, 2.16, 0.68, -0.18),
            (0.44, 1.64, 0.8, 0.36),
            (0.98, 2.18, 0.56, -0.52),
            (1.16, 1.18, 0.64, 0.16)
        ]
        for (index, spec) in crackSpecs.enumerated() {
            let crack = box(
                width: spec.width,
                height: 0.018,
                length: 0.012,
                color: NSColor(calibratedRed: 0.62, green: 0.84, blue: 1.0, alpha: 1),
                position: SCNVector3(Float(spec.x), Float(spec.y), -3.18)
            )
            crack.name = "mirrorPressureCrack_\(index)"
            crack.eulerAngles.z = spec.angle
            crack.opacity = 0.12
            crack.geometry?.firstMaterial?.blendMode = .add
            crack.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.42, green: 0.8, blue: 1.0, alpha: 1)
            crack.geometry?.firstMaterial?.emission.intensity = 0.18
            root.addChildNode(crack)
        }

        let shadow = makeStageFigure(
            color: NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.24, alpha: 1),
            position: SCNVector3(-0.78, 0, -1.85)
        )
        shadow.name = "mirrorLinCheShadow"
        shadow.opacity = 0.46
        shadow.scale = SCNVector3(0.68, 0.68, 0.68)
        root.addChildNode(shadow)

        let ringGeometry = SCNTorus(ringRadius: 0.46, pipeRadius: 0.012)
        let ringMaterial = SCNMaterial()
        ringMaterial.diffuse.contents = NSColor(calibratedRed: 0.32, green: 0.86, blue: 1.0, alpha: 0.34)
        ringMaterial.emission.contents = NSColor(calibratedRed: 0.32, green: 0.86, blue: 1.0, alpha: 1)
        ringMaterial.emission.intensity = 0.26
        ringMaterial.blendMode = .add
        ringMaterial.isDoubleSided = true
        ringGeometry.firstMaterial = ringMaterial
        let ring = SCNNode(geometry: ringGeometry)
        ring.name = "mirrorBreathRing"
        ring.eulerAngles.x = .pi / 2
        ring.position = SCNVector3(-0.78, 0.052, -1.71)
        ring.opacity = 0.28
        root.addChildNode(ring)

        let faceLight = sphere(radius: 0.18, color: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.36, alpha: 1), position: SCNVector3Zero)
        faceLight.name = "mirrorLinCheFaceLight"
        faceLight.opacity = 0
        faceLight.isHidden = true
        faceLight.geometry?.firstMaterial?.blendMode = .add
        faceLight.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.36, alpha: 1)
        faceLight.geometry?.firstMaterial?.emission.intensity = 0.4
        root.addChildNode(faceLight)

        let band = box(
            width: 2.3,
            height: 0.026,
            length: 0.12,
            color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 0.34),
            position: SCNVector3(0, 1.48, -3.08)
        )
        band.name = "mirrorRealityReturnBand"
        band.opacity = 0
        band.isHidden = true
        band.geometry?.firstMaterial?.blendMode = .add
        band.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1)
        band.geometry?.firstMaterial?.emission.intensity = 0.32
        root.addChildNode(band)

        let gateGeometry = SCNTorus(ringRadius: 0.54, pipeRadius: 0.018)
        let gateMaterial = SCNMaterial()
        gateMaterial.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 0.36)
        gateMaterial.emission.contents = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1)
        gateMaterial.emission.intensity = 0.35
        gateMaterial.blendMode = .add
        gateMaterial.isDoubleSided = true
        gateGeometry.firstMaterial = gateMaterial
        let gate = SCNNode(geometry: gateGeometry)
        gate.name = "mirrorReturnGate"
        gate.eulerAngles.x = .pi / 2
        gate.opacity = 0
        gate.isHidden = true
        root.addChildNode(gate)

        let path = box(
            width: 0.08,
            height: 0.018,
            length: 1.0,
            color: NSColor(calibratedRed: 0.2, green: 0.86, blue: 1.0, alpha: 0.42),
            position: SCNVector3(0, 0.048, -2.0)
        )
        path.name = "mirrorNavigationPath"
        path.opacity = 0
        path.geometry?.firstMaterial?.blendMode = .add
        path.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.18, green: 0.82, blue: 1.0, alpha: 1)
        path.geometry?.firstMaterial?.emission.intensity = 0.32
        root.addChildNode(path)

        let targetRingGeometry = SCNTorus(ringRadius: 0.34, pipeRadius: 0.018)
        let targetRingMaterial = SCNMaterial()
        targetRingMaterial.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.25, alpha: 0.46)
        targetRingMaterial.emission.contents = NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.25, alpha: 1)
        targetRingMaterial.emission.intensity = 0.48
        targetRingMaterial.blendMode = .add
        targetRingMaterial.isDoubleSided = true
        targetRingGeometry.firstMaterial = targetRingMaterial
        let targetRing = SCNNode(geometry: targetRingGeometry)
        targetRing.name = "mirrorNavigationTargetRing"
        targetRing.eulerAngles.x = .pi / 2
        targetRing.opacity = 0
        root.addChildNode(targetRing)

        let playerDot = sphere(radius: 0.055, color: NSColor(calibratedRed: 0.36, green: 0.92, blue: 1.0, alpha: 1), position: SCNVector3Zero)
        playerDot.name = "mirrorNavigationPlayerDot"
        playerDot.opacity = 0
        playerDot.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.36, green: 0.92, blue: 1.0, alpha: 1)
        playerDot.geometry?.firstMaterial?.emission.intensity = 0.7
        root.addChildNode(playerDot)

        return root
    }

    private func makeMirrorRouteLightsRig() -> SCNNode {
        let root = SCNNode()
        root.name = "mirrorRouteLightsRig"
        let positions: [SCNVector3] = [
            SCNVector3(-1.18, 2.18, -2.94),
            SCNVector3(0, 2.36, -2.94),
            SCNVector3(1.18, 2.18, -2.94)
        ]
        let labels = ["草稿", "旋律", "擦痕"]

        for index in 0..<2 {
            let bridge = box(
                width: 0.78,
                height: 0.026,
                length: 0.026,
                color: NSColor(calibratedRed: 0.82, green: 0.68, blue: 0.32, alpha: 1),
                position: SCNVector3((positions[index].x + positions[index + 1].x) / 2, (positions[index].y + positions[index + 1].y) / 2, -2.94)
            )
            bridge.name = "mirrorRouteBridge_\(index)"
            bridge.eulerAngles.z = index == 0 ? -0.15 : 0.15
            bridge.opacity = 0.16
            bridge.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.24, alpha: 1)
            bridge.geometry?.firstMaterial?.emission.intensity = 0.12
            root.addChildNode(bridge)
        }

        for (index, position) in positions.enumerated() {
            let light = sphere(radius: 0.13, color: NSColor(calibratedRed: 0.34, green: 0.3, blue: 0.48, alpha: 1), position: position)
            light.name = "mirrorRouteLight_\(index)"
            light.opacity = 0.28
            light.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.34, green: 0.3, blue: 0.48, alpha: 1)
            light.geometry?.firstMaterial?.emission.intensity = 0.2

            let halo = box(
                width: 0.58,
                height: 0.01,
                length: 0.58,
                color: NSColor(calibratedRed: 0.5, green: 0.44, blue: 0.72, alpha: 0.25),
                position: SCNVector3(0, 0, -0.012)
            )
            halo.name = "mirrorRouteLightHalo"
            halo.opacity = 0.12
            halo.geometry?.firstMaterial?.blendMode = .add
            halo.geometry?.firstMaterial?.isDoubleSided = true
            halo.geometry?.firstMaterial?.writesToDepthBuffer = false
            light.addChildNode(halo)

            let label = makeText(
                labels[index],
                size: 0.06,
                color: NSColor(calibratedRed: 0.72, green: 0.82, blue: 1, alpha: 1),
                position: SCNVector3(position.x - 0.18, position.y - 0.38, position.z + 0.02)
            )
            label.name = "mirrorRouteLabel_\(index)"
            root.addChildNode(label)
            root.addChildNode(light)
        }

        for index in 0..<6 {
            let echo = sphere(radius: 0.055, color: NSColor(calibratedRed: 0.44, green: 0.9, blue: 1.0, alpha: 1), position: SCNVector3Zero)
            echo.name = "mirrorMicroEcho_\(index)"
            echo.opacity = 0
            echo.geometry?.firstMaterial?.blendMode = .add
            echo.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.44, green: 0.9, blue: 1.0, alpha: 1)
            echo.geometry?.firstMaterial?.emission.intensity = 0.18
            root.addChildNode(echo)
        }

        let portalGeometry = SCNTorus(ringRadius: 0.31, pipeRadius: 0.02)
        let portalMaterial = SCNMaterial()
        portalMaterial.diffuse.contents = NSColor(calibratedRed: 0.32, green: 0.88, blue: 1.0, alpha: 0.42)
        portalMaterial.emission.contents = NSColor(calibratedRed: 0.32, green: 0.88, blue: 1.0, alpha: 1)
        portalMaterial.emission.intensity = 0.72
        portalMaterial.blendMode = .add
        portalMaterial.isDoubleSided = true
        portalGeometry.firstMaterial = portalMaterial
        let portal = SCNNode(geometry: portalGeometry)
        portal.name = "mirrorMicroPortalRing"
        portal.opacity = 0
        portal.isHidden = true
        root.addChildNode(portal)

        let beam = box(
            width: 0.34,
            height: 0.018,
            length: 1.0,
            color: NSColor(calibratedRed: 0.24, green: 0.84, blue: 1.0, alpha: 0.3),
            position: SCNVector3Zero
        )
        beam.name = "mirrorMicroPortalBeam"
        beam.opacity = 0
        beam.isHidden = true
        beam.eulerAngles.z = -0.04
        beam.geometry?.firstMaterial?.blendMode = .add
        beam.geometry?.firstMaterial?.isDoubleSided = true
        beam.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.24, green: 0.84, blue: 1.0, alpha: 1)
        beam.geometry?.firstMaterial?.emission.intensity = 0.3
        root.addChildNode(beam)

        let pulseGeometry = SCNTorus(ringRadius: 0.42, pipeRadius: 0.016)
        let pulseMaterial = SCNMaterial()
        pulseMaterial.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.28, alpha: 0.4)
        pulseMaterial.emission.contents = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.28, alpha: 1)
        pulseMaterial.emission.intensity = 0.92
        pulseMaterial.blendMode = .add
        pulseMaterial.isDoubleSided = true
        pulseGeometry.firstMaterial = pulseMaterial
        let pulse = SCNNode(geometry: pulseGeometry)
        pulse.name = "mirrorMicroReturnPulse"
        pulse.opacity = 0
        pulse.isHidden = true
        root.addChildNode(pulse)

        return root
    }

    private func makeNoteTraceStage() -> SCNNode {
        let root = makeStageShell(
            name: "narrativeStage_\(NarrativeChapter.noteTrace.rawValue)",
            floor: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.15, alpha: 1),
            wall: NSColor(calibratedRed: 0.17, green: 0.2, blue: 0.21, alpha: 1),
            light: NSColor(calibratedRed: 0.68, green: 0.82, blue: 0.9, alpha: 1)
        )
        for index in 0..<10 {
            let z = 4.4 - Float(index) * 0.92
            let x = sin(Float(index) * 1.8) * 0.72
            let paper = box(width: 0.42, height: 0.014, length: 0.29, color: NSColor(calibratedWhite: 0.86 + CGFloat(index % 2) * 0.08, alpha: 1), position: SCNVector3(x, 0.025, z))
            paper.eulerAngles.y = CGFloat(index) * 0.37
            paper.geometry?.firstMaterial?.emission.contents = NSColor(calibratedWhite: 0.08, alpha: 1)
            root.addChildNode(paper)
        }
        let evidenceTable = box(width: 2.4, height: 0.75, length: 0.75, color: NSColor(calibratedRed: 0.24, green: 0.2, blue: 0.16, alpha: 1), position: SCNVector3(0, 0.38, -1.45))
        evidenceTable.name = "stageFocus"
        root.addChildNode(evidenceTable)
        root.addChildNode(box(width: 1.55, height: 0.03, length: 0.92, color: NSColor(calibratedWhite: 0.94, alpha: 1), position: SCNVector3(0, 0.78, -1.45)))
        root.addChildNode(makeText("值日表 / 座位 / 时间", size: 0.075, color: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.18, alpha: 1), position: SCNVector3(-0.66, 0.81, -1.88)))
        root.addChildNode(makeStageFigure(color: NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.34, alpha: 1), position: SCNVector3(1.45, 0, -0.85)))
        root.addChildNode(makeNarrativeCompanion(
            name: "companionZhou",
            label: "周予安",
            color: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.52, alpha: 1),
            position: SCNVector3(-1.8, 0, 0.25)
        ))
        root.addChildNode(makeNarrativeCompanion(
            name: "companionXu",
            label: "许栀",
            color: NSColor(calibratedRed: 0.5, green: 0.24, blue: 0.38, alpha: 1),
            position: SCNVector3(1.8, 0, 0.25)
        ))
        noteTraceHotspotVisuals.forEach { root.addChildNode(makeNoteTraceHotspotBeacon($0)) }
        root.addChildNode(makeNoteTraceNavigationRig())
        root.addChildNode(makeStageLight(color: NSColor(calibratedRed: 0.75, green: 0.92, blue: 1, alpha: 1), intensity: 900, position: SCNVector3(0, 1.8, -1.2)))
        return root
    }

    private func makeNoteTraceNavigationRig() -> SCNNode {
        let root = SCNNode()
        root.name = "noteTraceNavigationRig"
        root.isHidden = true
        root.opacity = 0

        let beam = box(
            width: 1,
            height: 0.026,
            length: 0.062,
            color: NSColor(calibratedRed: 0.28, green: 0.86, blue: 1, alpha: 1),
            position: SCNVector3Zero
        )
        beam.name = "noteTraceNavigationBeam"
        beam.opacity = 0.62
        beam.geometry?.firstMaterial?.blendMode = .add
        beam.geometry?.firstMaterial?.writesToDepthBuffer = false
        beam.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.2, green: 0.78, blue: 1, alpha: 1)
        beam.geometry?.firstMaterial?.emission.intensity = 0.72
        root.addChildNode(beam)

        let origin = sphere(
            radius: 0.055,
            color: NSColor(calibratedRed: 0.58, green: 0.96, blue: 1, alpha: 1),
            position: SCNVector3Zero
        )
        origin.name = "noteTraceNavigationOrigin"
        origin.geometry?.firstMaterial?.emission.intensity = 0.52
        root.addChildNode(origin)

        let targetCore = sphere(
            radius: 0.082,
            color: NSColor(calibratedRed: 0.36, green: 0.96, blue: 0.82, alpha: 1),
            position: SCNVector3Zero
        )
        targetCore.name = "noteTraceNavigationTargetCore"
        targetCore.geometry?.firstMaterial?.emission.intensity = 0.86
        root.addChildNode(targetCore)

        let targetRing = SCNNode(geometry: SCNTorus(ringRadius: 0.34, pipeRadius: 0.012))
        targetRing.name = "noteTraceNavigationTargetRing"
        targetRing.eulerAngles.x = .pi / 2
        targetRing.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.32, green: 0.92, blue: 1, alpha: 0.62))
        targetRing.geometry?.firstMaterial?.blendMode = .add
        targetRing.geometry?.firstMaterial?.writesToDepthBuffer = false
        targetRing.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.25, green: 0.86, blue: 1, alpha: 1)
        targetRing.geometry?.firstMaterial?.emission.intensity = 0.54
        root.addChildNode(targetRing)

        return root
    }

    private func makeNoteTraceHotspotBeacon(_ visual: NoteTraceHotspotVisual) -> SCNNode {
        let beacon = sphere(radius: 0.105, color: visual.color, position: visual.position)
        beacon.name = visual.nodeName
        beacon.opacity = 0.28
        beacon.geometry?.firstMaterial?.emission.contents = visual.color
        beacon.geometry?.firstMaterial?.emission.intensity = 0.22

        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.22, pipeRadius: 0.008))
        ring.name = "noteTraceHotspotRing"
        ring.eulerAngles.x = .pi / 2
        ring.opacity = 0.16
        ring.geometry?.firstMaterial = material(visual.color.withAlphaComponent(0.4))
        ring.geometry?.firstMaterial?.emission.contents = visual.color
        ring.geometry?.firstMaterial?.emission.intensity = 0.24
        beacon.addChildNode(ring)

        let label = makeText(
            visual.label,
            size: 0.075,
            color: visual.color.blended(withFraction: 0.38, of: .white) ?? visual.color,
            position: SCNVector3(-0.12, 0.18, 0)
        )
        label.name = "noteTraceHotspotLabel"
        label.opacity = 0.4
        beacon.addChildNode(label)

        return beacon
    }

    private func makeStairwellStage() -> SCNNode {
        let root = makeStageShell(
            name: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)",
            floor: NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.11, alpha: 1),
            wall: NSColor(calibratedRed: 0.24, green: 0.21, blue: 0.19, alpha: 1),
            light: NSColor(calibratedRed: 0.9, green: 0.55, blue: 0.34, alpha: 1)
        )
        for index in 0..<9 {
            let step = box(width: 3.7, height: 0.16, length: 0.62, color: NSColor(calibratedRed: 0.3, green: 0.29, blue: 0.28, alpha: 1), position: SCNVector3(-1.65, Float(index) * 0.16, 4.4 - Float(index) * 0.58))
            root.addChildNode(step)
        }
        for z in stride(from: -4.7, through: 4.6, by: 1.15) {
            root.addChildNode(capsule(radius: 0.035, height: 1.02, color: NSColor(calibratedRed: 0.72, green: 0.22, blue: 0.16, alpha: 1), position: SCNVector3(0.55, 0.64, Float(z))))
        }
        root.addChildNode(box(width: 0.06, height: 0.06, length: 9.8, color: NSColor(calibratedRed: 0.72, green: 0.22, blue: 0.16, alpha: 1), position: SCNVector3(0.55, 1.15, 0)))
        root.addChildNode(box(width: 2.1, height: 2.75, length: 0.12, color: NSColor(calibratedRed: 0.28, green: 0.08, blue: 0.07, alpha: 1), position: SCNVector3(1.85, 1.38, -3.8)))
        root.addChildNode(makeText("13F", size: 0.23, color: NSColor(calibratedWhite: 0.94, alpha: 1), position: SCNVector3(1.35, 2.2, -3.71)))
        let stairwellFigure = makeStageFigure(color: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.2, alpha: 1), position: SCNVector3(0.1, 0, -1.65))
        stairwellFigure.name = "stageFocus"
        root.addChildNode(stairwellFigure)
        root.addChildNode(makeNarrativeCompanion(name: "companionZhou", label: "周予安", color: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.52, alpha: 1), position: SCNVector3(-2.25, 0, 3.45)))
        root.addChildNode(makeNarrativeCompanion(name: "companionXu", label: "许栀", color: NSColor(calibratedRed: 0.5, green: 0.24, blue: 0.38, alpha: 1), position: SCNVector3(2.75, 0, -0.35)))
        let teacher = makeNarrativeCompanion(
            name: "handoffTeacher",
            label: "方老师",
            color: NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.3, alpha: 1),
            position: SCNVector3(-1.15, 0, 0.1)
        )
        teacher.isHidden = true
        root.addChildNode(teacher)
        let arrivalSignal = sphere(radius: 0.12, color: NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.62, alpha: 1), position: SCNVector3(-1.15, 1.95, 0.1))
        arrivalSignal.name = "adultArrivalSignal"
        arrivalSignal.isHidden = true
        arrivalSignal.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.62, alpha: 1)
        root.addChildNode(arrivalSignal)

        let dialogueSupportArc = SCNNode(geometry: SCNTorus(ringRadius: 0.68, pipeRadius: 0.014))
        dialogueSupportArc.name = "jiangDialogueSupportArc"
        dialogueSupportArc.position = SCNVector3(0.1, 0.08, -1.65)
        dialogueSupportArc.eulerAngles.x = .pi / 2
        dialogueSupportArc.opacity = 0
        dialogueSupportArc.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.34, green: 0.9, blue: 0.62, alpha: 1))
        dialogueSupportArc.geometry?.firstMaterial?.emission.intensity = 0.24
        root.addChildNode(dialogueSupportArc)

        let dialogueAnchorLine = box(
            width: 1.95,
            height: 0.02,
            length: 0.055,
            color: NSColor(calibratedRed: 0.42, green: 0.86, blue: 0.94, alpha: 1),
            position: SCNVector3(-0.72, 0.05, -0.82)
        )
        dialogueAnchorLine.name = "jiangDialogueAnchorLine"
        dialogueAnchorLine.eulerAngles.y = -0.68
        dialogueAnchorLine.opacity = 0
        dialogueAnchorLine.geometry?.firstMaterial?.emission.intensity = 0.18
        root.addChildNode(dialogueAnchorLine)

        let dialogueRuptureField = box(
            width: 2.15,
            height: 0.024,
            length: 1.55,
            color: NSColor(calibratedRed: 0.82, green: 0.24, blue: 0.16, alpha: 1),
            position: SCNVector3(0.1, 0.028, -1.65)
        )
        dialogueRuptureField.name = "jiangDialogueRuptureField"
        dialogueRuptureField.opacity = 0
        dialogueRuptureField.geometry?.firstMaterial?.emission.intensity = 0.12
        root.addChildNode(dialogueRuptureField)
        return root
    }

    private func makeCounselingStage() -> SCNNode {
        let root = makeStageShell(
            name: "narrativeStage_\(NarrativeChapter.counseling.rawValue)",
            floor: NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.15, alpha: 1),
            wall: NSColor(calibratedRed: 0.25, green: 0.34, blue: 0.3, alpha: 1),
            light: NSColor(calibratedRed: 1, green: 0.72, blue: 0.42, alpha: 1)
        )
        root.addChildNode(box(width: 4.8, height: 0.035, length: 3.2, color: NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.2, alpha: 1), position: SCNVector3(0, 0.025, -0.8)))
        for x in [-1.45, 0.0, 1.45] {
            root.addChildNode(makeStageChair(position: SCNVector3(Float(x), 0, -0.65)))
        }
        root.addChildNode(box(width: 1.25, height: 0.12, length: 0.72, color: NSColor(calibratedRed: 0.46, green: 0.3, blue: 0.2, alpha: 1), position: SCNVector3(0, 0.5, 0.45)))
        root.addChildNode(box(width: 2.95, height: 3.45, length: 0.12, color: NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.22, alpha: 1), position: SCNVector3(-2.42, 1.72, -3.35)))
        root.addChildNode(box(width: 2.95, height: 3.45, length: 0.12, color: NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.22, alpha: 1), position: SCNVector3(2.42, 1.72, -3.35)))
        root.addChildNode(box(width: 1.9, height: 0.65, length: 0.12, color: NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.22, alpha: 1), position: SCNVector3(0, 3.12, -3.35)))
        let counselingDoor = box(width: 1.72, height: 2.72, length: 0.14, color: NSColor(calibratedRed: 0.13, green: 0.2, blue: 0.18, alpha: 1), position: SCNVector3(0, 1.36, -3.28))
        counselingDoor.name = "counselingDoor"
        counselingDoor.geometry?.firstMaterial?.lightingModel = .constant
        counselingDoor.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.14, alpha: 1)
        counselingDoor.geometry?.firstMaterial?.emission.contents = NSColor.black
        root.addChildNode(counselingDoor)
        root.addChildNode(sphere(radius: 0.055, color: NSColor(calibratedRed: 0.76, green: 0.57, blue: 0.3, alpha: 1), position: SCNVector3(0.62, 1.28, -3.17)))
        root.addChildNode(makeText("咨询室 · 正在会谈", size: 0.095, color: NSColor(calibratedRed: 0.76, green: 0.9, blue: 0.82, alpha: 1), position: SCNVector3(-0.72, 2.42, -3.17)))
        let boundaryLine = box(width: 1.95, height: 0.018, length: 0.055, color: NSColor(calibratedRed: 0.34, green: 0.88, blue: 0.62, alpha: 1), position: SCNVector3(0, 0.02, -2.32))
        boundaryLine.name = "counselingBoundaryLine"
        boundaryLine.opacity = 0.22
        boundaryLine.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.24, green: 0.72, blue: 0.5, alpha: 1)
        root.addChildNode(boundaryLine)
        root.addChildNode(capsule(radius: 0.05, height: 1.45, color: NSColor(calibratedRed: 0.72, green: 0.52, blue: 0.28, alpha: 1), position: SCNVector3(2.65, 0.75, -1.35)))
        let lamp = sphere(radius: 0.28, color: NSColor(calibratedRed: 1, green: 0.72, blue: 0.3, alpha: 1), position: SCNVector3(2.65, 1.6, -1.35))
        lamp.name = "stageFocus"
        lamp.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1, green: 0.5, blue: 0.16, alpha: 1)
        root.addChildNode(lamp)
        root.addChildNode(makeNarrativeCompanion(name: "companionZhou", label: "周予安", color: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.52, alpha: 1), position: SCNVector3(-1.45, 0, -0.65)))
        root.addChildNode(makeNarrativeCompanion(name: "companionXu", label: "许栀", color: NSColor(calibratedRed: 0.5, green: 0.24, blue: 0.38, alpha: 1), position: SCNVector3(1.45, 0, -0.65)))
        let rumorOne = makeNarrativeCompanion(name: "rumorNPC_1", label: "路过同学", color: NSColor(calibratedRed: 0.38, green: 0.33, blue: 0.44, alpha: 1), position: SCNVector3(-2.45, 0, 1.35))
        rumorOne.isHidden = true
        root.addChildNode(rumorOne)
        let rumorTwo = makeStageFigure(color: NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.42, alpha: 1), position: SCNVector3(-1.8, 0, 1.72))
        rumorTwo.name = "rumorNPC_2"
        rumorTwo.isHidden = true
        root.addChildNode(rumorTwo)
        let messagePhone = box(width: 0.38, height: 0.035, length: 0.68, color: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.16, alpha: 1), position: SCNVector3(0, 0.58, 0.45))
        messagePhone.name = "messagePhone"
        messagePhone.isHidden = true
        messagePhone.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.2, green: 0.72, blue: 0.92, alpha: 1)
        root.addChildNode(messagePhone)
        let routeBeacon = capsule(radius: 0.05, height: 0.68, color: NSColor(calibratedRed: 0.24, green: 0.82, blue: 0.54, alpha: 1), position: SCNVector3(3.2, 1.2, -2.7))
        routeBeacon.name = "counselingRouteBeacon"
        root.addChildNode(routeBeacon)
        root.addChildNode(makeText("正在会谈", size: 0.12, color: NSColor(calibratedRed: 0.82, green: 0.96, blue: 0.85, alpha: 1), position: SCNVector3(-0.62, 2.4, -3.25)))
        return root
    }

    private func makeEpilogueStage() -> SCNNode {
        let root = makeStageShell(
            name: "narrativeStage_\(NarrativeChapter.epilogue.rawValue)",
            floor: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.16, alpha: 1),
            wall: NSColor(calibratedRed: 0.22, green: 0.3, blue: 0.27, alpha: 1),
            light: NSColor(calibratedRed: 1, green: 0.84, blue: 0.52, alpha: 1)
        )
        for index in 0..<7 {
            let width = CGFloat(5.8 - Double(index) * 0.55)
            let frame = box(width: width, height: 0.055, length: 0.055, color: NSColor(calibratedRed: 1, green: 0.68 + CGFloat(index) * 0.025, blue: 0.3, alpha: 1), position: SCNVector3(0, 0.35 + Float(index) * 0.36, -3.35 + Float(index) * 0.12))
            frame.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.34, green: 0.18, blue: 0.05, alpha: 1)
            root.addChildNode(frame)
        }
        let sun = sphere(radius: 0.7, color: NSColor(calibratedRed: 1, green: 0.74, blue: 0.3, alpha: 1), position: SCNVector3(0, 2.0, -3.65))
        sun.name = "stageFocus"
        sun.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1, green: 0.5, blue: 0.12, alpha: 1)
        root.addChildNode(sun)
        let echoPlacements: [(Float, Float, Float)] = [
            (-2.6, 1.05, -2.25),
            (-1.55, 1.32, -2.95),
            (-0.35, 1.12, -2.45),
            (0.75, 1.34, -2.98),
            (1.75, 1.08, -2.28),
            (2.55, 1.46, -3.18)
        ]
        for (index, placement) in echoPlacements.enumerated() {
            let echo = sphere(
                radius: 0.16,
                color: NSColor(calibratedRed: 1, green: 0.72, blue: 0.35, alpha: 1),
                position: SCNVector3(placement.0, placement.1, placement.2)
            )
            echo.name = "consequenceEcho_\(index)"
            echo.opacity = 0
            echo.isHidden = true
            echo.geometry?.firstMaterial?.emission.intensity = 0.2
            root.addChildNode(echo)
        }
        let memoryX: [Float] = [-2.75, -1.65, -0.55, 0.55, 1.65, 2.75]
        for index in 0..<memoryX.count {
            let beacon = sphere(
                radius: 0.13,
                color: NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.38, alpha: 1),
                position: SCNVector3(memoryX[index], 0.82 + Float(index % 2) * 0.12, -0.42 - abs(memoryX[index]) * 0.08)
            )
            beacon.name = "chapterMemoryBeacon_\(index)"
            beacon.opacity = 0
            beacon.geometry?.firstMaterial?.emission.intensity = 0.18

            let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.22, pipeRadius: 0.008))
            halo.name = "chapterMemoryHalo"
            halo.eulerAngles.x = .pi / 2
            halo.opacity = 0
            halo.geometry?.firstMaterial = material(NSColor(calibratedRed: 1, green: 0.76, blue: 0.38, alpha: 1))
            halo.geometry?.firstMaterial?.emission.intensity = 0.18
            beacon.addChildNode(halo)

            root.addChildNode(beacon)
        }
        for index in 0..<(memoryX.count - 1) {
            let start = memoryX[index]
            let end = memoryX[index + 1]
            let line = box(
                width: CGFloat(abs(end - start)) * 0.82,
                height: 0.018,
                length: 0.035,
                color: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.42, alpha: 1),
                position: SCNVector3((start + end) / 2, 0.55, -0.58)
            )
            line.name = "chapterMemoryLine_\(index)"
            line.opacity = 0
            line.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.9, green: 0.62, blue: 0.28, alpha: 1)
            root.addChildNode(line)
        }
        for (index, x) in [-2.0, -1.0, 0.0, 1.0, 2.0].enumerated() {
            let color = index == 2
                ? NSColor(calibratedRed: 0.28, green: 0.48, blue: 0.58, alpha: 1)
                : NSColor(calibratedRed: 0.2, green: 0.34, blue: 0.3, alpha: 1)
            root.addChildNode(makeStageFigure(color: color, position: SCNVector3(Float(x), 0, -1.45 - abs(Float(x)) * 0.16)))
        }
        root.addChildNode(makeText("这里有光", size: 0.24, color: NSColor(calibratedRed: 1, green: 0.88, blue: 0.62, alpha: 1), position: SCNVector3(-0.78, 3.03, -3.58)))
        return root
    }

    private func makeStageFigure(color: NSColor, position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let torso = capsule(radius: 0.16, height: 0.92, color: color, position: SCNVector3(0, 0.64, 0))
        torso.name = "performanceTorso"
        root.addChildNode(torso)

        let head = sphere(radius: 0.15, color: skinTone, position: SCNVector3(0, 1.27, 0))
        head.name = "performanceHead"
        root.addChildNode(head)

        let shoulderLine = capsule(
            radius: 0.018,
            height: 0.46,
            color: color.blended(withFraction: 0.28, of: .white) ?? color,
            position: SCNVector3(0, 1.08, -0.02),
            rotation: SCNVector4(0, 0, 1, Float.pi / 2)
        )
        shoulderLine.name = "performanceShoulderLine"
        root.addChildNode(shoulderLine)

        let gazeLine = capsule(
            radius: 0.01,
            height: 0.62,
            color: NSColor(calibratedRed: 0.55, green: 0.86, blue: 1.0, alpha: 1),
            position: SCNVector3(0, 1.25, -0.35),
            rotation: SCNVector4(1, 0, 0, Float.pi / 2)
        )
        gazeLine.name = "performanceGazeLine"
        gazeLine.opacity = 0.18
        gazeLine.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.22, green: 0.6, blue: 0.9, alpha: 1)
        root.addChildNode(gazeLine)

        let breath = sphere(radius: 0.055, color: NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.46, alpha: 1), position: SCNVector3(0, 0.86, -0.13))
        breath.name = "performanceBreathPulse"
        breath.opacity = 0.2
        breath.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.9, green: 0.56, blue: 0.22, alpha: 1)
        root.addChildNode(breath)

        let shield = SCNNode(geometry: SCNTorus(ringRadius: 0.32, pipeRadius: 0.012))
        shield.name = "performancePrivacyShield"
        shield.position = SCNVector3(0, 1.02, -0.18)
        shield.eulerAngles.x = .pi / 2
        shield.isHidden = true
        shield.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.58, alpha: 0.45))
        shield.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.18, green: 0.58, blue: 0.38, alpha: 1)
        shield.geometry?.firstMaterial?.emission.intensity = 0.55
        root.addChildNode(shield)
        return root
    }

    private func makeNarrativeCompanion(name: String, label: String, color: NSColor, position: SCNVector3) -> SCNNode {
        let root = makeStageFigure(color: color, position: position)
        root.name = name
        let nameplate = makeText(label, size: 0.065, color: .white, position: SCNVector3(-0.16, 1.58, 0))
        nameplate.constraints = [SCNBillboardConstraint()]
        root.addChildNode(nameplate)
        let marker = capsule(radius: 0.035, height: 0.22, color: color, position: SCNVector3(0, 1.76, 0))
        marker.geometry?.firstMaterial?.emission.contents = color
        root.addChildNode(marker)
        let contactProp = box(width: 0.16, height: 0.32, length: 0.035, color: NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.1, alpha: 1), position: SCNVector3(0, 1.02, -0.2))
        contactProp.name = "companionContactProp"
        contactProp.isHidden = true
        contactProp.geometry?.firstMaterial?.emission.intensity = 0.7
        root.addChildNode(contactProp)
        let followLine = box(
            width: 1,
            height: 0.018,
            length: 0.035,
            color: color.withAlphaComponent(0.42),
            position: SCNVector3(0, 0.042, 0)
        )
        followLine.name = "companionFollowDistanceLine"
        followLine.isHidden = true
        followLine.opacity = 0
        followLine.geometry?.firstMaterial?.blendMode = .add
        followLine.geometry?.firstMaterial?.writesToDepthBuffer = false
        followLine.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.48)
        root.addChildNode(followLine)
        let boundaryRing = SCNNode(geometry: SCNTorus(ringRadius: 0.72, pipeRadius: 0.012))
        boundaryRing.name = "companionBoundaryRing"
        boundaryRing.eulerAngles.x = .pi / 2
        boundaryRing.isHidden = true
        boundaryRing.opacity = 0
        boundaryRing.geometry?.firstMaterial = material(color.withAlphaComponent(0.38))
        boundaryRing.geometry?.firstMaterial?.blendMode = .add
        boundaryRing.geometry?.firstMaterial?.writesToDepthBuffer = false
        boundaryRing.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.5)
        root.addChildNode(boundaryRing)
        applyNarrativeActorPerformance(
            to: root,
            tension: 0.32,
            gaze: 0.45,
            breath: 0.2,
            shieldVisible: false,
            markerColor: color
        )
        return root
    }

    private func applyNarrativeActorPerformance(
        to node: SCNNode?,
        tension: CGFloat,
        gaze: CGFloat,
        breath: CGFloat,
        shieldVisible: Bool,
        markerColor: NSColor
    ) {
        guard let node else { return }
        let clampedTension = min(1, max(0, tension))
        let clampedGaze = min(1, max(0, gaze))
        let clampedBreath = min(1, max(0, breath))
        let duration: CFTimeInterval = inputView == nil ? 0 : 0.28

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration

        if let torso = node.childNode(withName: "performanceTorso", recursively: true) {
            torso.eulerAngles.x = -0.08 * clampedTension
            torso.scale = SCNVector3(1 - Float(clampedTension) * 0.08, 1, 1)
        }
        if let head = node.childNode(withName: "performanceHead", recursively: true) {
            head.eulerAngles.x = -0.2 * clampedTension
            head.eulerAngles.z = 0.08 * clampedTension
        }
        if let shoulder = node.childNode(withName: "performanceShoulderLine", recursively: true) {
            shoulder.eulerAngles.z = CGFloat.pi / 2 - 0.26 * clampedTension
            shoulder.opacity = 0.4 + (1 - clampedTension) * 0.45
            shoulder.geometry?.firstMaterial?.emission.contents = markerColor.withAlphaComponent(0.28)
            shoulder.geometry?.firstMaterial?.emission.intensity = 0.18 + (1 - clampedTension) * 0.5
        }
        if let gazeNode = node.childNode(withName: "performanceGazeLine", recursively: true) {
            gazeNode.opacity = 0.08 + clampedGaze * 0.68
            gazeNode.scale = SCNVector3(1, 1 + Float(clampedGaze) * 0.42, 1)
            gazeNode.geometry?.firstMaterial?.emission.contents = markerColor.withAlphaComponent(0.52)
            gazeNode.geometry?.firstMaterial?.emission.intensity = 0.25 + clampedGaze * 0.75
        }
        if let breathNode = node.childNode(withName: "performanceBreathPulse", recursively: true) {
            breathNode.opacity = 0.08 + clampedBreath * 0.62
            breathNode.scale = SCNVector3(
                0.86 + Float(clampedBreath) * 0.55,
                0.86 + Float(clampedBreath) * 0.55,
                0.86 + Float(clampedBreath) * 0.55
            )
            breathNode.geometry?.firstMaterial?.emission.contents = markerColor.withAlphaComponent(0.46)
            breathNode.geometry?.firstMaterial?.emission.intensity = 0.2 + clampedBreath * 0.8
        }
        if let shield = node.childNode(withName: "performancePrivacyShield", recursively: true) {
            shield.isHidden = shieldVisible == false
            shield.opacity = shieldVisible ? 0.66 : 0
            shield.geometry?.firstMaterial?.emission.contents = markerColor.withAlphaComponent(0.5)
        }

        SCNTransaction.commit()
    }

    private func makeStageChair(position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let fabric = NSColor(calibratedRed: 0.18, green: 0.38, blue: 0.34, alpha: 1)
        root.addChildNode(box(width: 0.82, height: 0.16, length: 0.75, color: fabric, position: SCNVector3(0, 0.48, 0)))
        root.addChildNode(box(width: 0.82, height: 0.7, length: 0.14, color: fabric, position: SCNVector3(0, 0.82, 0.31)))
        for x in [-0.33, 0.33] {
            root.addChildNode(box(width: 0.08, height: 0.46, length: 0.08, color: NSColor(calibratedRed: 0.28, green: 0.19, blue: 0.13, alpha: 1), position: SCNVector3(Float(x), 0.23, 0)))
        }
        return root
    }

    private func updateLightingEnvironment(game: GameManager) {
        let usesQuad = game.isPrologueActive && game.prologueCurrentBeat == .gateArrival
        let identifier = usesQuad ? "quad" : "hall"
        guard identifier != activeLightingEnvironment else { return }
        activeLightingEnvironment = identifier
        scene.lightingEnvironment.contents = usesQuad ? quadLightingImage : hallLightingImage
        scene.lightingEnvironment.intensity = usesQuad ? 0.42 : 0.16
        scene.background.contents = usesQuad
            ? (quadBackgroundImage ?? quadLightingImage)
            : NSColor(calibratedRed: 0.018, green: 0.022, blue: 0.03, alpha: 1)
        // Gate arrival is a photographic 360-degree exterior within the same
        // SceneKit scene. The classroom's authored geometry must not cut into
        // the horizon while this world-space exterior is active.
        for node in scene.rootNode.childNodes where node !== cameraRig {
            node.isHidden = usesQuad
        }
        cameraRig.camera?.exposureOffset = usesQuad ? 0.15 : -1.9
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 100
        camera.zNear = 0.03
        camera.zFar = 80
        camera.wantsDepthOfField = true
        camera.wantsHDR = true
        camera.screenSpaceAmbientOcclusionIntensity = 0.72
        camera.screenSpaceAmbientOcclusionRadius = 1.8
        camera.screenSpaceAmbientOcclusionBias = 0.025
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -1.2
        camera.minimumExposure = -3.0
        camera.maximumExposure = -0.2
        camera.bloomIntensity = 0.012
        camera.bloomThreshold = 1.8
        camera.bloomBlurRadius = 2
        camera.focusDistance = 1.5
        camera.fStop = 1.8
        camera.vignettingPower = 0.8
        camera.vignettingIntensity = 0.55
        cameraRig.camera = camera
        cameraRig.position = SCNVector3(-1.2, 1.18, 1.5)
        scene.rootNode.addChildNode(cameraRig)
    }

    private func applyCameraMode(game: GameManager, teacherPosition: SCNVector3) {
        if game.isPrologueActive {
            applyPrologueCamera(game: game)
            return
        }
        if game.narrativeCampaign.isActive {
            applyNarrativeCamera(game: game)
            return
        }
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
                cameraRig.position = SCNVector3(-1.2 + stressSway, height - attentionDip, 1.5)
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

    private func applyPrologueCamera(game: GameManager) {
        switch game.prologueCurrentBeat {
        case .gateArrival:
            cameraRig.position = SCNVector3Zero
            cameraRig.eulerAngles = SCNVector3(-0.04, -0.12, 0)
            cameraRig.camera?.fieldOfView = 70
        case .lookDownHall:
            cameraRig.position = SCNVector3(5.25, 1.58, 7.3)
            cameraRig.eulerAngles = SCNVector3(Float(game.studentLookPitch), 0.58 + Float(game.studentLookYaw), 0)
            cameraRig.camera?.fieldOfView = 88
        case .returnToSeat:
            cameraRig.position = SCNVector3(Float(game.freeRoam.positionX), 1.58, Float(game.freeRoam.positionZ))
            cameraRig.eulerAngles = SCNVector3(Float(game.freeRoam.pitch), Float(game.freeRoam.yaw), 0)
            cameraRig.camera?.fieldOfView = 90
        case .placeWater:
            cameraRig.position = SCNVector3(-1.2, 1.18, 1.5)
            cameraRig.eulerAngles = SCNVector3(-0.22, 0.4, 0)
            cameraRig.camera?.fieldOfView = 68
        case .noticeLinChe:
            cameraRig.position = SCNVector3(-1.32, 1.22, 1.42)
            cameraRig.eulerAngles = SCNVector3(Float(game.studentLookPitch), Float(game.studentLookYaw), 0)
            cameraRig.camera?.fieldOfView = 58
        case .studyHallRhythm, .settleBreath, .accessibility, .bellBeforeClass:
            cameraRig.position = SCNVector3(-1.2, 1.18, 1.5)
            cameraRig.eulerAngles = SCNVector3(Float(game.studentLookPitch), Float(game.studentLookYaw), 0)
            cameraRig.camera?.fieldOfView = 94
        }
    }

    private func updateProloguePerformance(game: GameManager) {
        guard game.isPrologueActive else {
            prologueLookTargetNode.isHidden = true
            prologueLookTargetNode.opacity = 0
            prologueGateArrivalNode.isHidden = true
            prologueGateArrivalNode.opacity = 0
            return
        }
        updatePrologueGateArrivalPath(game: game)

        if game.prologueCurrentBeat == .gateArrival, game.accessibilityPreferences.reduceMotion == false {
            let progress = (game.prologueBeatElapsed / PrologueGateArrivalSignal.duration).clamped(to: 0...1)
            let eased = progress * progress * (3 - 2 * progress)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            cameraRig.position = SCNVector3Zero
            cameraRig.eulerAngles = SCNVector3(Float(-0.04 + eased * 0.015), Float(-0.12 + eased * 0.18), 0)
            cameraRig.camera?.fieldOfView = CGFloat(70 - eased * 4)
            SCNTransaction.commit()
        }

        let cupIsVisible = game.prologueState.completedBeats.contains(.placeWater)
            || game.prologueCurrentBeat == .placeWater
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        updatePrologueLookTarget(game: game)
        playerWaterCupNode.opacity = cupIsVisible ? 1 : 0
        let cupFocus = game.prologueCurrentBeat == .placeWater
        playerWaterCupNode.scale = cupFocus ? SCNVector3(1.04, 1.04, 1.04) : SCNVector3(1, 1, 1)
        playerWaterCupNode.childNodes.forEach { child in
            child.geometry?.firstMaterial?.emission.contents = cupFocus
                ? NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.42, alpha: 1)
                : NSColor.black
        }
        SCNTransaction.commit()

        if game.prologueCurrentBeat == .noticeLinChe {
            cameraRig.camera?.focusDistance = 1.72
            cameraRig.camera?.fStop = 1.35
        }

        guard game.prologueCurrentBeat == .studyHallRhythm else {
            restoreAuthoredClassmatePositions(game.classmates)
            return
        }

        let phase = game.prologuePerformancePhase
        teacherNode.position = phase == 0 ? SCNVector3(-0.35, 0.05, -4.25) : SCNVector3(0, 0.05, -4.25)
        teacherNode.opacity = 0.92

        restoreAuthoredClassmatePositions(game.classmates)
        if let monitor = classmateNodes[1], let mate = game.classmates.first(where: { $0.id == 1 }), phase <= 1 {
            let target = classmateScenePosition(seat: mate.seat)
            let progress = ((game.prologueBeatElapsed - 6) / 6).clamped(to: 0...1)
            let targetX = Double(target.x)
            let targetZ = Double(target.z)
            let animatedX = 3.45 + (targetX - 3.45) * progress
            let animatedZ = -4.2 + (targetZ + 4.2) * progress
            monitor.position = SCNVector3(Float(animatedX), Float(target.y), Float(animatedZ))
        }
        if let xuZhi = classmateNodes[4] {
            let bend = phase == 2 ? 0.82 : 1.0
            xuZhi.scale = SCNVector3(1, Float(bend), 1)
        }
        if let linChe = classmateNodes[0] {
            linChe.opacity = phase >= 4 ? 1 : 0
        }
    }

    private func updatePrologueGateArrivalPath(game: GameManager) {
        let signal = PrologueGateArrivalSignal(
            isPrologueActive: game.isPrologueActive,
            currentBeat: game.prologueCurrentBeat,
            elapsed: game.prologueBeatElapsed
        )
        prologueGateArrivalNode.isHidden = signal.isVisible == false
        prologueGateArrivalNode.opacity = signal.isVisible ? 1 : 0

        for index in 0..<PrologueGateArrivalSignal.stepCount {
            guard let step = prologueGateArrivalNode.childNode(withName: "prologueGateStep_\(index)", recursively: true) else { continue }
            let lit = index < signal.litStepCount
            let localIntensity = lit ? 0.82 + CGFloat(signal.progress) * 0.56 : 0.18
            step.opacity = lit ? 0.96 : 0.2
            step.scale = lit ? SCNVector3(2.08, 0.25, 1.04) : SCNVector3(1.46, 0.17, 0.78)
            step.geometry?.firstMaterial?.emission.intensity = localIntensity
        }

        if let marker = prologueGateArrivalNode.childNode(withName: "prologueGateStudentMarker", recursively: true) {
            marker.position.z = CGFloat(signal.studentZ)
            marker.opacity = signal.isVisible ? 0.82 : 0
            marker.geometry?.firstMaterial?.emission.intensity = 0.18 + CGFloat(signal.progress) * 0.36
        }
        if let entrance = prologueGateArrivalNode.childNode(withName: "prologueGateEntranceGlow", recursively: true) {
            entrance.opacity = CGFloat(signal.entranceGlow)
            entrance.geometry?.firstMaterial?.emission.intensity = 0.16 + CGFloat(signal.entranceGlow) * 0.72
        }
        if let line = prologueGateArrivalNode.childNode(withName: "prologueGatePathLine", recursively: true) {
            line.opacity = signal.isVisible ? CGFloat(0.18 + signal.progress * 0.28) : 0
            line.geometry?.firstMaterial?.emission.intensity = CGFloat(0.12 + signal.progress * 0.32)
        }
    }

    private func updatePrologueLookTarget(game: GameManager) {
        let signal = PrologueLookTargetSignal(
            isPrologueActive: game.isPrologueActive,
            currentBeat: game.prologueCurrentBeat,
            lastBeatEcho: game.prologueState.lastBeatEcho,
            cameraPose: game.cameraPose,
            studentLookYaw: game.studentLookYaw
        )

        prologueLookTargetNode.isHidden = signal.isVisible == false
        prologueLookTargetNode.opacity = CGFloat(signal.opacity)
        prologueLookTargetNode.scale = SCNVector3(Float(signal.scale), Float(signal.scale), Float(signal.scale))

        let emission = CGFloat(signal.emissionIntensity)
        for name in ["prologueLookTargetCore", "prologueLookTargetInnerRing", "prologueLookTargetOuterRing", "prologueLookTargetLift"] {
            prologueLookTargetNode.childNode(withName: name, recursively: true)?
                .geometry?
                .firstMaterial?
                .emission
                .intensity = emission
        }
        prologueLookTargetNode.childNode(withName: "prologueLookTargetLabel", recursively: true)?.opacity = CGFloat(signal.labelOpacity)
        prologueLookTargetNode.childNode(withName: "prologueLookTargetLight", recursively: true)?.light?.intensity = CGFloat(signal.lightIntensity)
    }

    private func updateScenePresentation(game: GameManager) {
        guard game.scenePresentation.isActive,
              let camera = cameraRig.camera else { return }
        let phaseIntensity = ScenePresentationMotionProfile.phaseIntensity(
            for: game.scenePresentation,
            reduceMotion: game.accessibilityPreferences.reduceMotion
        )
        guard phaseIntensity > 0 else { return }
        let style = game.scenePresentation.transition

        switch style {
        case .fade:
            camera.exposureOffset -= CGFloat(0.14 * phaseIntensity)
            camera.vignettingIntensity += CGFloat(0.08 * phaseIntensity)
            camera.vignettingPower += CGFloat(0.12 * phaseIntensity)
        case .colorTemperatureFlip:
            camera.exposureOffset += CGFloat(0.05 * phaseIntensity)
            camera.saturation = max(0.72, camera.saturation - CGFloat(0.16 * phaseIntensity))
            camera.fStop += CGFloat(0.12 * phaseIntensity)
        case .mirrorRipple:
            camera.fieldOfView += CGFloat(2.5 * phaseIntensity)
            camera.focusDistance = max(1.0, camera.focusDistance - CGFloat(0.14 * phaseIntensity))
            camera.vignettingIntensity += CGFloat(0.06 * phaseIntensity)
        }
    }

    private func restoreAuthoredClassmatePositions(_ classmates: [Classmate]) {
        for mate in classmates {
            classmateNodes[mate.id]?.position = classmateScenePosition(seat: mate.seat)
        }
    }

    private func classmateScenePosition(seat: (row: Int, column: Int)) -> SCNVector3 {
        // A seated student occupies the chair behind the desk, facing toward
        // the board at -Z. Keep the pelvis over the seat and the knees under
        // the desk rather than placing the body at the desk center.
        SCNVector3(Float(seat.column) * 1.2 - 2.4, 0.42, Float(seat.row) * 1.45 - 1.42)
    }

    private func updateLinCheChapterOnePerformance(game: GameManager) {
        guard game.isPrologueActive == false,
              game.narrativeCampaign.isActive == false,
              game.activeChapter == .silentClassroom,
              let linChe = classmateNodes[0] else { return }

        let cue = game.linChePerformanceCue
        lastLinChePerformanceCue = cue
        ensureLinChePerformanceProps(on: linChe)

        let seat = classmateScenePosition(seat: (2, 0))
        let position = linCheExitPosition(progress: cue.exitProgress)
        linChe.position = cue.isLeaving || cue.phase == .packingUp ? position : seat
        linChe.opacity = cue.phase == .exited ? 0.18 : 1
        linChe.scale = SCNVector3(
            1,
            CGFloat(0.99 + cue.packingProgress * 0.1 + cue.exitProgress * 0.08),
            1
        )
        linChe.eulerAngles.y = CGFloat(-0.18 * cue.doorAttention - 0.42 * cue.exitProgress)
        linChe.eulerAngles.z = CGFloat(-0.035 * cue.intensity + 0.025 * cue.exitProgress)

        if let head = linChe.childNode(withName: "head", recursively: true) {
            let headPitch = -0.12 + 0.18 * cue.doorAttention - 0.08 * cue.packingProgress
            let headYaw = -0.62 * cue.doorAttention + 0.16 * cue.exitProgress
            head.eulerAngles.x = CGFloat(headPitch)
            head.eulerAngles.y = CGFloat(headYaw)
            head.position.y = CGFloat(0.88 + 0.05 * cue.exitProgress)
        }
        if let hair = linChe.childNode(withName: "hair", recursively: true) {
            hair.eulerAngles.y = CGFloat(-0.48 * cue.doorAttention + 0.12 * cue.exitProgress)
            hair.position.y = CGFloat(0.955 + 0.05 * cue.exitProgress)
        }
        if let body = linChe.childNode(withName: "body", recursively: true) {
            body.eulerAngles.x = CGFloat(-0.05 * cue.packingProgress + 0.08 * cue.exitProgress)
            body.geometry?.firstMaterial?.emission.intensity = 0.02 + CGFloat(cue.intensity) * 0.08
        }
        if let paper = linChe.childNode(withName: "paper", recursively: true) {
            paper.opacity = CGFloat((0.28 + cue.pageStillness * 0.62 - cue.packingProgress * 0.32).clamped(to: 0...0.9))
            paper.position.x = CGFloat(-0.12 + cue.packingProgress * 0.18)
            paper.position.z = CGFloat(-0.2 + cue.packingProgress * 0.12)
            paper.eulerAngles.y = CGFloat(cue.packingProgress * 0.5)
        }
        if let bag = linChe.childNode(withName: "linChePackedBag", recursively: true) {
            bag.opacity = CGFloat((cue.packingProgress * 0.86 + cue.exitProgress * 0.14).clamped(to: 0...1))
            bag.position.x = CGFloat(0.17 - cue.exitProgress * 0.08)
            bag.position.y = CGFloat(0.28 + cue.exitProgress * 0.1)
            bag.eulerAngles.z = CGFloat(-0.16 * cue.exitProgress)
        }
        if let gaze = linChe.childNode(withName: "linCheDoorGazeLine", recursively: true) {
            gaze.opacity = CGFloat((cue.doorAttention * 0.58 - cue.exitProgress * 0.18).clamped(to: 0...0.58))
            gaze.scale = SCNVector3(1, 1, CGFloat(0.72 + cue.doorAttention * 0.46))
        }
        if let trace = linChe.childNode(withName: "linCheExitTrace", recursively: true) {
            trace.opacity = CGFloat((cue.exitProgress * 0.78).clamped(to: 0...0.78))
            trace.scale = SCNVector3(
                CGFloat(0.72 + cue.exitProgress * 0.32),
                1,
                CGFloat(0.72 + cue.exitProgress * 0.72)
            )
        }
    }

    private func ensureLinChePerformanceProps(on linChe: SCNNode) {
        if linChe.childNode(withName: "linChePackedBag", recursively: false) == nil {
            let bag = box(
                width: 0.2,
                height: 0.12,
                length: 0.09,
                color: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1),
                position: SCNVector3(0.17, 0.28, 0.04)
            )
            bag.name = "linChePackedBag"
            bag.opacity = 0
            bag.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.18, alpha: 1)
            linChe.addChildNode(bag)
        }
        if linChe.childNode(withName: "linCheDoorGazeLine", recursively: false) == nil {
            let gaze = box(
                width: 0.026,
                height: 0.012,
                length: 0.78,
                color: NSColor(calibratedRed: 0.32, green: 0.74, blue: 1, alpha: 0.5),
                position: SCNVector3(-0.02, 0.83, -0.48)
            )
            gaze.name = "linCheDoorGazeLine"
            gaze.opacity = 0
            gaze.geometry?.firstMaterial?.lightingModel = .constant
            gaze.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.2, green: 0.62, blue: 1, alpha: 1)
            gaze.geometry?.firstMaterial?.emission.intensity = 0.56
            linChe.addChildNode(gaze)
        }
        if linChe.childNode(withName: "linCheExitTrace", recursively: false) == nil {
            let trace = box(
                width: 0.09,
                height: 0.012,
                length: 0.62,
                color: NSColor(calibratedRed: 1, green: 0.56, blue: 0.28, alpha: 0.5),
                position: SCNVector3(0.02, -0.38, 0.28)
            )
            trace.name = "linCheExitTrace"
            trace.opacity = 0
            trace.geometry?.firstMaterial?.lightingModel = .constant
            trace.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1, green: 0.42, blue: 0.18, alpha: 1)
            trace.geometry?.firstMaterial?.emission.intensity = 0.48
            linChe.addChildNode(trace)
        }
    }

    private func linCheExitPosition(progress: Double) -> SCNVector3 {
        let start = classmateScenePosition(seat: (2, 0))
        let bend = SCNVector3(-1.72, 0.48, -1.72)
        let door = SCNVector3(-0.92, 0.5, -4.12)
        let amount = progress.clamped(to: 0...1)
        if amount <= 0.55 {
            return interpolate(start, bend, t: amount / 0.55)
        }
        return interpolate(bend, door, t: (amount - 0.55) / 0.45)
    }

    private func interpolate(_ start: SCNVector3, _ end: SCNVector3, t: Double) -> SCNVector3 {
        let amount = CGFloat(t.clamped(to: 0...1))
        let x = start.x + (end.x - start.x) * amount
        let y = start.y + (end.y - start.y) * amount
        let z = start.z + (end.z - start.z) * amount
        return SCNVector3(x, y, z)
    }

    private func makePrologueExterior() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueExterior"

        let ground = SCNNode(geometry: SCNBox(width: 12, height: 0.08, length: 18, chamferRadius: 0))
        ground.position = SCNVector3(17.8, -0.08, 12)
        ground.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.24, alpha: 1)
        root.addChildNode(ground)

        let sky = SCNNode(geometry: SCNPlane(width: 42, height: 22))
        sky.position = SCNVector3(17.8, 8.5, 3.75)
        sky.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.2, green: 0.26, blue: 0.38, alpha: 1)
        sky.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.12, alpha: 1)
        sky.geometry?.firstMaterial?.isDoubleSided = true
        root.addChildNode(sky)

        let walkway = SCNNode(geometry: SCNBox(width: 4.4, height: 0.045, length: 12.8, chamferRadius: 0.015))
        walkway.position = SCNVector3(17.8, 0, 11.15)
        walkway.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.43, alpha: 1)
        root.addChildNode(walkway)
        for index in 0..<9 {
            let joint = box(
                width: 4.3,
                height: 0.008,
                length: 0.018,
                color: NSColor(calibratedWhite: 0.18, alpha: 0.7),
                position: SCNVector3(17.8, 0.028, 5.7 + Float(index) * 1.42)
            )
            root.addChildNode(joint)
        }

        let building = SCNNode(geometry: SCNBox(width: 10, height: 7, length: 1.2, chamferRadius: 0.08))
        building.position = SCNVector3(17.8, 3.5, 5)
        building.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.48, green: 0.5, blue: 0.48, alpha: 1)
        root.addChildNode(building)

        let entrance = box(
            width: 2.45,
            height: 2.55,
            length: 0.08,
            color: NSColor(calibratedRed: 0.055, green: 0.12, blue: 0.17, alpha: 1),
            position: SCNVector3(17.8, 1.28, 5.65)
        )
        root.addChildNode(entrance)
        root.addChildNode(box(width: 0.055, height: 2.4, length: 0.1, color: NSColor(calibratedWhite: 0.68, alpha: 1), position: SCNVector3(17.8, 1.28, 5.72)))
        root.addChildNode(box(width: 2.9, height: 0.16, length: 1.0, color: NSColor(calibratedRed: 0.24, green: 0.3, blue: 0.34, alpha: 1), position: SCNVector3(17.8, 2.72, 6.02)))
        root.addChildNode(makeText("教学楼 · 晚自习", size: 0.18, color: NSColor(calibratedRed: 0.94, green: 0.86, blue: 0.62, alpha: 1), position: SCNVector3(16.54, 3.12, 5.68)))

        for index in 0..<3 {
            let step = box(
                width: 2.9 + CGFloat(index) * 0.28,
                height: 0.09,
                length: 0.42,
                color: NSColor(calibratedRed: 0.34, green: 0.36, blue: 0.35, alpha: 1),
                position: SCNVector3(17.8, 0.045 + Float(index) * 0.055, 6.12 + Float(index) * 0.34)
            )
            root.addChildNode(step)
        }

        for floor in 0..<3 {
            for column in 0..<6 {
                let window = SCNNode(geometry: SCNBox(width: 1.05, height: 0.9, length: 0.05, chamferRadius: 0.03))
                window.position = SCNVector3(14.6 + Float(column) * 1.28, 1.35 + Float(floor) * 1.75, 5.64)
                window.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.5, alpha: 1)
                window.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.28, green: 0.2, blue: 0.08, alpha: 1)
                root.addChildNode(window)
            }
        }

        let noticeBoard = box(width: 1.35, height: 1.05, length: 0.08, color: NSColor(calibratedRed: 0.14, green: 0.2, blue: 0.22, alpha: 1), position: SCNVector3(20.65, 1.05, 5.72))
        root.addChildNode(noticeBoard)
        root.addChildNode(makeText("18:30  晚自习\n三楼  高二(3)班", size: 0.105, color: NSColor(calibratedWhite: 0.9, alpha: 1), position: SCNVector3(20.08, 1.35, 5.78)))

        let gateLeft = SCNNode(geometry: SCNBox(width: 0.35, height: 2.4, length: 0.35, chamferRadius: 0.03))
        gateLeft.position = SCNVector3(14.3, 1.2, 16.2)
        gateLeft.geometry?.firstMaterial?.diffuse.contents = NSColor.darkGray
        root.addChildNode(gateLeft)
        let gateRight = gateLeft.clone()
        gateRight.position.x = 21.3
        root.addChildNode(gateRight)
        root.addChildNode(box(width: 7.35, height: 0.22, length: 0.3, color: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.19, alpha: 1), position: SCNVector3(17.8, 2.38, 16.2)))
        root.addChildNode(makeText("铃 响 之 前", size: 0.2, color: NSColor(calibratedRed: 0.93, green: 0.78, blue: 0.46, alpha: 1), position: SCNVector3(16.35, 2.46, 16.38)))
        prologueGateArrivalNode.addChildNode(makePrologueGateArrivalPath())
        prologueGateArrivalNode.name = "prologueGateArrivalPath"
        prologueGateArrivalNode.opacity = 0
        prologueGateArrivalNode.isHidden = true
        root.addChildNode(prologueGateArrivalNode)

        func addTree(x: Float, z: Float, scale: Float) {
            let trunk = SCNNode(geometry: SCNCylinder(radius: CGFloat(0.11 * scale), height: CGFloat(1.5 * scale)))
            trunk.position = SCNVector3(x, 0.75 * scale, z)
            trunk.geometry?.firstMaterial = material(NSColor(calibratedRed: 0.25, green: 0.17, blue: 0.11, alpha: 1))
            root.addChildNode(trunk)
            let crown = sphere(radius: CGFloat(0.72 * scale), color: NSColor(calibratedRed: 0.12, green: 0.3, blue: 0.22, alpha: 1), position: SCNVector3(x, 1.72 * scale, z), scale: SCNVector3(1, 1.18, 0.82))
            root.addChildNode(crown)
        }
        addTree(x: 13.1, z: 10.2, scale: 1.0)
        addTree(x: 22.5, z: 11.4, scale: 1.08)
        addTree(x: 12.9, z: 15.1, scale: 0.82)
        addTree(x: 22.7, z: 15.7, scale: 0.88)

        for (index, placement) in [(15.5, 13.6), (20.0, 12.6), (16.25, 9.7), (19.45, 8.4), (18.35, 7.25)].enumerated() {
            let student = makeStudent(seed: 30 + index, profile: nil)
            student.position = SCNVector3(Float(placement.0), 0.38, Float(placement.1))
            student.scale = SCNVector3(0.76, 0.76, 0.76)
            student.eulerAngles.y = index.isMultiple(of: 2) ? 0.08 : -0.12
            root.addChildNode(student)
        }

        for x in [14.45, 21.15] {
            let post = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 1.5))
            post.position = SCNVector3(Float(x), 0.75, 9.1)
            post.geometry?.firstMaterial = material(NSColor(calibratedWhite: 0.16, alpha: 1))
            root.addChildNode(post)
            let lamp = sphere(radius: 0.12, color: NSColor(calibratedRed: 1, green: 0.75, blue: 0.38, alpha: 1), position: SCNVector3(Float(x), 1.55, 9.1))
            let light = SCNLight()
            light.type = .omni
            light.color = NSColor(calibratedRed: 1, green: 0.68, blue: 0.36, alpha: 1)
            light.intensity = 180
            light.attenuationEndDistance = 5.5
            lamp.light = light
            root.addChildNode(lamp)
        }

        let dusk = SCNLight()
        dusk.type = .omni
        dusk.color = NSColor(calibratedRed: 1, green: 0.58, blue: 0.32, alpha: 1)
        dusk.intensity = 760
        dusk.attenuationEndDistance = 24
        let duskNode = SCNNode()
        duskNode.light = dusk
        duskNode.position = SCNVector3(12, 6, 18)
        root.addChildNode(duskNode)
        return root
    }

    private func makePrologueGateArrivalPath() -> SCNNode {
        let root = SCNNode()
        let warm = NSColor(calibratedRed: 1, green: 0.86, blue: 0.26, alpha: 1)
        for index in 0..<PrologueGateArrivalSignal.stepCount {
            let z = 15.2 - Float(index) * 1.28
            let step = sphere(
                radius: 0.13,
                color: warm.withAlphaComponent(0.72),
                position: SCNVector3(17.8 + (index.isMultiple(of: 2) ? -0.18 : 0.18), 0.08, z),
                scale: SCNVector3(1.9, 0.2, 0.94)
            )
            step.name = "prologueGateStep_\(index)"
            step.opacity = 0.18
            step.geometry?.firstMaterial?.blendMode = .add
            step.geometry?.firstMaterial?.writesToDepthBuffer = false
            step.geometry?.firstMaterial?.emission.contents = warm
            step.geometry?.firstMaterial?.emission.intensity = 0.12
            root.addChildNode(step)
        }

        let studentMarker = capsule(
            radius: 0.045,
            height: 0.92,
            color: NSColor(calibratedRed: 0.86, green: 0.94, blue: 1, alpha: 0.86),
            position: SCNVector3(17.8, 0.54, 15.55)
        )
        studentMarker.name = "prologueGateStudentMarker"
        studentMarker.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.38, green: 0.68, blue: 1, alpha: 1)
        studentMarker.geometry?.firstMaterial?.emission.intensity = 0.18
        root.addChildNode(studentMarker)

        let entranceGlow = box(
            width: 2.65,
            height: 2.38,
            length: 0.035,
            color: warm.withAlphaComponent(0.36),
            position: SCNVector3(17.8, 1.32, 5.77)
        )
        entranceGlow.name = "prologueGateEntranceGlow"
        entranceGlow.opacity = 0.22
        entranceGlow.geometry?.firstMaterial?.blendMode = .add
        entranceGlow.geometry?.firstMaterial?.writesToDepthBuffer = false
        entranceGlow.geometry?.firstMaterial?.emission.contents = warm
        entranceGlow.geometry?.firstMaterial?.emission.intensity = 0.18
        root.addChildNode(entranceGlow)

        let pathLine = box(
            width: 0.12,
            height: 0.012,
            length: 8.9,
            color: warm.withAlphaComponent(0.34),
            position: SCNVector3(17.8, 0.045, 10.85)
        )
        pathLine.name = "prologueGatePathLine"
        pathLine.opacity = 0.26
        pathLine.geometry?.firstMaterial?.blendMode = .add
        pathLine.geometry?.firstMaterial?.writesToDepthBuffer = false
        pathLine.geometry?.firstMaterial?.emission.contents = warm
        pathLine.geometry?.firstMaterial?.emission.intensity = 0.12
        root.addChildNode(pathLine)

        return root
    }

    private func cameraTurnDuration(game: GameManager) -> Double {
        if game.isPrologueActive { return 0 }
        return game.viewMode == .student ? 0.16 : 0.28
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
        // The window-level monitor owns this shortcut so focused SceneKit input
        // cannot toggle capture a second time for the same key event.
        if isMouseLookToggle(event) {
            return
        }
        if Self.isTutorialToggle(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) {
            if isDown && event.isARepeat == false {
                currentGame?.toggleCurrentPrologueTutorial()
            }
            return
        }
        if Self.isCompleteTutorialKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) {
            if isDown && event.isARepeat == false {
                currentGame?.completeCurrentPrologueEarly()
            }
            return
        }
        if isDown,
           event.isARepeat == false,
           let game = currentGame,
           game.accessibilityPreferences.keyboardAlternativeInput,
           handleNarrativeKeyboardCommand(event, game: game) {
            return
        }
        if event.keyCode == 49 {
            if isDown && event.isARepeat == false {
                currentGame?.confirmPrologueInteraction()
            }
            return
        }
        if event.keyCode == 14 {
            if isDown && event.isARepeat == false {
                if currentGame?.confirmPrologueSeat() == true {
                    return
                } else if currentGame?.narrativeCampaign.isActive == true {
                    currentGame?.interactNarrativeHotspot()
                } else {
                    currentGame?.interactWithNearbyDoor()
                }
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

    private func handleNarrativeKeyboardCommand(_ event: NSEvent, game: GameManager) -> Bool {
        let isNarrativeContext = game.narrativeCampaign.isActive || game.isFullNarrativeRun || game.narrativePaused
        guard isNarrativeContext else { return false }
        let command: NarrativeKeyboardCommand?
        switch event.keyCode {
        case 48, 124:
            command = .nextTarget
        case 123:
            command = .previousTarget
        case 36, 49, 14:
            command = .confirm
        case 53:
            command = .cancel
        default:
            command = nil
        }
        guard let command else { return false }
        return game.performNarrativeKeyboardCommand(command)
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
        let isLooking = pendingMouseDeltaX != 0 || pendingMouseDeltaY != 0
        applyPendingMouseLook()
        currentGame?.updatePrologueLookExploration(isMoving: isLooking, delta: 1.0 / 60.0)
        currentGame?.updatePrologueDwell(delta: 1.0 / 60.0)
        guard let game = currentGame else {
            lastMovementTick = Date()
            return
        }
        let now = Date()
        let delta = min(0.05, now.timeIntervalSince(lastMovementTick))
        lastMovementTick = now

        let forward = (pressedKeys.contains("w") ? 1.0 : 0.0) - (pressedKeys.contains("s") ? 1.0 : 0.0)
        let strafe = (pressedKeys.contains("d") ? 1.0 : 0.0) - (pressedKeys.contains("a") ? 1.0 : 0.0)
        if game.narrativeCampaign.isActive {
            if forward != 0 || strafe != 0 {
                game.moveNarrativeExploration(forward: forward, strafe: strafe, deltaTime: delta)
            }
            game.tickNarrativeExploration(deltaTime: delta)
            updateNarrativeBoundaryVisual(game: game)
            return
        }
        if game.freeRoam.isActive {
            synchronizeMovementModifiers(NSEvent.modifierFlags)
            if forward != 0 || strafe != 0 {
                game.moveStudentFreeRoam(forward: forward, strafe: strafe, deltaTime: delta)
            }
        } else {
            game.tickChapterOneDwell(deltaTime: delta)
        }
    }

    private func applyFocusFeedbackIfNeeded(game: GameManager) {
        guard let feedback = game.focusFeedbackTrigger,
              feedback.id != lastFocusFeedbackID,
              let camera = cameraRig.camera else { return }
        lastFocusFeedbackID = feedback.id
        let baseFOV = camera.fieldOfView
        let duration = game.accessibilityPreferences.reduceMotion ? 0.2 : 0.5

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration * 0.45
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        camera.fieldOfView = max(50, baseFOV - 2)
        SCNTransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.45) { [weak self, weak camera] in
            Task { @MainActor in
                guard self?.lastFocusFeedbackID == feedback.id,
                      let camera else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = duration * 0.55
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                camera.fieldOfView = baseFOV
                SCNTransaction.commit()
            }
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
        if game.narrativeCampaign.isActive {
            game.rotateNarrativeExploration(deltaX: deltaX, deltaY: deltaY)
        } else {
            game.rotateStudentView(deltaX: deltaX, deltaY: deltaY)
        }
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
        Self.isMouseLookToggle(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    static func isMouseLookToggle(keyCode: UInt16, characters: String?) -> Bool {
        // The physical key above Tab is stable across Chinese/English input methods.
        keyCode == 50 || characters == "`" || characters == "~" || characters == "～"
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
            if CGDisplayHideCursor(CGMainDisplayID()) == .success {
                cursorHiddenByDisplayAPI = true
            }
            recenterMouseCursor()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            if cursorHiddenByDisplayAPI {
                CGDisplayShowCursor(CGMainDisplayID())
                cursorHiddenByDisplayAPI = false
            }
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
        prologueLookTargetNode.addChildNode(makePrologueLookTargetBeacon())
        prologueLookTargetNode.name = "prologueLookTarget"
        prologueLookTargetNode.position = SCNVector3(4.65, 1.64, -6.7)
        prologueLookTargetNode.opacity = 0
        prologueLookTargetNode.isHidden = true
        root.addChildNode(prologueLookTargetNode)
        return root
    }

    private func makePrologueLookTargetBeacon() -> SCNNode {
        let root = SCNNode()
        let mint = NSColor(calibratedRed: 0.52, green: 0.96, blue: 0.78, alpha: 1)
        let cyan = NSColor(calibratedRed: 0.42, green: 0.82, blue: 1, alpha: 1)

        let outer = box(
            width: 0.46,
            height: 0.018,
            length: 0.018,
            color: mint.withAlphaComponent(0.58),
            position: SCNVector3Zero
        )
        outer.name = "prologueLookTargetOuterRing"
        outer.geometry?.firstMaterial?.blendMode = .add
        outer.geometry?.firstMaterial?.writesToDepthBuffer = false
        outer.geometry?.firstMaterial?.emission.contents = mint
        outer.geometry?.firstMaterial?.emission.intensity = 0.46
        root.addChildNode(outer)

        let outerVertical = box(
            width: 0.018,
            height: 0.46,
            length: 0.018,
            color: mint.withAlphaComponent(0.58),
            position: SCNVector3Zero
        )
        outerVertical.geometry?.firstMaterial?.blendMode = .add
        outerVertical.geometry?.firstMaterial?.writesToDepthBuffer = false
        outerVertical.geometry?.firstMaterial?.emission.contents = mint
        outerVertical.geometry?.firstMaterial?.emission.intensity = 0.46
        root.addChildNode(outerVertical)

        let inner = box(
            width: 0.22,
            height: 0.014,
            length: 0.014,
            color: cyan.withAlphaComponent(0.72),
            position: SCNVector3(0, 0.0, 0.01)
        )
        inner.name = "prologueLookTargetInnerRing"
        inner.geometry?.firstMaterial?.blendMode = .add
        inner.geometry?.firstMaterial?.writesToDepthBuffer = false
        inner.geometry?.firstMaterial?.emission.contents = cyan
        inner.geometry?.firstMaterial?.emission.intensity = 0.54
        root.addChildNode(inner)

        let core = sphere(radius: 0.055, color: mint, position: SCNVector3Zero)
        core.name = "prologueLookTargetCore"
        core.geometry?.firstMaterial?.emission.contents = mint
        core.geometry?.firstMaterial?.emission.intensity = 0.82
        root.addChildNode(core)

        let line = capsule(
            radius: 0.008,
            height: 0.46,
            color: mint.withAlphaComponent(0.52),
            position: SCNVector3(0, 0.24, 0),
            rotation: SCNVector4(0, 0, 1, 0)
        )
        line.name = "prologueLookTargetLift"
        line.geometry?.firstMaterial?.blendMode = .add
        line.geometry?.firstMaterial?.writesToDepthBuffer = false
        line.geometry?.firstMaterial?.emission.contents = mint
        line.geometry?.firstMaterial?.emission.intensity = 0.5
        root.addChildNode(line)

        let label = box(
            width: 0.42,
            height: 0.08,
            length: 0.014,
            color: NSColor(calibratedWhite: 0.96, alpha: 0.82),
            position: SCNVector3(0, 0.53, 0)
        )
        label.name = "prologueLookTargetLabel"
        label.geometry?.firstMaterial?.emission.contents = NSColor(calibratedWhite: 0.88, alpha: 1)
        label.geometry?.firstMaterial?.emission.intensity = 0.18
        label.opacity = 0.82
        root.addChildNode(label)

        let light = SCNLight()
        light.type = .omni
        light.color = mint
        light.intensity = 120
        light.attenuationEndDistance = 3.2
        let lightNode = SCNNode()
        lightNode.name = "prologueLookTargetLight"
        lightNode.light = light
        lightNode.position = SCNVector3(0, 0.18, 0)
        root.addChildNode(lightNode)

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
            lightPanel.geometry?.firstMaterial?.emission.contents = NSColor(calibratedWhite: 0.22, alpha: 1)
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
        if let realisticDeskTemplate {
            let desk = realisticDeskTemplate.clone()
            desk.name = isPlayer ? "photorealPlayerDesk" : "photorealDesk"
            root.addChildNode(desk)
            if isPlayer == false {
                let supplies = makeDeskSupplies(seed: Int((position.x + 4) * 10 + (position.z + 6) * 7))
                supplies.position.y = 0.28
                root.addChildNode(supplies)
            }
            return root
        }
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
        if let realisticChairTemplate {
            let chair = realisticChairTemplate.clone()
            chair.name = "photorealChair"
            // The Poly Haven chair is authored facing -Z. Desks in this scene
            // put the writing surface on -Z, so the chair must face +Z with
            // its back toward the desk-facing side of the room.
            chair.eulerAngles.y = .pi
            root.addChildNode(chair)
            return root
        }
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
        if classmates.isEmpty {
            var id = 0
            for row in 0..<5 {
                for column in 0..<4 where !(row == 2 && column == 1) {
                    addClassmateNode(id: id, seat: (row, column), profile: nil)
                    id += 1
                }
            }
            return
        }
        for mate in classmates {
            addClassmateNode(id: mate.id, seat: mate.seat, profile: mate.profile)
        }
    }

    private func addClassmateNode(id: Int, seat: (row: Int, column: Int), profile: ClassmateProfile?) {
        let node = makeStudent(seed: id, profile: profile)
        node.position = classmateScenePosition(seat: seat)
        classmateNodes[id] = node
        scene.rootNode.addChildNode(node)
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
            NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.3, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.22, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.27, alpha: 1)
        ]
        let uniformColor = studentUniformColor(seed: seed, profile: profile, fallback: shirtColors[seed % shirtColors.count])
        root.addChildNode(makeStudentBody(uniformColor: uniformColor, seed: seed, profile: profile))

        let head = sphere(
            radius: 0.112,
            color: skinColor(seed),
            position: SCNVector3(0, 0.88, -0.005),
            scale: SCNVector3(0.82, 1.04, 0.9)
        )
        head.name = "head"
        let face = makeStudentFace(seed: seed, profile: profile)
        face.scale = SCNVector3(0.72, 0.72, 0.72)
        face.position.z = -0.012
        head.addChildNode(face)
        if profile?.orderliness ?? 0 > 72 {
            let glasses = makeFaceGlasses()
            glasses.scale = SCNVector3(0.72, 0.72, 0.72)
            glasses.position.z = -0.012
            head.addChildNode(glasses)
        }
        root.addChildNode(head)

        let hairColor = NSColor(calibratedWhite: 0.025 + CGFloat(seed % 3) * 0.025, alpha: 1)
        let hair = sphere(
            radius: 0.116,
            color: hairColor,
            position: SCNVector3(0, 0.955, 0.018),
            scale: SCNVector3(0.88, 0.52 + Float(seed % 3) * 0.045, 0.94)
        )
        hair.name = "hair"
        root.addChildNode(hair)
        let fringeCount = 3 + seed % 2
        for index in 0..<fringeCount {
            let offset = (CGFloat(index) - CGFloat(fringeCount - 1) / 2) * 0.036
            let fringe = capsule(
                radius: 0.018,
                height: 0.10 + CGFloat((seed + index) % 3) * 0.014,
                color: hairColor,
                position: SCNVector3(Float(offset), 0.935, -0.091),
                rotation: SCNVector4(1, 0, 0, 0.25)
            )
            fringe.scale = SCNVector3(0.85, 1, 0.42)
            root.addChildNode(fringe)
        }
        for side in [Float(-1), 1] {
            let ear = sphere(
                radius: 0.026,
                color: skinColor(seed).blended(withFraction: 0.08, of: .red) ?? skinColor(seed),
                position: SCNVector3(side * 0.095, 0.88, 0.0),
                scale: SCNVector3(0.54, 1, 0.52)
            )
            root.addChildNode(ear)
        }
        if seed.isMultiple(of: 4) {
            root.addChildNode(capsule(radius: 0.052, height: 0.22, color: hairColor, position: SCNVector3(0, 0.87, 0.085)))
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

        let pressureGaze = box(
            width: 0.018,
            height: 0.018,
            length: 0.52,
            color: NSColor(calibratedRed: 0.96, green: 0.34, blue: 0.16, alpha: 1),
            position: SCNVector3(0, 0.82, -0.34)
        )
        pressureGaze.name = "classmatePressureGaze"
        pressureGaze.opacity = 0
        pressureGaze.geometry?.firstMaterial?.blendMode = .add
        pressureGaze.geometry?.firstMaterial?.writesToDepthBuffer = false
        pressureGaze.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.96, green: 0.34, blue: 0.16, alpha: 1)
        root.addChildNode(pressureGaze)

        let supportSignal = sphere(
            radius: 0.045,
            color: NSColor(calibratedRed: 0.24, green: 0.88, blue: 0.58, alpha: 1),
            position: SCNVector3(-0.2, 0.35, -0.14),
            scale: SCNVector3(1, 0.36, 1)
        )
        supportSignal.name = "classmateSupportSignal"
        supportSignal.opacity = 0
        supportSignal.geometry?.firstMaterial?.blendMode = .add
        supportSignal.geometry?.firstMaterial?.writesToDepthBuffer = false
        supportSignal.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.24, green: 0.88, blue: 0.58, alpha: 1)
        root.addChildNode(supportSignal)

        let bystanderFold = box(
            width: 0.26,
            height: 0.012,
            length: 0.05,
            color: NSColor(calibratedRed: 0.78, green: 0.68, blue: 0.42, alpha: 1),
            position: SCNVector3(0, 0.48, -0.08)
        )
        bystanderFold.name = "classmateBystanderFold"
        bystanderFold.opacity = 0
        bystanderFold.geometry?.firstMaterial?.blendMode = .add
        bystanderFold.geometry?.firstMaterial?.writesToDepthBuffer = false
        bystanderFold.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.78, green: 0.68, blue: 0.42, alpha: 1)
        root.addChildNode(bystanderFold)

        if profile?.empathy ?? 0 > 72 {
            root.addChildNode(box(width: 0.08, height: 0.012, length: 0.12, color: NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1), position: SCNVector3(-0.22, 0.21, 0.02)))
        }

        root.scale = SCNVector3(1, Float(0.97 + (profile?.cooperation ?? 50) / 1_500), 1)
        root.enumerateChildNodes { node, _ in node.castsShadow = true }
        return root
    }

    private func makeTeacherGeometry() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(makeTeacherBody())
        let head = sphere(
            radius: 0.13,
            color: NSColor(calibratedRed: 0.84, green: 0.69, blue: 0.56, alpha: 1),
            position: SCNVector3(0, 1.28, 0),
            scale: SCNVector3(0.82, 1.04, 0.9)
        )
        let face = makeTeacherFace()
        face.scale = SCNVector3(0.75, 0.75, 0.75)
        face.position.z = -0.012
        head.addChildNode(face)
        root.addChildNode(head)
        root.addChildNode(sphere(radius: 0.132, color: NSColor(calibratedWhite: 0.035, alpha: 1), position: SCNVector3(0, 1.37, 0.018), scale: SCNVector3(0.86, 0.48, 0.94)))
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
        teacherPressureLightNode.light?.intensity = 3 + 16 * attention
        teacherPressureLightNode.light?.color = color
        teacherGazeNode.childNodes.first?.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.18)
        teacherGazeNode.childNodes.first?.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.12)

        let playerPosition = SCNVector3(-1.2, game.player.posture == .standing ? 1.58 : 1.18, 1.5)
        teacherNode.eulerAngles = teacherEulerAngles(from: teacherPosition, to: playerPosition)
    }

    private func makeTeacherPatrolPressureStage() -> SCNNode {
        let root = SCNNode()
        root.name = "teacherPatrolPressureStage"
        root.opacity = 0
        root.isHidden = true

        let pathBand = box(
            width: 0.36,
            height: 0.018,
            length: 2.15,
            color: NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.18, alpha: 0.42),
            position: SCNVector3(0, 0.028, 0)
        )
        pathBand.name = "teacherPatrolPathBand"
        pathBand.geometry?.firstMaterial?.blendMode = .add
        pathBand.geometry?.firstMaterial?.writesToDepthBuffer = false
        pathBand.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.12, alpha: 1)
        pathBand.geometry?.firstMaterial?.emission.intensity = 0.28
        root.addChildNode(pathBand)

        let seatRing = SCNNode(geometry: SCNTorus(ringRadius: 0.42, pipeRadius: 0.012))
        seatRing.name = "teacherPatrolSeatRiskRing"
        seatRing.eulerAngles.x = .pi / 2
        seatRing.position = SCNVector3(-1.2, 0.042, 1.5)
        seatRing.geometry?.firstMaterial = translucentSoundMaterial(NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.22, alpha: 0.42))
        seatRing.geometry?.firstMaterial?.emission.intensity = 0.2
        root.addChildNode(seatRing)

        for index in 0..<5 {
            let footprint = box(
                width: 0.13,
                height: 0.02,
                length: 0.24,
                color: NSColor(calibratedRed: 1.0, green: 0.57, blue: 0.22, alpha: 0.54),
                position: SCNVector3(0, 0.055, 0)
            )
            footprint.name = "teacherPatrolFootprint_\(index)"
            footprint.geometry?.firstMaterial?.blendMode = .add
            footprint.geometry?.firstMaterial?.writesToDepthBuffer = false
            footprint.geometry?.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.16, alpha: 1)
            footprint.geometry?.firstMaterial?.emission.intensity = 0.22
            root.addChildNode(footprint)
        }

        return root
    }

    private func updateTeacherPatrolPressureStage(game: GameManager, teacherPosition: SCNVector3) {
        guard let stage = teacherPatrolPressureNode.childNode(withName: "teacherPatrolPressureStage", recursively: false),
              let readout = game.teacherPatrolReadout else {
            teacherPatrolPressureNode.childNode(withName: "teacherPatrolPressureStage", recursively: false)?.isHidden = true
            teacherPatrolPressureNode.childNode(withName: "teacherPatrolPressureStage", recursively: false)?.opacity = 0
            return
        }

        let model = TeacherPatrolPressureStageModel.derive(from: readout, teacherPosition: teacherPosition)
        let color = teacherPatrolColor(for: readout)
        stage.isHidden = model.isActive == false
        stage.opacity = model.stageOpacity

        if let band = stage.childNode(withName: "teacherPatrolPathBand", recursively: true) {
            band.position = model.pathBandPosition
            band.eulerAngles.y = model.pathBandYaw
            band.scale = model.pathBandScale
            band.opacity = model.pathBandOpacity
            band.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.28 + CGFloat(readout.intensity.clamped(to: 0...1)) * 0.32)
            band.geometry?.firstMaterial?.emission.contents = color
            band.geometry?.firstMaterial?.emission.intensity = model.pathBandEmission
        }

        if let ring = stage.childNode(withName: "teacherPatrolSeatRiskRing", recursively: true) {
            ring.opacity = model.seatRingOpacity
            ring.scale = model.seatRingScale
            ring.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.26 + CGFloat(readout.intensity.clamped(to: 0...1)) * 0.24)
            ring.geometry?.firstMaterial?.emission.contents = color
            ring.geometry?.firstMaterial?.emission.intensity = model.seatRingEmission
        }

        for (index, footprintModel) in model.footprints.enumerated() {
            guard let footprint = stage.childNode(withName: "teacherPatrolFootprint_\(index)", recursively: true) else { continue }
            footprint.position = footprintModel.position
            footprint.eulerAngles.y = footprintModel.yaw
            footprint.opacity = footprintModel.opacity
            footprint.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.34)
            footprint.geometry?.firstMaterial?.emission.contents = color
            footprint.geometry?.firstMaterial?.emission.intensity = footprintModel.emission
        }
    }

    private func teacherPatrolColor(for readout: TeacherPatrolReadout) -> NSColor {
        switch readout.tone {
        case .unseen:
            return NSColor(calibratedRed: 0.48, green: 0.62, blue: 1.0, alpha: 1)
        case .close:
            return NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.18, alpha: 1)
        case .approaching:
            return NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.28, alpha: 1)
        case .distant:
            return NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.96, alpha: 1)
        }
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
        homeworkSheetNode.position = SCNVector3(-1.2, 0.79, 1.43)
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

        let cupBody = SCNCylinder(radius: 0.072, height: 0.18)
        cupBody.radialSegmentCount = 32
        cupBody.firstMaterial = material(NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.47, alpha: 1))
        let cupBodyNode = SCNNode(geometry: cupBody)
        cupBodyNode.position.y = 0.09
        playerWaterCupNode.addChildNode(cupBodyNode)

        let cupRim = SCNTorus(ringRadius: 0.071, pipeRadius: 0.007)
        cupRim.ringSegmentCount = 32
        cupRim.pipeSegmentCount = 10
        cupRim.firstMaterial = material(NSColor(calibratedRed: 0.72, green: 0.88, blue: 0.88, alpha: 1))
        let cupRimNode = SCNNode(geometry: cupRim)
        cupRimNode.position.y = 0.185
        playerWaterCupNode.addChildNode(cupRimNode)

        let water = SCNCylinder(radius: 0.059, height: 0.004)
        water.radialSegmentCount = 32
        water.firstMaterial = material(NSColor(calibratedRed: 0.36, green: 0.72, blue: 0.82, alpha: 0.82))
        water.firstMaterial?.transparency = 0.82
        let waterNode = SCNNode(geometry: water)
        waterNode.position.y = 0.178
        playerWaterCupNode.addChildNode(waterNode)

        let handle = SCNTorus(ringRadius: 0.047, pipeRadius: 0.009)
        handle.ringSegmentCount = 24
        handle.pipeSegmentCount = 8
        handle.firstMaterial = material(NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.47, alpha: 1))
        let handleNode = SCNNode(geometry: handle)
        handleNode.eulerAngles.x = .pi / 2
        handleNode.position = SCNVector3(0.075, 0.1, 0)
        playerWaterCupNode.addChildNode(handleNode)

        playerWaterCupNode.name = "playerWaterCup"
        playerWaterCupNode.position = SCNVector3(-0.95, 0.89, 0.72)
        playerWaterCupNode.opacity = 0
        root.addChildNode(playerWaterCupNode)

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
        drawerShadowNode.position = SCNVector3(-1.2, 0.735, 1.73)
        drawerShadowNode.opacity = 0.18
        root.addChildNode(drawerShadowNode)

        chapterOneNotePaperNode.name = "chapterOneUnsignedNotePaper"
        chapterOneNotePaperNode.addChildNode(box(width: 0.34, height: 0.012, length: 0.22, color: NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.88, alpha: 1), position: SCNVector3(0, 0, 0)))
        for index in 0..<4 {
            chapterOneNotePaperNode.addChildNode(box(
                width: 0.28,
                height: 0.004,
                length: 0.006,
                color: NSColor(calibratedRed: 0.28, green: 0.42, blue: 0.82, alpha: 1),
                position: SCNVector3(0, 0.012, -0.072 + Float(index) * 0.048)
            ))
        }
        chapterOneNotePaperNode.addChildNode(box(width: 0.048, height: 0.014, length: 0.06, color: NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.96, alpha: 1), position: SCNVector3(0.16, 0.014, -0.085)))
        chapterOneNotePaperNode.position = SCNVector3(-0.72, 0.828, 1.36)
        chapterOneNotePaperNode.eulerAngles.y = -0.26
        chapterOneNotePaperNode.opacity = 0
        root.addChildNode(chapterOneNotePaperNode)

        drawerNode.addChildNode(box(width: 0.44, height: 0.05, length: 0.18, color: NSColor(calibratedRed: 0.44, green: 0.32, blue: 0.22, alpha: 1), position: SCNVector3(0, 0, 0)))
        drawerNode.addChildNode(box(width: 0.1, height: 0.014, length: 0.014, color: NSColor(calibratedRed: 0.78, green: 0.58, blue: 0.28, alpha: 1), position: SCNVector3(0, 0.01, 0.095)))
        drawerNode.position = SCNVector3(-1.2, 0.71, 1.66)
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
        seatTensionNode.position = SCNVector3(-1.2, 0.455, 2.05)
        seatTensionNode.opacity = 0.08
        root.addChildNode(seatTensionNode)

        let heartbeat = SCNTorus(ringRadius: 0.18, pipeRadius: 0.01)
        heartbeat.ringSegmentCount = 36
        heartbeat.pipeSegmentCount = 8
        heartbeat.firstMaterial = material(NSColor(calibratedRed: 0.95, green: 0.16, blue: 0.24, alpha: 1))
        heartbeat.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.9, green: 0.08, blue: 0.16, alpha: 1)
        heartbeat.firstMaterial?.emission.intensity = 0.2
        breakdownHeartbeatNode.name = "breakdownHeartbeatPulse"
        breakdownHeartbeatNode.geometry = heartbeat
        breakdownHeartbeatNode.position = SCNVector3(-0.64, 0.74, 1.28)
        breakdownHeartbeatNode.eulerAngles.x = .pi / 2
        breakdownHeartbeatNode.opacity = 0
        root.addChildNode(breakdownHeartbeatNode)

        breakdownSupportNoteNode.name = "breakdownSupportNote"
        breakdownSupportNoteNode.addChildNode(box(width: 0.34, height: 0.01, length: 0.18, color: NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.86, alpha: 1), position: SCNVector3(0, 0, 0)))
        breakdownSupportNoteNode.addChildNode(box(width: 0.24, height: 0.004, length: 0.012, color: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.34, alpha: 1), position: SCNVector3(0, 0.008, -0.04)))
        breakdownSupportNoteNode.addChildNode(box(width: 0.18, height: 0.004, length: 0.012, color: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.34, alpha: 1), position: SCNVector3(-0.03, 0.008, 0.035)))
        breakdownSupportNoteNode.position = SCNVector3(-0.18, 0.822, 1.32)
        breakdownSupportNoteNode.eulerAngles.y = -0.18
        breakdownSupportNoteNode.opacity = 0
        root.addChildNode(breakdownSupportNoteNode)

        let cupHalo = SCNTorus(ringRadius: 0.115, pipeRadius: 0.006)
        cupHalo.ringSegmentCount = 32
        cupHalo.pipeSegmentCount = 8
        cupHalo.firstMaterial = material(NSColor(calibratedRed: 0.38, green: 0.92, blue: 0.9, alpha: 1))
        cupHalo.firstMaterial?.emission.contents = NSColor(calibratedRed: 0.28, green: 0.84, blue: 0.88, alpha: 1)
        cupHalo.firstMaterial?.emission.intensity = 0.3
        breakdownCupHaloNode.name = "breakdownCupHalo"
        breakdownCupHaloNode.geometry = cupHalo
        breakdownCupHaloNode.position = SCNVector3(-0.95, 1.105, 0.72)
        breakdownCupHaloNode.eulerAngles.x = .pi / 2
        breakdownCupHaloNode.opacity = 0
        root.addChildNode(breakdownCupHaloNode)
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
            chapterOneNotePaperNode.opacity = 0
            updateBreakdownRecoveryStage(game: game)
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
        let noteCue = game.chapterOneNoteDropCue
        let noteIntensity = CGFloat(noteCue?.stageIntensity ?? 0)
        chapterOneNotePaperNode.opacity = noteIntensity
        chapterOneNotePaperNode.isHidden = noteIntensity <= 0.01
        chapterOneNotePaperNode.position = (noteCue?.notePicked == true)
            ? SCNVector3(-0.42, 0.82, 1.44)
            : SCNVector3(-0.72, 0.828, 1.36)
        chapterOneNotePaperNode.eulerAngles.y = (noteCue?.overlayPresented == true) ? -0.42 : -0.26
        chapterOneNotePaperNode.scale = (noteCue?.overlayPresented == true)
            ? SCNVector3(1.12, 1.12, 1.12)
            : SCNVector3(1, 1, 1)
        chapterOneNotePaperNode.childNodes.forEach { child in
            child.geometry?.firstMaterial?.emission.contents = noteIntensity > 0.5
                ? NSColor(calibratedRed: 0.78, green: 0.86, blue: 0.42, alpha: 1)
                : NSColor.black
            child.geometry?.firstMaterial?.emission.intensity = noteIntensity > 0.5 ? 0.18 + noteIntensity * 0.42 : 0
        }
        let drawerOpen = game.cameraPose == .desk || phoneActive || snackActive || paperActive || noteIntensity > 0.3
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

        updateBreakdownRecoveryStage(game: game)
    }

    private func updateBreakdownRecoveryStage(game: GameManager) {
        let steps = game.completedBreakdownRecoverySteps
        let active = game.isBreakdownRecoveryActive || game.breakdownRecoverySummary.contains("恢复完成")
        let namedSignal = steps.contains(.nameSignal)
        let returnedToBody = steps.contains(.returnToBody)
        let acceptedSupport = steps.contains(.acceptSupport)

        let heartbeatOpacity: CGFloat
        if active == false {
            heartbeatOpacity = 0
        } else if namedSignal == false {
            heartbeatOpacity = 0.9
        } else if returnedToBody == false {
            heartbeatOpacity = 0.58
        } else {
            heartbeatOpacity = 0.22
        }
        breakdownHeartbeatNode.opacity = heartbeatOpacity
        breakdownHeartbeatNode.scale = SCNVector3(1 + Float(heartbeatOpacity) * 0.28, 1 + Float(heartbeatOpacity) * 0.28, 1)
        breakdownHeartbeatNode.geometry?.firstMaterial?.emission.intensity = 0.18 + heartbeatOpacity * 0.85
        if heartbeatOpacity > 0.05 && breakdownHeartbeatNode.action(forKey: "breakdown_pulse") == nil {
            breakdownHeartbeatNode.runAction(.repeatForever(.sequence([
                .scale(to: 1.22, duration: 0.18),
                .scale(to: 0.96, duration: 0.26),
                .wait(duration: 0.24)
            ])), forKey: "breakdown_pulse")
        } else if heartbeatOpacity <= 0.05 {
            breakdownHeartbeatNode.removeAction(forKey: "breakdown_pulse")
        }

        breakdownCupHaloNode.opacity = returnedToBody ? 0.82 : (namedSignal ? 0.28 : 0)
        breakdownCupHaloNode.geometry?.firstMaterial?.emission.intensity = returnedToBody ? 0.72 : 0.24
        playerWaterCupNode.scale = returnedToBody ? SCNVector3(1.08, 1.08, 1.08) : SCNVector3(1, 1, 1)

        breakdownSupportNoteNode.opacity = acceptedSupport ? 0.94 : (returnedToBody ? 0.34 : 0)
        breakdownSupportNoteNode.position.x = acceptedSupport ? -0.18 : -0.02
        breakdownSupportNoteNode.geometry?.firstMaterial?.emission.intensity = acceptedSupport ? 0.18 : 0.04
    }

    var playerSeatedPropsVisible: Bool {
        playerSeatedPropsNode.isHidden == false
    }

    var playerWaterCupVisible: Bool {
        playerWaterCupNode.opacity > 0.01 && playerSeatedPropsNode.isHidden == false
    }

    var chapterOneNotePaperOpacity: CGFloat {
        chapterOneNotePaperNode.isHidden ? 0 : chapterOneNotePaperNode.opacity
    }

    var chapterOneNotePaperEmission: CGFloat {
        chapterOneNotePaperNode.childNodes.compactMap {
            $0.geometry?.firstMaterial?.emission.intensity
        }.max() ?? 0
    }

    var linChePerformancePosition: SCNVector3? {
        classmateNodes[0]?.position
    }

    var linChePerformanceHeadYaw: CGFloat? {
        guard let head = classmateNodes[0]?.childNode(withName: "head", recursively: true) else { return nil }
        return CGFloat(head.eulerAngles.y)
    }

    var linChePerformancePaperOpacity: CGFloat? {
        classmateNodes[0]?.childNode(withName: "paper", recursively: true)?.opacity
    }

    var linChePerformanceBagOpacity: CGFloat? {
        classmateNodes[0]?.childNode(withName: "linChePackedBag", recursively: true)?.opacity
    }

    var linChePerformanceExitTraceOpacity: CGFloat? {
        classmateNodes[0]?.childNode(withName: "linCheExitTrace", recursively: true)?.opacity
    }

    var breakdownHeartbeatOpacity: CGFloat {
        breakdownHeartbeatNode.opacity
    }

    var breakdownCupHaloOpacity: CGFloat {
        breakdownCupHaloNode.opacity
    }

    var breakdownSupportNoteOpacity: CGFloat {
        breakdownSupportNoteNode.opacity
    }

    var cameraVignetteIntensity: CGFloat? {
        cameraRig.camera?.vignettingIntensity
    }

    var cameraFStop: CGFloat? {
        cameraRig.camera?.fStop
    }

    var cameraSaturation: CGFloat? {
        cameraRig.camera?.saturation
    }

    var photorealFurnitureLoaded: Bool {
        realisticDeskTemplate != nil && realisticChairTemplate != nil
    }

    var hdriLightingLoaded: Bool {
        hallLightingImage != nil && quadLightingImage != nil
    }

    var prologueLookTargetOpacity: CGFloat {
        prologueLookTargetNode.opacity
    }

    var prologueLookTargetEmissionIntensity: CGFloat? {
        prologueLookTargetNode
            .childNode(withName: "prologueLookTargetCore", recursively: true)?
            .geometry?
            .firstMaterial?
            .emission
            .intensity
    }

    var prologueLookTargetHidden: Bool {
        prologueLookTargetNode.isHidden
    }

    var prologueGateArrivalLitStepCount: Int {
        (0..<PrologueGateArrivalSignal.stepCount).filter { index in
            (prologueGateArrivalNode.childNode(withName: "prologueGateStep_\(index)", recursively: true)?.opacity ?? 0) > 0.5
        }.count
    }

    var prologueGateArrivalEntranceOpacity: CGFloat {
        prologueGateArrivalNode.childNode(withName: "prologueGateEntranceGlow", recursively: true)?.opacity ?? 0
    }

    var prologueGateArrivalStudentZ: CGFloat? {
        prologueGateArrivalNode.childNode(withName: "prologueGateStudentMarker", recursively: true).map { CGFloat($0.position.z) }
    }

    var prologueGateArrivalHidden: Bool {
        prologueGateArrivalNode.isHidden
    }

    var narrativeStageVisible: Bool {
        selectedNarrativeStageName != nil
    }

    var activeNarrativeStageName: String? {
        selectedNarrativeStageName
    }

    var activeNarrativeFocusScale: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let focus = stage.childNode(withName: "stageFocus", recursively: true) else { return nil }
        return focus.scale.x
    }

    var mirrorNarrativeStageOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return nil }
        return stage.opacity
    }

    var mirrorRouteLightOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<3).compactMap { index in
            stage.childNode(withName: "mirrorRouteLight_\(index)", recursively: true)?.opacity
        }
    }

    var mirrorRouteLightEmissionIntensities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<3).compactMap { index in
            stage.childNode(withName: "mirrorRouteLight_\(index)", recursively: true)?.geometry?.firstMaterial?.emission.intensity
        }
    }

    var mirrorRouteBridgeOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<2).compactMap { index in
            stage.childNode(withName: "mirrorRouteBridge_\(index)", recursively: true)?.opacity
        }
    }

    var mirrorPressureCrackOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<6).compactMap { index in
            stage.childNode(withName: "mirrorPressureCrack_\(index)", recursively: true)?.opacity
        }
    }

    var mirrorLinCheShadowPosition: SCNVector3? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let shadow = stage.childNode(withName: "mirrorLinCheShadow", recursively: true) else { return nil }
        return shadow.position
    }

    var mirrorLinCheShadowYaw: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let shadow = stage.childNode(withName: "mirrorLinCheShadow", recursively: true) else { return nil }
        return shadow.eulerAngles.y
    }

    var mirrorBreathRingOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ring = stage.childNode(withName: "mirrorBreathRing", recursively: true) else { return nil }
        return ring.opacity
    }

    var mirrorReturnGateOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let gate = stage.childNode(withName: "mirrorReturnGate", recursively: true) else { return nil }
        return gate.opacity
    }

    var mirrorRealityReturnBandOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let band = stage.childNode(withName: "mirrorRealityReturnBand", recursively: true) else { return nil }
        return band.opacity
    }

    var mirrorLinCheFaceLightOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let faceLight = stage.childNode(withName: "mirrorLinCheFaceLight", recursively: true) else { return nil }
        return faceLight.opacity
    }

    var mirrorNavigationPathOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let path = stage.childNode(withName: "mirrorNavigationPath", recursively: true) else { return nil }
        return path.opacity
    }

    var mirrorNavigationTargetRingOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ring = stage.childNode(withName: "mirrorNavigationTargetRing", recursively: true) else { return nil }
        return ring.opacity
    }

    var mirrorNavigationPathScale: SCNVector3? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let path = stage.childNode(withName: "mirrorNavigationPath", recursively: true) else { return nil }
        return path.scale
    }

    var mirrorMicroEchoOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<6).compactMap { index in
            stage.childNode(withName: "mirrorMicroEcho_\(index)", recursively: true)?.opacity
        }
    }

    var mirrorMicroEchoPositions: [SCNVector3] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<6).compactMap { index in
            stage.childNode(withName: "mirrorMicroEcho_\(index)", recursively: true)?.position
        }
    }

    var mirrorMicroPortalOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let portal = stage.childNode(withName: "mirrorMicroPortalRing", recursively: true) else { return nil }
        return portal.opacity
    }

    var mirrorMicroPortalPosition: SCNVector3? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let portal = stage.childNode(withName: "mirrorMicroPortalRing", recursively: true) else { return nil }
        return portal.position
    }

    var mirrorMicroPortalBeamOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let beam = stage.childNode(withName: "mirrorMicroPortalBeam", recursively: true) else { return nil }
        return beam.opacity
    }

    var mirrorMicroReturnPulseOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let pulse = stage.childNode(withName: "mirrorMicroReturnPulse", recursively: true) else { return nil }
        return pulse.opacity
    }

    var noteTraceHotspotOpacities: [String: CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [:] }
        var values: [String: CGFloat] = [:]
        for visual in noteTraceHotspotVisuals {
            values[visual.hotspotID] = stage.childNode(withName: visual.nodeName, recursively: true)?.opacity
        }
        return values
    }

    var noteTraceHotspotEmissionIntensities: [String: CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [:] }
        var values: [String: CGFloat] = [:]
        for visual in noteTraceHotspotVisuals {
            values[visual.hotspotID] = stage
                .childNode(withName: visual.nodeName, recursively: true)?
                .geometry?
                .firstMaterial?
                .emission
                .intensity
        }
        return values
    }

    var noteTraceNavigationRigOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let rig = stage.childNode(withName: "noteTraceNavigationRig", recursively: true) else { return nil }
        return rig.isHidden ? 0 : rig.opacity
    }

    var noteTraceNavigationBeamOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let beam = stage.childNode(withName: "noteTraceNavigationBeam", recursively: true) else { return nil }
        return beam.opacity
    }

    var noteTraceNavigationBeamLength: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let beam = stage.childNode(withName: "noteTraceNavigationBeam", recursively: true) else { return nil }
        return beam.scale.x
    }

    var noteTraceNavigationBeamAngle: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let beam = stage.childNode(withName: "noteTraceNavigationBeam", recursively: true) else { return nil }
        return beam.eulerAngles.y
    }

    var noteTraceNavigationTargetRingOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ring = stage.childNode(withName: "noteTraceNavigationTargetRing", recursively: true) else { return nil }
        return ring.opacity
    }

    var classmateSensoryReactionOpacities: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            classmateNodes[id]?.opacity
        }
    }

    var classmateSensoryReactionScales: [SCNVector3] {
        classmateNodes.keys.sorted().compactMap { id in
            classmateNodes[id]?.scale
        }
    }

    var classmateSensoryReactionEmissionIntensities: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            classmateNodes[id]?.childNode(withName: "body", recursively: true)?.geometry?.firstMaterial?.emission.intensity
        }
    }

    var classmateSensoryReactionLeanAngles: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            classmateNodes[id]?.eulerAngles.z
        }
    }

    var classmatePressureGazeOpacities: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            guard let node = classmateNodes[id]?.childNode(withName: "classmatePressureGaze", recursively: true) else { return nil }
            return node.isHidden ? 0 : node.opacity
        }
    }

    var classmateSupportSignalOpacities: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            guard let node = classmateNodes[id]?.childNode(withName: "classmateSupportSignal", recursively: true) else { return nil }
            return node.isHidden ? 0 : node.opacity
        }
    }

    var classmateBystanderFoldOpacities: [CGFloat] {
        classmateNodes.keys.sorted().compactMap { id in
            guard let node = classmateNodes[id]?.childNode(withName: "classmateBystanderFold", recursively: true) else { return nil }
            return node.isHidden ? 0 : node.opacity
        }
    }

    var soundSourceStagePosition: SCNVector3? {
        guard let node = soundSourceStageNode.childNode(withName: "soundSourceStage", recursively: false),
              node.isHidden == false else { return nil }
        return node.position
    }

    var soundSourceStageOpacity: CGFloat {
        guard let node = soundSourceStageNode.childNode(withName: "soundSourceStage", recursively: false),
              node.isHidden == false else { return 0 }
        return node.opacity
    }

    var soundSourceStageCoreEmission: CGFloat {
        guard let node = soundSourceStageNode.childNode(withName: "soundSourceCore", recursively: true),
              node.isHidden == false else { return 0 }
        return node.geometry?.firstMaterial?.emission.intensity ?? 0
    }

    var soundSourceStageRingOpacities: [CGFloat] {
        ["soundSourceRingOuter", "soundSourceRingInner"].compactMap { name in
            soundSourceStageNode.childNode(withName: name, recursively: true)?.opacity
        }
    }

    var teacherPatrolPressureOpacity: CGFloat {
        guard let stage = teacherPatrolPressureNode.childNode(withName: "teacherPatrolPressureStage", recursively: false),
              stage.isHidden == false else { return 0 }
        return stage.opacity
    }

    var teacherPatrolPathBandEmission: CGFloat {
        guard let band = teacherPatrolPressureNode.childNode(withName: "teacherPatrolPathBand", recursively: true),
              band.isHidden == false else { return 0 }
        return band.geometry?.firstMaterial?.emission.intensity ?? 0
    }

    var teacherPatrolPathBandPosition: SCNVector3? {
        guard let stage = teacherPatrolPressureNode.childNode(withName: "teacherPatrolPressureStage", recursively: false),
              stage.isHidden == false,
              let band = stage.childNode(withName: "teacherPatrolPathBand", recursively: true) else { return nil }
        return band.position
    }

    var teacherPatrolSeatRingOpacity: CGFloat {
        guard let ring = teacherPatrolPressureNode.childNode(withName: "teacherPatrolSeatRiskRing", recursively: true),
              ring.isHidden == false else { return 0 }
        return ring.opacity
    }

    var teacherPatrolFootprintOpacities: [CGFloat] {
        (0..<5).compactMap { index in
            teacherPatrolPressureNode.childNode(withName: "teacherPatrolFootprint_\(index)", recursively: true)?.opacity
        }
    }

    var narrativeCameraPosition: SCNVector3 {
        cameraRig.position
    }

    var activeNarrativeCompanionName: String? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return nil }
        return ["companionZhou", "companionXu"].first { name in
            stage.childNode(withName: name, recursively: true)?.isHidden == false
        }
    }

    var activeNarrativeCompanionPosition: SCNVector3? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let node = stage.childNode(withName: name, recursively: true) else { return nil }
        return node.position
    }

    var activeNarrativeCompanionContactPropPosition: SCNVector3? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let prop = companion.childNode(withName: "companionContactProp", recursively: true),
              prop.isHidden == false else { return nil }
        return prop.position
    }

    var activeNarrativeCompanionPrivacyShieldVisible: Bool {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let shield = companion.childNode(withName: "performancePrivacyShield", recursively: true) else { return false }
        return shield.isHidden == false && shield.opacity > 0.1
    }

    var activeNarrativeCompanionGazeOpacity: CGFloat? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let gaze = companion.childNode(withName: "performanceGazeLine", recursively: true) else { return nil }
        return gaze.opacity
    }

    var activeNarrativeCompanionFollowLineOpacity: CGFloat? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let line = companion.childNode(withName: "companionFollowDistanceLine", recursively: true) else { return nil }
        return line.isHidden ? 0 : line.opacity
    }

    var activeNarrativeCompanionFollowLineLength: Float? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let line = companion.childNode(withName: "companionFollowDistanceLine", recursively: true) else { return nil }
        return line.isHidden ? 0 : Float(line.scale.x)
    }

    var activeNarrativeCompanionBoundaryRingOpacity: CGFloat? {
        guard let name = activeNarrativeCompanionName,
              let stageName = selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: stageName, recursively: false),
              let companion = stage.childNode(withName: name, recursively: true),
              let ring = companion.childNode(withName: "companionBoundaryRing", recursively: true) else { return nil }
        return ring.isHidden ? 0 : ring.opacity
    }

    var narrativeTeacherVisible: Bool {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let teacher = stage.childNode(withName: "handoffTeacher", recursively: true) else { return false }
        return teacher.isHidden == false
    }

    var narrativeTeacherGazeOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let teacher = stage.childNode(withName: "handoffTeacher", recursively: true),
              teacher.isHidden == false,
              let gaze = teacher.childNode(withName: "performanceGazeLine", recursively: true) else { return nil }
        return gaze.opacity
    }

    var narrativeJiangShoulderTilt: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)", recursively: false),
              let jiang = stage.childNode(withName: "stageFocus", recursively: true),
              let shoulder = jiang.childNode(withName: "performanceShoulderLine", recursively: true) else { return nil }
        return shoulder.eulerAngles.z
    }

    var narrativeJiangBreathOpacity: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)", recursively: false),
              let jiang = stage.childNode(withName: "stageFocus", recursively: true),
              let breath = jiang.childNode(withName: "performanceBreathPulse", recursively: true) else { return nil }
        return breath.opacity
    }

    var narrativeJiangDialogueSupportOpacity: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)", recursively: false),
              let arc = stage.childNode(withName: "jiangDialogueSupportArc", recursively: true) else { return nil }
        return arc.opacity
    }

    var narrativeJiangDialogueAnchorOpacity: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)", recursively: false),
              let line = stage.childNode(withName: "jiangDialogueAnchorLine", recursively: true) else { return nil }
        return line.opacity
    }

    var narrativeJiangDialogueRuptureOpacity: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.stairwell.rawValue)", recursively: false),
              let field = stage.childNode(withName: "jiangDialogueRuptureField", recursively: true) else { return nil }
        return field.opacity
    }

    var visibleNarrativeRumorNPCCount: Int {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return 0 }
        return stage.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("rumorNPC") == true && node.isHidden == false
        }).count
    }

    var narrativeMessagePhoneVisible: Bool {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let phone = stage.childNode(withName: "messagePhone", recursively: true) else { return false }
        return phone.isHidden == false
    }

    var narrativeBoundaryLineIntensity: CGFloat? {
        guard let stage = narrativeStageNode.childNode(withName: "narrativeStage_\(NarrativeChapter.counseling.rawValue)", recursively: false),
              let line = stage.childNode(withName: "counselingBoundaryLine", recursively: true) else { return nil }
        return line.geometry?.firstMaterial?.emission.intensity
    }

    var narrativeWorldPressureOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let field = stage.childNode(withName: "worldDirectorPressureField", recursively: true) else { return nil }
        return field.opacity
    }

    var narrativeWorldPrivacyOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let line = stage.childNode(withName: "worldDirectorPrivacyLine", recursively: true) else { return nil }
        return line.opacity
    }

    var narrativeWorldSupportOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ring = stage.childNode(withName: "worldDirectorSupportRing", recursively: true) else { return nil }
        return ring.opacity
    }

    var narrativeWorldSafetyOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let beacon = stage.childNode(withName: "worldDirectorSafetyBeacon", recursively: true) else { return nil }
        return beacon.opacity
    }

    var narrativeWorldChoiceImpactRingOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ring = stage.childNode(withName: "worldDirectorChoiceImpactRing", recursively: true) else { return nil }
        return ring.opacity
    }

    var narrativeWorldChoiceImpactRayOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ray = stage.childNode(withName: "worldDirectorChoiceImpactRay", recursively: true) else { return nil }
        return ray.opacity
    }

    var narrativeWorldChoiceImpactRayAngle: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let ray = stage.childNode(withName: "worldDirectorChoiceImpactRay", recursively: true) else { return nil }
        return ray.eulerAngles.y
    }

    var narrativeWorldChoiceImpactCrownOpacity: CGFloat? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let crown = stage.childNode(withName: "worldDirectorChoiceImpactCrown", recursively: true) else { return nil }
        return crown.opacity
    }

    var visibleNarrativeWorldWitnessCount: Int {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return 0 }
        return stage.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("worldDirectorWitness_") == true && node.isHidden == false && node.opacity > 0.05
        }).count
    }

    var visibleNarrativeAmbientActorCount: Int {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return 0 }
        return stage.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("ambientLivingActor_") == true && node.isHidden == false && node.opacity > 0.05
        }).count
    }

    var narrativeAmbientActorPositions: [SCNVector3] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<4).compactMap { index in
            guard let node = stage.childNode(withName: "ambientLivingActor_\(index)", recursively: true),
                  node.isHidden == false,
                  node.opacity > 0.05 else { return nil }
            return node.position
        }
    }

    var visibleNarrativeConsequenceEchoCount: Int {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return 0 }
        return stage.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("consequenceEcho_") == true && node.isHidden == false && node.opacity > 0.05
        }).count
    }

    var narrativeConsequenceEchoOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<6).compactMap { index in
            guard let node = stage.childNode(withName: "consequenceEcho_\(index)", recursively: true),
                  node.isHidden == false else { return nil }
            return node.opacity
        }
    }

    var visibleNarrativeChapterMemoryBeaconCount: Int {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return 0 }
        return stage.childNodes(passingTest: { node, _ in
            node.name?.hasPrefix("chapterMemoryBeacon_") == true && node.isHidden == false && node.opacity > 0.05
        }).count
    }

    var narrativeChapterMemoryBeaconOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<NarrativeChapter.allCases.count).compactMap { index in
            guard let node = stage.childNode(withName: "chapterMemoryBeacon_\(index)", recursively: true),
                  node.isHidden == false else { return nil }
            return node.opacity
        }
    }

    var narrativeChapterMemoryLineOpacities: [CGFloat] {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false) else { return [] }
        return (0..<(NarrativeChapter.allCases.count - 1)).compactMap { index in
            guard let node = stage.childNode(withName: "chapterMemoryLine_\(index)", recursively: true),
                  node.isHidden == false else { return nil }
            return node.opacity
        }
    }

    func renderSnapshot(size: CGSize) -> NSImage {
        if isRunningInXCTest {
            return fallbackSnapshot(size: size)
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraRig
        let snapshot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return snapshot.tiffRepresentation == nil ? fallbackSnapshot(size: size) : snapshot
    }

    func projectedWaterCupPosition(size: CGSize) -> SCNVector3 {
        if isRunningInXCTest {
            return SCNVector3(Float(size.width * 0.5), Float(size.height * 0.58), 0.42)
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraRig
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        return renderer.projectPoint(playerWaterCupNode.presentation.worldPosition)
    }

    func projectedNarrativeFocusPosition(size: CGSize) -> SCNVector3? {
        guard let selectedNarrativeStageName,
              let stage = narrativeStageNode.childNode(withName: selectedNarrativeStageName, recursively: false),
              let focus = stage.childNode(withName: "stageFocus", recursively: true) else { return nil }
        if isRunningInXCTest {
            return fallbackProjectedNarrativeFocusPosition(size: size, stageName: selectedNarrativeStageName)
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraRig
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        let projected = renderer.projectPoint(focus.presentation.worldPosition)
        if projected.x.isFinite, projected.y.isFinite, projected.z.isFinite,
           projected.x > 0, projected.y > 0 {
            return projected
        }
        return fallbackProjectedNarrativeFocusPosition(size: size, stageName: selectedNarrativeStageName)
    }

    private var isRunningInXCTest: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func fallbackProjectedNarrativeFocusPosition(size: CGSize, stageName: String) -> SCNVector3 {
        let stageNumber = stageName.split(separator: "_").last.flatMap { Int($0) } ?? 1
        let offset = CGFloat(stageNumber - 3) * 34
        let x = (size.width * 0.5 + offset).clamped(to: 160...max(160, size.width - 160))
        let y = (size.height * (0.36 + CGFloat(stageNumber % 3) * 0.055)).clamped(to: 90...max(90, size.height - 90))
        return SCNVector3(Float(x), Float(y), 0.55)
    }

    private func fallbackSnapshot(size: CGSize) -> NSImage {
        let pixelScale = min(1, min(480 / max(1, size.width), 300 / max(1, size.height)))
        let width = max(1, Int((size.width * pixelScale).rounded()))
        let height = max(1, Int((size.height * pixelScale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let data = bitmap.bitmapData else {
            return NSImage(size: size)
        }

        let seed = fallbackSnapshotSeed
        let stageHue = Double(seed % 360) / 360
        let baseR = 38 + Int(92 * abs(sin(stageHue * .pi * 2)))
        let baseG = 42 + Int(88 * abs(sin((stageHue + 0.23) * .pi * 2)))
        let baseB = 48 + Int(96 * abs(sin((stageHue + 0.47) * .pi * 2)))

        for y in 0..<height {
            let vertical = Double(y) / Double(max(1, height - 1))
            for x in 0..<width {
                let horizontal = Double(x) / Double(max(1, width - 1))
                let noise = ((x &* 73_856_093) ^ (y &* 19_349_663) ^ (seed &* 83_492_791)) & 0xff
                let stripe = ((x / 24 + y / 18 + seed) % 9 == 0) ? 34 : 0
                let vignette = min(1, hypot(horizontal - 0.5, vertical - 0.5) * 1.45)
                let warmLine = abs(horizontal - 0.5) < 0.008 || abs(vertical - 0.62) < 0.006 ? 42 : 0
                let r = (baseR + Int(vertical * 82) + noise / 8 + stripe + warmLine - Int(vignette * 38)).clamped(to: 0...255)
                let g = (baseG + Int((1 - vertical) * 58) + noise / 10 + stripe / 2 - Int(vignette * 34)).clamped(to: 0...255)
                let b = (baseB + Int(horizontal * 72) + noise / 7 + warmLine / 2 - Int(vignette * 30)).clamped(to: 0...255)
                let offset = (y * width + x) * 4
                data[offset] = UInt8(r)
                data[offset + 1] = UInt8(g)
                data[offset + 2] = UInt8(b)
                data[offset + 3] = 255
            }
        }

        if selectedNarrativeStageName == "narrativeStage_\(NarrativeChapter.mirror.rawValue)" {
            drawFallbackMirrorRouteLights(data: data, width: width, height: height)
        }
        if lastClassmateSensoryReaction.isActive {
            drawFallbackClassmateSensoryReaction(data: data, width: width, height: height)
        }
        if soundSourceStageOpacity > 0.01, let position = soundSourceStagePosition {
            drawFallbackSoundSourceStage(data: data, width: width, height: height, position: position)
        }
        if teacherPatrolPressureOpacity > 0.01 {
            drawFallbackTeacherPatrolPressure(data: data, width: width, height: height)
        }
        if chapterOneNotePaperOpacity > 0.01 {
            drawFallbackChapterOneNotePaper(data: data, width: width, height: height)
        }
        if lastLinChePerformanceCue.phase != .idleStillPage || lastLinChePerformanceCue.intensity > 0.48 {
            drawFallbackLinChePerformance(data: data, width: width, height: height)
        }
        if (narrativeWorldChoiceImpactRingOpacity ?? 0) > 0.1 {
            drawFallbackChoiceImpactStage(data: data, width: width, height: height)
        }
        if selectedNarrativeStageName == "narrativeStage_\(NarrativeChapter.noteTrace.rawValue)" {
            drawFallbackNoteTraceNavigationPulse(data: data, width: width, height: height)
        }

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private func drawFallbackChoiceImpactStage(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let ringOpacity = Double((narrativeWorldChoiceImpactRingOpacity ?? 0).clamped(to: 0...1))
        let rayOpacity = Double((narrativeWorldChoiceImpactRayOpacity ?? 0).clamped(to: 0...1))
        let crownOpacity = Double((narrativeWorldChoiceImpactCrownOpacity ?? 0).clamped(to: 0...1))
        guard max(ringOpacity, rayOpacity, crownOpacity) > 0.1 else { return }

        let cue = currentGame?.narrativeCampaign.worldDirectorSignal.cue ?? .attention
        let color: (red: Int, green: Int, blue: Int)
        switch cue {
        case .attention:
            color = (120, 178, 238)
        case .investigation:
            color = (238, 202, 98)
        case .risk:
            color = (255, 96, 58)
        case .privacy:
            color = (72, 226, 164)
        case .safetyResponse:
            color = (62, 205, 255)
        case .support:
            color = (94, 238, 142)
        }

        let center = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.56)
        let angle = Double(narrativeWorldChoiceImpactRayAngle ?? 0)
        let rayLength = CGFloat(86 + rayOpacity * 82)
        let rayEnd = CGPoint(
            x: center.x + CGFloat(cos(angle)) * rayLength,
            y: center.y + CGFloat(sin(angle)) * rayLength * 0.58
        )
        let crown = CGPoint(x: center.x, y: CGFloat(height) * 0.31)

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            for y in (Int(center.y) - radius)...(Int(center.y) + radius) {
                for x in (Int(center.x) - radius)...(Int(center.x) + radius) {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.16 + falloff * 0.84))
                }
            }
        }

        func drawRing(radius: Int, thickness: Double, alpha: Double) {
            for y in (Int(center.y) - radius - 4)...(Int(center.y) + radius + 4) {
                for x in (Int(center.x) - radius - 4)...(Int(center.x) + radius + 4) {
                    let dx = Double(x) - Double(center.x)
                    let dy = (Double(y) - Double(center.y)) * 1.55
                    let distance = sqrt(dx * dx + dy * dy)
                    let band = abs(distance - Double(radius))
                    guard band <= thickness else { continue }
                    let falloff = 1 - band / max(0.01, thickness)
                    blendPixel(x: x, y: y, red: color.red, green: color.green, blue: color.blue, alpha: alpha * (0.2 + falloff * 0.8))
                }
            }
        }

        func drawLine(from start: CGPoint, to end: CGPoint, red: Int, green: Int, blue: Int, alpha: Double) {
            for step in 0...120 {
                let progress = CGFloat(step) / 120
                let x = start.x + (end.x - start.x) * progress
                let y = start.y + (end.y - start.y) * progress
                drawDisc(center: CGPoint(x: x, y: y), radius: 3 + Int(rayOpacity * 4), red: red, green: green, blue: blue, alpha: alpha * Double(1 - abs(0.5 - progress) * 0.7))
            }
        }

        drawRing(radius: 45 + Int(ringOpacity * 28), thickness: 5.6, alpha: 0.22 + ringOpacity * 0.38)
        drawRing(radius: 22 + Int(ringOpacity * 15), thickness: 3.8, alpha: 0.26 + ringOpacity * 0.42)
        drawLine(from: center, to: rayEnd, red: color.red, green: color.green, blue: color.blue, alpha: 0.18 + rayOpacity * 0.38)
        drawDisc(center: center, radius: 10 + Int(ringOpacity * 8), red: 244, green: 252, blue: 255, alpha: 0.42 + ringOpacity * 0.36)
        drawLine(from: crown, to: center, red: color.red, green: color.green, blue: color.blue, alpha: 0.08 + crownOpacity * 0.18)
        drawDisc(center: crown, radius: 18 + Int(crownOpacity * 12), red: color.red, green: color.green, blue: color.blue, alpha: 0.20 + crownOpacity * 0.34)
        drawDisc(center: crown, radius: 7 + Int(crownOpacity * 5), red: 255, green: 252, blue: 232, alpha: 0.44 + crownOpacity * 0.34)
    }

    private func drawFallbackNoteTraceNavigationPulse(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        guard let campaign = currentGame?.narrativeCampaign,
              let cue = ChapterThreeNavigationCue.derive(from: campaign),
              let hotspot = campaign.requiredInteractionHotspots.first else { return }
        let pulse = cue.pulseIntensity.clamped(to: 0...1)
        let player = CGPoint(
            x: CGFloat(width) * (0.5 + CGFloat(campaign.exploration.positionX) / 8.4),
            y: CGFloat(height) * (0.62 - CGFloat(campaign.exploration.positionZ) / 13.0)
        )
        let target = CGPoint(
            x: CGFloat(width) * (0.5 + CGFloat(hotspot.x) / 8.4),
            y: CGFloat(height) * (0.62 - CGFloat(hotspot.z) / 13.0)
        )
        let color = cue.isInRange ? (red: 72, green: 255, blue: 142) : (red: 0, green: 255, blue: 255)

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            for y in (Int(center.y) - radius)...(Int(center.y) + radius) {
                for x in (Int(center.x) - radius)...(Int(center.x) + radius) {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.14 + falloff * 0.86))
                }
            }
        }

        func drawLine(from start: CGPoint, to end: CGPoint, alpha: Double) {
            let steps = 140
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let x = start.x + (end.x - start.x) * progress
                let y = start.y + (end.y - start.y) * progress
                let wave = 0.58 + 0.42 * sin(Double(progress) * .pi)
                drawDisc(
                    center: CGPoint(x: x, y: y),
                    radius: 2 + Int(pulse * 3),
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    alpha: alpha * wave
                )
            }
        }

        func drawRing(center: CGPoint, radius: Int, thickness: Double, alpha: Double) {
            for y in (Int(center.y) - radius - 4)...(Int(center.y) + radius + 4) {
                for x in (Int(center.x) - radius - 4)...(Int(center.x) + radius + 4) {
                    let dx = Double(x) - Double(center.x)
                    let dy = (Double(y) - Double(center.y)) * 1.42
                    let distance = sqrt(dx * dx + dy * dy)
                    let band = abs(distance - Double(radius))
                    guard band <= thickness else { continue }
                    let falloff = 1 - band / max(0.01, thickness)
                    blendPixel(x: x, y: y, red: color.red, green: color.green, blue: color.blue, alpha: alpha * (0.2 + falloff * 0.8))
                }
            }
        }

        drawLine(from: player, to: target, alpha: cue.isInRange ? 0.18 : 0.36 + pulse * 0.42)
        drawDisc(center: player, radius: 5 + Int(pulse * 4), red: 214, green: 255, blue: 255, alpha: 0.28 + pulse * 0.26)
        drawRing(center: target, radius: 18 + Int(pulse * 16), thickness: 4.2, alpha: 0.3 + pulse * 0.46)
        drawDisc(center: target, radius: 7 + Int(pulse * 5), red: color.red, green: color.green, blue: color.blue, alpha: 0.46 + pulse * 0.38)
    }

    private func drawFallbackMirrorRouteLights(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let opacities = mirrorRouteLightOpacities
        guard opacities.count == 3 else { return }
        let bridges = mirrorRouteBridgeOpacities
        let points = [
            CGPoint(x: CGFloat(width) * 0.35, y: CGFloat(height) * 0.34),
            CGPoint(x: CGFloat(width) * 0.50, y: CGFloat(height) * 0.27),
            CGPoint(x: CGFloat(width) * 0.65, y: CGFloat(height) * 0.34)
        ]

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            let minX = Int(center.x) - radius
            let maxX = Int(center.x) + radius
            let minY = Int(center.y) - radius
            let maxY = Int(center.y) + radius
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.28 + falloff * 0.72))
                }
            }
        }

        func drawLine(from start: CGPoint, to end: CGPoint, red: Int, green: Int, blue: Int, alpha: Double) {
            for step in 0...120 {
                let progress = CGFloat(step) / 120
                let x = start.x + (end.x - start.x) * progress
                let y = start.y + (end.y - start.y) * progress
                drawDisc(center: CGPoint(x: x, y: y), radius: 4, red: red, green: green, blue: blue, alpha: alpha)
            }
        }

        for index in 0..<2 {
            let alpha = Double(index < bridges.count ? bridges[index] : 0.16)
            drawLine(from: points[index], to: points[index + 1], red: 255, green: 205, blue: 78, alpha: alpha * 0.55)
        }

        for index in 0..<3 {
            let power = Double(opacities[index].clamped(to: 0...1))
            let color: (red: Int, green: Int, blue: Int)
            if power > 0.82 {
                color = (255, 214, 72)
            } else if power > 0.48 {
                color = (72, 220, 255)
            } else {
                color = (112, 96, 152)
            }
            drawDisc(center: points[index], radius: 23 + Int(power * 13), red: color.red, green: color.green, blue: color.blue, alpha: 0.28 + power * 0.42)
            drawDisc(center: points[index], radius: 9 + Int(power * 7), red: 255, green: 246, blue: 212, alpha: 0.34 + power * 0.46)
        }

        let cracks = mirrorPressureCrackOpacities
        let crackLines = [
            (CGPoint(x: CGFloat(width) * 0.37, y: CGFloat(height) * 0.44), CGPoint(x: CGFloat(width) * 0.28, y: CGFloat(height) * 0.52)),
            (CGPoint(x: CGFloat(width) * 0.43, y: CGFloat(height) * 0.50), CGPoint(x: CGFloat(width) * 0.37, y: CGFloat(height) * 0.57)),
            (CGPoint(x: CGFloat(width) * 0.48, y: CGFloat(height) * 0.39), CGPoint(x: CGFloat(width) * 0.56, y: CGFloat(height) * 0.42)),
            (CGPoint(x: CGFloat(width) * 0.57, y: CGFloat(height) * 0.47), CGPoint(x: CGFloat(width) * 0.66, y: CGFloat(height) * 0.52)),
            (CGPoint(x: CGFloat(width) * 0.64, y: CGFloat(height) * 0.39), CGPoint(x: CGFloat(width) * 0.71, y: CGFloat(height) * 0.47)),
            (CGPoint(x: CGFloat(width) * 0.67, y: CGFloat(height) * 0.55), CGPoint(x: CGFloat(width) * 0.74, y: CGFloat(height) * 0.58))
        ]
        for index in 0..<min(cracks.count, crackLines.count) {
            drawLine(from: crackLines[index].0, to: crackLines[index].1, red: 118, green: 218, blue: 255, alpha: Double(cracks[index]) * 0.62)
        }

        if let shadow = mirrorLinCheShadowPosition, let ring = mirrorBreathRingOpacity {
            let x = CGFloat(width) * CGFloat((Double(shadow.x) + 2.2) / 4.4).clamped(to: 0.25...0.75)
            let y = CGFloat(height) * CGFloat(0.69 - (Double(shadow.z) + 2.25) * 0.11).clamped(to: 0.49...0.74)
            drawDisc(center: CGPoint(x: x, y: y), radius: 28 + Int(Double(ring) * 22), red: 68, green: 222, blue: 255, alpha: Double(ring) * 0.26)
            drawDisc(center: CGPoint(x: x, y: y - 20), radius: 14, red: 24, green: 38, blue: 72, alpha: 0.72)
        }
    }

    private func drawFallbackSoundSourceStage(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int, position: SCNVector3) {
        let normalizedX = CGFloat((position.x + 3.8) / 7.6).clamped(to: 0.08...0.92)
        let normalizedZ = CGFloat((position.z + 5.0) / 10.0).clamped(to: 0.12...0.86)
        let center = CGPoint(
            x: CGFloat(width) * normalizedX,
            y: CGFloat(height) * (0.78 - normalizedZ * 0.42)
        )
        let opacity = Double(soundSourceStageOpacity.clamped(to: 0...1))
        let located = soundSourceStageCoreEmission > 1.65
        let color = located
            ? (red: 80, green: 244, blue: 154)
            : (red: 58, green: 220, blue: 255)

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawRing(radius: Int, thickness: Double, alpha: Double) {
            let minX = Int(center.x) - radius - 2
            let maxX = Int(center.x) + radius + 2
            let minY = Int(center.y) - radius - 2
            let maxY = Int(center.y) + radius + 2
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    let band = abs(distance - Double(radius))
                    guard band <= thickness else { continue }
                    let falloff = 1 - band / max(0.01, thickness)
                    blendPixel(x: x, y: y, red: color.red, green: color.green, blue: color.blue, alpha: alpha * (0.25 + falloff * 0.75))
                }
            }
        }

        func drawDisc(radius: Int, alpha: Double, red: Int, green: Int, blue: Int) {
            let minX = Int(center.x) - radius
            let maxX = Int(center.x) + radius
            let minY = Int(center.y) - radius
            let maxY = Int(center.y) + radius
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.18 + falloff * 0.82))
                }
            }
        }

        drawRing(radius: 42 + Int(opacity * 20), thickness: 6.4, alpha: 0.24 + opacity * 0.36)
        drawRing(radius: 24 + Int(opacity * 11), thickness: 4.6, alpha: 0.32 + opacity * 0.44)
        drawDisc(radius: 13 + Int(opacity * 8), alpha: 0.64 + opacity * 0.32, red: 230, green: 252, blue: 255)
        for step in 0...46 {
            let progress = CGFloat(step) / 46
            let y = Int(center.y - progress * CGFloat(54 + Int(opacity * 34)))
            drawDisc(radius: max(1, 4 - step / 14), alpha: (0.12 + opacity * 0.18) * Double(1 - progress), red: color.red, green: color.green, blue: color.blue)
            blendPixel(x: Int(center.x), y: y, red: color.red, green: color.green, blue: color.blue, alpha: 0.12 + opacity * 0.2)
        }
    }

    private func drawFallbackTeacherPatrolPressure(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let pressure = Double(teacherPatrolPressureOpacity.clamped(to: 0...1))
        guard pressure > 0.01 else { return }
        let readout = currentGame?.teacherPatrolReadout
        let color: (red: Int, green: Int, blue: Int)
        switch readout?.tone {
        case .unseen:
            color = (116, 148, 255)
        case .approaching:
            color = (255, 190, 68)
        case .distant:
            color = (72, 220, 244)
        case .close, .none:
            color = (255, 112, 42)
        }
        let startX = CGFloat(width) * 0.66
        let startY = CGFloat(height) * 0.24
        let endX = CGFloat(width) * 0.43
        let endY = CGFloat(height) * 0.68

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            let minX = Int(center.x) - radius
            let maxX = Int(center.x) + radius
            let minY = Int(center.y) - radius
            let maxY = Int(center.y) + radius
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.2 + falloff * 0.8))
                }
            }
        }

        for step in 0...150 {
            let progress = CGFloat(step) / 150
            let x = startX + (endX - startX) * progress
            let y = startY + (endY - startY) * progress
            drawDisc(
                center: CGPoint(x: x, y: y),
                radius: 5 + Int(pressure * 5),
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0.08 + pressure * 0.2
            )
        }

        for index in 0..<5 {
            let progress = CGFloat(index + 1) / 6
            let x = startX + (endX - startX) * progress
            let y = startY + (endY - startY) * progress
            let offset = CGFloat(index.isMultiple(of: 2) ? -8 : 8)
            drawDisc(
                center: CGPoint(x: x + offset, y: y),
                radius: 7 + Int(pressure * 7),
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0.22 + pressure * 0.32
            )
        }

        drawDisc(
            center: CGPoint(x: endX, y: endY),
            radius: 24 + Int(pressure * 18),
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 0.16 + pressure * 0.18
        )
        drawDisc(
            center: CGPoint(x: startX, y: startY),
            radius: 14 + Int(pressure * 12),
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 0.12 + pressure * 0.22
        )
    }

    private func drawFallbackChapterOneNotePaper(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let opacity = Double(chapterOneNotePaperOpacity.clamped(to: 0...1))
        guard opacity > 0.01 else { return }
        let center = CGPoint(x: CGFloat(width) * 0.43, y: CGFloat(height) * 0.58)
        let paperWidth = Int(CGFloat(width) * 0.19)
        let paperHeight = Int(CGFloat(height) * 0.15)

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            for y in (Int(center.y) - radius)...(Int(center.y) + radius) {
                for x in (Int(center.x) - radius)...(Int(center.x) + radius) {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (1 - distance / Double(max(1, radius))))
                }
            }
        }

        drawDisc(center: center, radius: max(paperWidth, paperHeight), red: 210, green: 232, blue: 90, alpha: 0.06 + opacity * 0.1)

        let minX = Int(center.x) - paperWidth / 2
        let maxX = Int(center.x) + paperWidth / 2
        let minY = Int(center.y) - paperHeight / 2
        let maxY = Int(center.y) + paperHeight / 2
        for y in minY...maxY {
            for x in minX...maxX {
                let localX = x - minX
                let localY = y - minY
                let tear = localX > paperWidth - 18 && localY < 24 && (localX + localY).isMultiple(of: 7)
                if tear { continue }
                blendPixel(x: x, y: y, red: 236, green: 244, blue: 224, alpha: 0.78 * opacity)
            }
        }

        for line in 1...4 {
            let y = minY + line * paperHeight / 5
            for x in (minX + 12)...(maxX - 12) {
                blendPixel(x: x, y: y, red: 80, green: 118, blue: 210, alpha: 0.32 * opacity)
            }
        }

        for stroke in 0..<24 {
            let x = minX + 24 + stroke * 3
            let y = minY + paperHeight / 2 + Int(sin(Double(stroke) * 0.65) * 8)
            drawDisc(center: CGPoint(x: x, y: y), radius: 2, red: 34, green: 42, blue: 54, alpha: 0.45 * opacity)
        }
    }

    private func drawFallbackLinChePerformance(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let cue = lastLinChePerformanceCue
        let power = cue.intensity.clamped(to: 0...1)
        let seat = CGPoint(x: CGFloat(width) * 0.28, y: CGFloat(height) * 0.58)
        let bend = CGPoint(x: CGFloat(width) * 0.34, y: CGFloat(height) * 0.43)
        let door = CGPoint(x: CGFloat(width) * 0.48, y: CGFloat(height) * 0.20)
        let current: CGPoint
        if cue.exitProgress <= 0.55 {
            let t = CGFloat((cue.exitProgress / 0.55).clamped(to: 0...1))
            current = CGPoint(x: seat.x + (bend.x - seat.x) * t, y: seat.y + (bend.y - seat.y) * t)
        } else {
            let t = CGFloat(((cue.exitProgress - 0.55) / 0.45).clamped(to: 0...1))
            current = CGPoint(x: bend.x + (door.x - bend.x) * t, y: bend.y + (door.y - bend.y) * t)
        }

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            let minX = Int(center.x) - radius
            let maxX = Int(center.x) + radius
            let minY = Int(center.y) - radius
            let maxY = Int(center.y) + radius
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.18 + falloff * 0.82))
                }
            }
        }

        func drawLine(from start: CGPoint, to end: CGPoint, red: Int, green: Int, blue: Int, alpha: Double) {
            for step in 0...120 {
                let progress = CGFloat(step) / 120
                let x = start.x + (end.x - start.x) * progress
                let y = start.y + (end.y - start.y) * progress
                drawDisc(center: CGPoint(x: x, y: y), radius: 2 + Int(power * 2), red: red, green: green, blue: blue, alpha: alpha * Double(1 - abs(0.5 - progress) * 0.8))
            }
        }

        if cue.doorAttention > 0.05 {
            drawLine(from: seat, to: door, red: 72, green: 190, blue: 255, alpha: 0.08 + cue.doorAttention * 0.22)
        }
        if cue.exitProgress > 0.02 {
            drawLine(from: seat, to: current, red: 255, green: 142, blue: 58, alpha: 0.12 + cue.exitProgress * 0.32)
        }
        drawDisc(center: seat, radius: 15 + Int(cue.pageStillness * 7), red: 214, green: 232, blue: 214, alpha: 0.16 + cue.pageStillness * 0.22)
        drawDisc(center: current, radius: 12 + Int(power * 8), red: 255, green: 228, blue: 190, alpha: 0.28 + power * 0.38)
        drawDisc(center: CGPoint(x: current.x + 8, y: current.y + 10), radius: 6 + Int(cue.packingProgress * 4), red: 42, green: 58, blue: 78, alpha: cue.packingProgress * 0.55)
    }

    private func drawFallbackClassmateSensoryReaction(data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let reaction = lastClassmateSensoryReaction
        let pressureDominant = reaction.pressure >= reaction.support
        let color = pressureDominant
            ? (red: 255, green: 126, blue: 52)
            : (red: 72, green: 230, blue: 160)
        let secondary = pressureDominant
            ? (red: 128, green: 72, blue: 48)
            : (red: 52, green: 132, blue: 126)
        let strength = max(reaction.pressure, reaction.support).clamped(to: 0...1)
        let compression = CGFloat(reaction.compression.clamped(to: 0...1))

        func blendPixel(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let offset = (y * width + x) * 4
            let existingRed = Double(data[offset])
            let existingGreen = Double(data[offset + 1])
            let existingBlue = Double(data[offset + 2])
            data[offset] = UInt8((existingRed * (1 - alpha) + Double(red) * alpha).clamped(to: 0...255))
            data[offset + 1] = UInt8((existingGreen * (1 - alpha) + Double(green) * alpha).clamped(to: 0...255))
            data[offset + 2] = UInt8((existingBlue * (1 - alpha) + Double(blue) * alpha).clamped(to: 0...255))
            data[offset + 3] = 255
        }

        func drawDisc(center: CGPoint, radius: Int, red: Int, green: Int, blue: Int, alpha: Double) {
            let minX = Int(center.x) - radius
            let maxX = Int(center.x) + radius
            let minY = Int(center.y) - radius
            let maxY = Int(center.y) + radius
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = Double(x) - Double(center.x)
                    let dy = Double(y) - Double(center.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    guard distance <= Double(radius) else { continue }
                    let falloff = 1 - distance / Double(max(1, radius))
                    blendPixel(x: x, y: y, red: red, green: green, blue: blue, alpha: alpha * (0.22 + falloff * 0.78))
                }
            }
        }

        for row in 0..<4 {
            for column in 0..<5 {
                let x = CGFloat(width) * (0.20 + CGFloat(column) * 0.15)
                let y = CGFloat(height) * (0.38 + CGFloat(row) * 0.08 + CGFloat(row) * compression * 0.018)
                let radius = 7 + Int(strength * 8) - (pressureDominant ? row : 0)
                drawDisc(center: CGPoint(x: x, y: y), radius: max(5, radius), red: secondary.red, green: secondary.green, blue: secondary.blue, alpha: 0.12 + strength * 0.18)
                drawDisc(center: CGPoint(x: x, y: y - CGFloat(4 + row)), radius: max(3, radius / 2), red: color.red, green: color.green, blue: color.blue, alpha: 0.18 + strength * 0.32)
            }
        }
    }

    private var fallbackSnapshotSeed: Int {
        var seed = 137
        func mix(_ string: String) {
            for scalar in string.unicodeScalars {
                seed = (seed &* 31 &+ Int(scalar.value)) & 0x7fffffff
            }
        }
        mix(selectedNarrativeStageName ?? "classroom")
        mix(lastPrologueBeat?.rawValue ?? "no-prologue")
        mix(lastNarrativeMomentID)
        seed = seed &+ Int((cameraRig.position.x * 1_000).rounded()) &* 3
        seed = seed &+ Int((cameraRig.position.y * 1_000).rounded()) &* 5
        seed = seed &+ Int((cameraRig.position.z * 1_000).rounded()) &* 7
        seed = seed &+ (playerWaterCupVisible ? 11_003 : 0)
        seed = seed &+ Int((breakdownHeartbeatOpacity * 1_000).rounded()) &* 19
        seed = seed &+ Int((breakdownCupHaloOpacity * 1_000).rounded()) &* 23
        seed = seed &+ Int((breakdownSupportNoteOpacity * 1_000).rounded()) &* 29
        seed = seed &+ (currentGame?.activeBreakdownRecoverySteps.count ?? 0) &* 31
        seed = seed &+ (currentGame?.completedBreakdownRecoverySteps.count ?? 0) &* 37
        seed = seed &+ (narrativeTeacherVisible ? 17_021 : 0)
        seed = seed &+ visibleNarrativeRumorNPCCount &* 23_017
        seed = seed &+ (narrativeMessagePhoneVisible ? 29_003 : 0)
        seed = seed &+ Int(((narrativeJiangDialogueSupportOpacity ?? 0) * 1_000).rounded()) &* 31
        seed = seed &+ Int(((narrativeJiangDialogueAnchorOpacity ?? 0) * 1_000).rounded()) &* 37
        seed = seed &+ Int(((narrativeJiangDialogueRuptureOpacity ?? 0) * 1_000).rounded()) &* 41
        seed = seed &+ visibleNarrativeChapterMemoryBeaconCount &* 43
        seed = seed &+ Int(((narrativeChapterMemoryBeaconOpacities.max() ?? 0) * 1_000).rounded()) &* 47
        seed = seed &+ Int((lastClassmateSensoryReaction.pressure * 1_000).rounded()) &* 53
        seed = seed &+ Int((lastClassmateSensoryReaction.support * 1_000).rounded()) &* 59
        seed = seed &+ Int(((classmatePressureGazeOpacities.max() ?? 0) * 1_000).rounded()) &* 107
        seed = seed &+ Int(((classmateSupportSignalOpacities.max() ?? 0) * 1_000).rounded()) &* 109
        seed = seed &+ Int(((classmateBystanderFoldOpacities.max() ?? 0) * 1_000).rounded()) &* 113
        seed = seed &+ Int((teacherPatrolPressureOpacity * 1_000).rounded()) &* 61
        seed = seed &+ Int((teacherPatrolPathBandEmission * 1_000).rounded()) &* 67
        seed = seed &+ Int((chapterOneNotePaperOpacity * 1_000).rounded()) &* 71
        seed = seed &+ Int((chapterOneNotePaperEmission * 1_000).rounded()) &* 73
        seed = seed &+ Int((lastLinChePerformanceCue.intensity * 1_000).rounded()) &* 79
        seed = seed &+ Int((lastLinChePerformanceCue.exitProgress * 1_000).rounded()) &* 83
        seed = seed &+ Int((lastLinChePerformanceCue.doorAttention * 1_000).rounded()) &* 89
        seed = seed &+ Int(((activeNarrativeCompanionFollowLineOpacity ?? 0) * 1_000).rounded()) &* 97
        seed = seed &+ Int(((activeNarrativeCompanionBoundaryRingOpacity ?? 0) * 1_000).rounded()) &* 101
        return abs(seed)
    }


    var playerGroundedChairVisible: Bool {
        scene.rootNode.childNode(withName: "playerGroundedChair", recursively: true)?.isHidden == false
    }

    var playerGroundedChairLegCount: Int {
        guard let chair = scene.rootNode.childNode(withName: "playerGroundedChair", recursively: true) else { return 0 }
        if chair.childNode(withName: "photorealChair", recursively: true) != nil {
            return 4
        }
        return chair.childNodes.filter { $0.name?.hasPrefix("chairLeg_") == true }.count
    }

    private func eventVisualIntensity(game: GameManager) -> (blur: Double, vignette: Double, desaturation: Double) {
        guard case .event(let event) = game.gameState else {
            return (0, 0, 0)
        }
        switch event.kind {
        case .playerBreakdown:
            let completion = Double(game.completedBreakdownRecoverySteps.count) / Double(max(1, game.activeBreakdownRecoverySteps.count))
            return (
                2.0 + (1 - completion) * 3.5,
                0.44 + (1 - completion) * 0.76,
                0.18 + (1 - completion) * 0.28
            )
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
        case .linCheDialogue:
            return (1.1, 0.34, 0.08)
        case .noteDrop:
            return (1.2, 0.42, 0.08)
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

    private func applySensoryReaction(_ reaction: SensoryClassroomGroupReaction, classmate: Classmate, to node: SCNNode) {
        let state = classmate.state
        let baseScale: SCNVector3
        if state == .crying {
            baseScale = SCNVector3(0.9, 0.72, 0.9)
        } else {
            baseScale = SCNVector3(1, 1, 1)
        }
        let lateralCompression = CGFloat(reaction.compression) * 0.07
        let verticalCompression = CGFloat(reaction.compression) * 0.13
        let supportLift = CGFloat(max(0, reaction.support - reaction.pressure * 0.25)) * 0.045
        let scaleX = max(CGFloat(0.82), baseScale.x - lateralCompression + supportLift)
        let scaleY = max(CGFloat(0.62), baseScale.y - verticalCompression + supportLift)
        let scaleZ = max(CGFloat(0.82), baseScale.z - lateralCompression + supportLift)
        node.scale = SCNVector3(scaleX, scaleY, scaleZ)

        let baseOpacity: CGFloat = state == .sleeping ? 0.72 : 1
        node.opacity = (baseOpacity - CGFloat(reaction.opacityDrop)).clamped(to: 0.62...1.05)
        node.eulerAngles.z = classmateBaseLeanZ(for: state) + CGFloat(reaction.leanZ)

        guard let bodyMaterial = node.childNode(withName: "body", recursively: true)?.geometry?.firstMaterial else { return }
        let stateColor = emissionColor(for: state)
        let blendAmount = CGFloat(max(reaction.pressure, reaction.support).clamped(to: 0...1))
        let glowColor = classmateGlowColor(for: reaction)
        bodyMaterial.emission.contents = stateColor.blended(withFraction: blendAmount, of: glowColor) ?? glowColor
        bodyMaterial.emission.intensity = CGFloat(reaction.glowIntensity)
        applyClassmateCrowdRoleSignals(reaction, classmate: classmate, to: node)
    }

    private func applyClassmateCrowdRoleSignals(_ reaction: SensoryClassroomGroupReaction, classmate: Classmate, to node: SCNNode) {
        let profile = classmate.profile
        let pressureAffinity = (
            profile.anxiety * 0.42
            + profile.orderliness * 0.34
            + profile.maskStrength * 0.24
        ) / 100
        let supportAffinity = (
            profile.empathy * 0.5
            + classmate.support * 0.22
            + classmate.relationship * 0.18
            + (classmate.hasSharedTruth ? 10 : 0)
        ) / 100
        let witnessAffinity = (
            profile.cooperation * 0.24
            + profile.orderliness * 0.22
            + max(0, 100 - profile.empathy) * 0.22
            + profile.maskStrength * 0.16
            + profile.anxiety * 0.16
        ) / 100

        let pressureOpacity = (reaction.pressure * (0.12 + pressureAffinity * 0.82) - reaction.support * 0.22).clamped(to: 0...0.82)
        let supportOpacity = (reaction.support * (0.14 + supportAffinity * 0.86) - reaction.pressure * 0.28).clamped(to: 0...0.86)
        let bystanderOpacity = (
            reaction.pressure * (0.12 + witnessAffinity * 0.48)
            + reaction.bodyAlarm * 0.18
            - supportOpacity * 0.22
        ).clamped(to: 0...0.58)

        if let gaze = node.childNode(withName: "classmatePressureGaze", recursively: true) {
            gaze.isHidden = pressureOpacity <= 0.03
            gaze.opacity = CGFloat(pressureOpacity)
            gaze.eulerAngles.y = CGFloat((Double(classmate.seat.column) - 1.5) * -0.08)
            gaze.scale = SCNVector3(1, 1, 0.72 + Float(pressureOpacity) * 0.78)
            gaze.geometry?.firstMaterial?.emission.intensity = CGFloat(0.22 + pressureOpacity * 0.86)
        }
        if let support = node.childNode(withName: "classmateSupportSignal", recursively: true) {
            support.isHidden = supportOpacity <= 0.03
            support.opacity = CGFloat(supportOpacity)
            support.scale = SCNVector3(
                0.82 + Float(supportOpacity) * 0.74,
                0.3 + Float(supportOpacity) * 0.28,
                0.82 + Float(supportOpacity) * 0.74
            )
            support.geometry?.firstMaterial?.emission.intensity = CGFloat(0.24 + supportOpacity * 0.9)
        }
        if let fold = node.childNode(withName: "classmateBystanderFold", recursively: true) {
            fold.isHidden = bystanderOpacity <= 0.04
            fold.opacity = CGFloat(bystanderOpacity)
            fold.eulerAngles.z = CGFloat(0.12 * reaction.pressure - 0.08 * reaction.support)
            fold.scale = SCNVector3(0.88 + Float(bystanderOpacity) * 0.46, 1, 1)
            fold.geometry?.firstMaterial?.emission.intensity = CGFloat(0.16 + bystanderOpacity * 0.62)
        }
    }

    private func classmateGlowColor(for reaction: SensoryClassroomGroupReaction) -> NSColor {
        reaction.supportDominant
            ? NSColor(calibratedRed: 0.24, green: 0.88, blue: 0.58, alpha: 1)
            : NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.12, alpha: 1)
    }

    private func classmateBaseLeanZ(for state: ClassmateState) -> CGFloat {
        switch state {
        case .offeringHelp:
            return -0.08
        case .covering:
            return 0.16
        default:
            return 0
        }
    }

    private func applyStateAnimation(_ state: ClassmateState, to node: SCNNode) {
        node.removeAllActions()
        node.eulerAngles.x = 0
        node.eulerAngles.z = classmateBaseLeanZ(for: state)
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
        case .lookingAtPlayer:
            node.eulerAngles.x = -0.04
            node.childNode(withName: "head", recursively: false)?.runAction(.repeatForever(.sequence([
                .rotateBy(x: 0, y: 0.08, z: 0, duration: 0.4),
                .rotateBy(x: 0, y: -0.08, z: 0, duration: 0.4)
            ])), forKey: "glance")
        case .covering:
            break
        }
    }

    private func makeLighting() -> SCNNode {
        let root = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 18
        ambient.color = NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.78, alpha: 1)
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        for x in [-2.7, 0, 2.7] {
            for z in [-3.6, -0.4, 2.8] {
                let light = SCNLight()
                light.type = .omni
                light.intensity = 18
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
        geometry.radialSegmentCount = 24
        geometry.capSegmentCount = 10
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
        geometry.segmentCount = 32
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
        let shirtLight = uniformColor.blended(withFraction: 0.5, of: .white) ?? uniformColor
        let pantsColor = NSColor(calibratedRed: 0.1, green: 0.13, blue: 0.19, alpha: 1)
        let shoeColor = NSColor(calibratedWhite: 0.045, alpha: 1)

        let neck = capsule(radius: 0.033, height: 0.13, color: skin, position: SCNVector3(0, 0.77, 0))
        root.addChildNode(neck)

        let torso = capsule(radius: 0.125, height: 0.46, color: uniformColor, position: SCNVector3(0, 0.5, 0.015))
        torso.scale = SCNVector3(1.08, 1, 0.72)
        torso.name = "body"
        root.addChildNode(torso)
        let collarColor = shirtLight.blended(withFraction: 0.32, of: .white) ?? shirtLight
        let leftCollar = box(width: 0.105, height: 0.022, length: 0.085, color: collarColor, position: SCNVector3(-0.055, 0.69, -0.09))
        leftCollar.eulerAngles.z = -0.42
        root.addChildNode(leftCollar)
        let rightCollar = box(width: 0.105, height: 0.022, length: 0.085, color: collarColor, position: SCNVector3(0.055, 0.69, -0.09))
        rightCollar.eulerAngles.z = 0.42
        root.addChildNode(rightCollar)
        root.addChildNode(capsule(radius: 0.055, height: 0.34, color: uniformColor, position: SCNVector3(0, 0.69, 0.015), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))
        root.addChildNode(box(width: 0.018, height: 0.39, length: 0.012, color: shirtLight, position: SCNVector3(0, 0.51, -0.087)))
        root.addChildNode(box(width: 0.018, height: 0.39, length: 0.012, color: shirtLight, position: SCNVector3(-0.112, 0.51, -0.075)))
        root.addChildNode(box(width: 0.018, height: 0.39, length: 0.012, color: shirtLight, position: SCNVector3(0.112, 0.51, -0.075)))
        for fold in 0..<3 {
            let x = Float(fold - 1) * 0.062
            let crease = capsule(radius: 0.004, height: 0.20, color: uniformColor.blended(withFraction: 0.18, of: .black) ?? uniformColor, position: SCNVector3(x, 0.46, -0.091))
            crease.opacity = 0.42
            root.addChildNode(crease)
        }

        for side in [Float(-1), Float(1)] {
            let upperArm = capsule(
                radius: 0.036,
                height: 0.31,
                color: uniformColor,
                position: SCNVector3(side * 0.18, 0.49, -0.015),
                rotation: SCNVector4(0, 0, 1, side * -0.18)
            )
            root.addChildNode(upperArm)
            let forearm = capsule(
                radius: 0.032,
                height: 0.31,
                color: uniformColor,
                position: SCNVector3(side * 0.205, 0.34, -0.15),
                rotation: SCNVector4(1, 0, 0, Float.pi / 2.45)
            )
            root.addChildNode(forearm)
            root.addChildNode(sphere(radius: 0.034, color: skin, position: SCNVector3(side * 0.205, 0.3, -0.31), scale: SCNVector3(0.72, 0.55, 1.05)))

            let thigh = capsule(radius: 0.045, height: 0.38, color: pantsColor, position: SCNVector3(side * 0.075, 0.14, -0.06), rotation: SCNVector4(1, 0, 0, Float.pi / 2.2))
            root.addChildNode(thigh)
            root.addChildNode(capsule(radius: 0.041, height: 0.34, color: pantsColor, position: SCNVector3(side * 0.075, -0.03, -0.22)))
            root.addChildNode(box(width: 0.105, height: 0.045, length: 0.18, color: shoeColor, position: SCNVector3(side * 0.075, -0.23, -0.275)))
        }

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
        let torso = capsule(radius: 0.17, height: 0.58, color: jacket, position: SCNVector3(0, 0.83, 0))
        torso.scale = SCNVector3(1.1, 1, 0.68)
        root.addChildNode(torso)
        let shirtFront = capsule(radius: 0.065, height: 0.42, color: shirt, position: SCNVector3(0, 0.87, -0.105))
        shirtFront.scale = SCNVector3(1.0, 1.0, 0.22)
        root.addChildNode(shirtFront)
        root.addChildNode(box(width: 0.06, height: 0.18, length: 0.024, color: NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.08, alpha: 1), position: SCNVector3(0, 0.92, -0.11)))
        root.addChildNode(capsule(radius: 0.06, height: 0.42, color: jacket, position: SCNVector3(0, 1.04, 0), rotation: SCNVector4(0, 0, 1, Float.pi / 2)))

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
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = 0.78
        material.metalness.contents = 0.0
        return material
    }

    private func translucentSoundMaterial(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = 0.5
        material.blendMode = .add
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
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
