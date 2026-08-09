import AppKit
import AudioToolbox
import AVFoundation
import SceneKit

struct AudioSceneMix: Equatable {
    let sceneID: String
    let ambientNoise: Float
    let fanAmount: Float
    let outsideAmount: Float
    let mirrorResonance: Float
    let reverbLevel: Float

    static let classroom = AudioSceneMix(
        sceneID: "classroom",
        ambientNoise: 0.08,
        fanAmount: 0.22,
        outsideAmount: 0.08,
        mirrorResonance: 0,
        reverbLevel: -18
    )

    static func profile(for sceneID: String) -> AudioSceneMix {
        switch sceneID {
        case "classroom":
            return .classroom
        case "corridor", "noteTrace":
            return AudioSceneMix(sceneID: "corridor", ambientNoise: 0.035, fanAmount: 0.04, outsideAmount: 0.16, mirrorResonance: 0.12, reverbLevel: -12)
        case "mirror":
            return AudioSceneMix(sceneID: "mirror", ambientNoise: 0.025, fanAmount: 0.02, outsideAmount: 0.06, mirrorResonance: 1.0, reverbLevel: -6)
        case "stairwell":
            return AudioSceneMix(sceneID: "stairwell", ambientNoise: 0.028, fanAmount: 0, outsideAmount: 0.22, mirrorResonance: 0.26, reverbLevel: -9)
        case "counseling":
            return AudioSceneMix(sceneID: "counseling", ambientNoise: 0.045, fanAmount: 0.08, outsideAmount: 0.045, mirrorResonance: 0, reverbLevel: -20)
        case "epilogue":
            return AudioSceneMix(sceneID: "epilogue", ambientNoise: 0.055, fanAmount: 0.05, outsideAmount: 0.1, mirrorResonance: 0.08, reverbLevel: -16)
        default:
            return .classroom
        }
    }
}

struct NarrativeAudioDynamics: Equatable {
    let riskPulse: Float
    let supportWarmth: Float
    let privacyDamping: Float
    let ruptureTension: Float
    let choiceImpactPulse: Float

    static let neutral = NarrativeAudioDynamics(
        riskPulse: 0,
        supportWarmth: 0,
        privacyDamping: 0,
        ruptureTension: 0,
        choiceImpactPulse: 0
    )

    static func derive(from campaign: NarrativeCampaign) -> NarrativeAudioDynamics {
        guard campaign.isActive else { return .neutral }
        let world = campaign.worldDirectorSignal
        let risk = Float(max(world.ambientTension, world.safetyResponse * 0.7).clamped(to: 0...1))
        let support = Float(max(world.supportPresence, campaign.jiangDialoguePerformanceSupport * 0.8).clamped(to: 0...1))
        let privacy = Float(world.privacyBoundary.clamped(to: 0...1))
        let rupture = Float(campaign.jiangDialoguePerformanceRupture.clamped(to: 0...1))
        let choiceImpact = Float(choiceImpactPulse(for: campaign.activeChoiceImpact).clamped(to: 0...1))
        return NarrativeAudioDynamics(
            riskPulse: risk,
            supportWarmth: support,
            privacyDamping: privacy,
            ruptureTension: rupture,
            choiceImpactPulse: choiceImpact
        )
    }

    private static func choiceImpactPulse(for impact: NarrativeChoiceImpact?) -> Double {
        guard let impact else { return 0 }
        let signalIDs = Set(impact.signalIDs)
        if signalIDs.contains("risk") { return 0.9 }
        if signalIDs.contains("adult") || signalIDs.contains("safety") { return 0.74 }
        if signalIDs.contains("privacy") || signalIDs.contains("boundary") { return 0.58 }
        if signalIDs.contains("support") { return 0.48 }
        if signalIDs.contains("selfCare") { return 0.36 }
        return 0.42
    }
}

enum NarrativeImpactAudioTone: String, Equatable {
    case risk
    case support
    case privacy
    case safety
    case investigate
}

struct NarrativeImpactAudioEvent: Equatable {
    let id: String
    let tone: NarrativeImpactAudioTone
    let cueKind: AudioCueKind
    let intensity: Double
    let positionX: Float
    let positionY: Float
    let positionZ: Float

    var position: SCNVector3 {
        SCNVector3(positionX, positionY, positionZ)
    }
}

final class SpatialAudioManager {
    private let engine = AVAudioEngine()
    private let environment = SpatialAudioManager.makeEnvironmentNodeIfAvailable()
    private var source: AVAudioSourceNode?
    private var ambientSource: AVAudioSourceNode?
    private var spatialCueSources: [AVAudioSourceNode] = []
    private var spatialCuePlayers: [AVAudioPlayerNode] = []
    private var loopPlayers: [String: AVAudioPlayerNode] = [:]
    private var didConfigureEngine = false
    private var phase: Double = 0
    private var ambientPhase: Double = 0
    private var fanPhase: Double = 0
    private var amplitude: Float = 0
    private var targetAmplitude: Float = 0
    private var ambientNoise: Float = 0.05
    private var targetAmbientNoise: Float = 0.05
    private var fanAmount: Float = 0
    private var targetFanAmount: Float = 0
    private var outsideAmount: Float = 0.08
    private var targetOutsideAmount: Float = 0.08
    private var mirrorResonance: Float = 0
    private var targetMirrorResonance: Float = 0
    private var ambienceGain: Float = 0.7
    private var cueGain: Float = 0.7
    private(set) var activeSceneID = "classroom"
    private(set) var targetSceneMix = AudioSceneMix.classroom
    private(set) var effectiveTargetSceneMix = AudioSceneMix.classroom
    private(set) var targetNarrativeDynamics = NarrativeAudioDynamics.neutral
    private(set) var lastNarrativeImpactAudioEvent: NarrativeImpactAudioEvent?
    private let loopAssetNames = ["light_hum", "pen_scratch", "ceiling_fan", "outside_night"]
    private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aif", "aiff", "caf"]

    var assetStatus: AudioAssetStatus {
        let missingCues = AudioCueKind.allCases
            .filter { audioAssetURL(for: $0) == nil }
            .map { assetBaseName(for: $0) }
        let missingLoops = loopAssetNames.filter { audioLoopURL(named: $0) == nil }
        return AudioAssetStatus(
            cueAvailable: AudioCueKind.allCases.count - missingCues.count,
            cueTotal: AudioCueKind.allCases.count,
            loopAvailable: loopAssetNames.count - missingLoops.count,
            loopTotal: loopAssetNames.count,
            missingCues: missingCues,
            missingLoops: missingLoops
        )
    }

    var externalAudioDirectory: URL? {
        externalAudioRootURL()
    }

    func start() {
        guard !engine.isRunning else { return }

        if !didConfigureEngine {
            configureEngine()
            didConfigureEngine = true
        }
        if loopPlayers.isEmpty {
            startAmbientLoops()
        }

        do {
            try engine.start()
        } catch {
            NSSound.beep()
        }
    }

    func setVolumes(dialogue: Double, ambience: Double, cues: Double) {
        // Spoken dialogue is not recorded yet; keep its independent preference at
        // the GameManager boundary so future voice assets do not require a migration.
        _ = dialogue
        ambienceGain = Float(ambience.clamped(to: 0...1))
        cueGain = Float(cues.clamped(to: 0...1))
        updateAmbientLoopVolumes(classroomNoise: Double(targetAmbientNoise))
    }

    func setMixVolumes(dialogue: Double, ambience: Double, cues: Double) {
        setVolumes(dialogue: dialogue, ambience: ambience, cues: cues)
    }

    private func configureEngine() {
        if let environment {
            engine.attach(environment)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0.8, z: 1.5)
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
            environment.reverbParameters.enable = true
            environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
            environment.reverbParameters.level = -18
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.amplitude += (self.targetAmplitude - self.amplitude) * 0.003
            for frame in 0..<Int(frameCount) {
                self.phase += 2.0 * .pi * 1.8 / 44_100.0
                let beat = sin(self.phase)
                let tick = beat > 0.94 ? self.amplitude : 0
                for buffer in abl {
                    let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                    pointer[frame] = tick * self.cueGain
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        let ambient = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.ambientNoise += (self.targetAmbientNoise - self.ambientNoise) * 0.0015
            self.fanAmount += (self.targetFanAmount - self.fanAmount) * 0.001
            self.outsideAmount += (self.targetOutsideAmount - self.outsideAmount) * 0.001
            self.mirrorResonance += (self.targetMirrorResonance - self.mirrorResonance) * 0.0012

            for frame in 0..<Int(frameCount) {
                self.ambientPhase += 2.0 * .pi / 44_100.0
                self.fanPhase += 2.0 * .pi * 58 / 44_100.0
                let lightHum = Float(sin(self.ambientPhase * 132)) * 0.018
                let penScratch = Float.random(in: -1...1) * self.ambientNoise * 0.055
                let fan = (Float(sin(self.fanPhase)) * 0.028 + Float(sin(self.fanPhase * 0.47)) * 0.018) * self.fanAmount
                let outside = (Float(sin(self.ambientPhase * 9.0)) * 0.012 + Float.random(in: -1...1) * 0.01) * self.outsideAmount
                let mirror = Float(sin(self.ambientPhase * 120.0)) * 0.038 * self.mirrorResonance
                    + Float(sin(self.ambientPhase * 37.0)) * 0.016 * self.mirrorResonance
                let sample = lightHum + penScratch + fan + outside + mirror
                for buffer in abl {
                    let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                    pointer[frame] = sample * self.ambienceGain
                }
            }
            return noErr
        }
        ambientSource = ambient
        engine.attach(ambient)
        engine.connect(ambient, to: engine.mainMixerNode, format: format)
    }

    func updateStress(energy: Double, stress: Double, teacherNear: Bool, support: Double, classroomNoise: Double) {
        let supportBuffer = support / 360
        let intensity = max(0, min(1, (100 - energy) / 100 + stress / 180 + classroomNoise * 0.22 + (teacherNear ? 0.18 : 0) - supportBuffer))
        targetAmplitude = Float(intensity * 0.08)
        environment?.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: teacherNear ? 25 : 0, pitch: 0, roll: 0)
    }

    func updateAmbient(classroomNoise: Double, period: StudyPeriod, lightLevel: Double, elapsedMinutes: Int) {
        guard activeSceneID == "classroom" else { return }
        let breakNoise = period.isBreak ? 0.16 : 0
        let lateFatigue = period == .third ? 0.12 : 0
        targetAmbientNoise = Float((0.04 + classroomNoise * 0.18 + breakNoise + lateFatigue).clamped(to: 0.02...0.34))
        targetFanAmount = Float(period == .third ? 1.0 : (lightLevel < 0.6 ? 0.45 : 0.18))
        targetOutsideAmount = Float(elapsedMinutes >= 90 ? 0.18 : 0.08)
        updateAmbientLoopVolumes(classroomNoise: classroomNoise)
    }

    func transitionScene(to sceneID: String, duration: TimeInterval = 1.8) {
        let mix = AudioSceneMix.profile(for: sceneID)
        activeSceneID = mix.sceneID
        targetSceneMix = mix
        applyEffectiveSceneMix()
        _ = duration
    }

    func updateNarrativeDynamics(_ dynamics: NarrativeAudioDynamics) {
        targetNarrativeDynamics = dynamics
        applyEffectiveSceneMix()
    }

    func playNarrativeImpact(_ impact: NarrativeChoiceImpact, chapter: NarrativeChapter) {
        let event = makeNarrativeImpactAudioEvent(for: impact, chapter: chapter)
        lastNarrativeImpactAudioEvent = event
        playCue(kind: event.cueKind, intensity: event.intensity, position: event.position)
    }

    private func applyEffectiveSceneMix() {
        let mix = makeEffectiveMix(base: targetSceneMix, dynamics: targetNarrativeDynamics)
        effectiveTargetSceneMix = mix
        targetAmbientNoise = mix.ambientNoise
        targetFanAmount = mix.fanAmount
        targetOutsideAmount = mix.outsideAmount
        targetMirrorResonance = mix.mirrorResonance
        environment?.reverbParameters.level = mix.reverbLevel
        targetAmplitude = max(
            targetAmplitude,
            targetNarrativeDynamics.riskPulse * 0.05
                + targetNarrativeDynamics.ruptureTension * 0.04
                + targetNarrativeDynamics.choiceImpactPulse * 0.035
        )
        updateAmbientLoopVolumes(classroomNoise: Double(mix.ambientNoise))
    }

    private func makeEffectiveMix(base: AudioSceneMix, dynamics: NarrativeAudioDynamics) -> AudioSceneMix {
        let ambient = (base.ambientNoise
            + dynamics.riskPulse * 0.052
            + dynamics.ruptureTension * 0.034
            + dynamics.choiceImpactPulse * 0.026
            - dynamics.privacyDamping * 0.026).clamped(to: 0.015...0.34)
        let fan = (base.fanAmount
            + dynamics.riskPulse * 0.09
            - dynamics.supportWarmth * 0.035).clamped(to: 0...1)
        let outside = (base.outsideAmount
            + dynamics.supportWarmth * 0.05
            - dynamics.privacyDamping * 0.035).clamped(to: 0...0.32)
        let mirror = (base.mirrorResonance
            + dynamics.riskPulse * 0.14
            + dynamics.ruptureTension * 0.12
            + dynamics.choiceImpactPulse * 0.08
            - dynamics.supportWarmth * 0.04).clamped(to: 0...1)
        let reverb = (base.reverbLevel
            + dynamics.riskPulse * 4.0
            + dynamics.ruptureTension * 2.4
            + dynamics.choiceImpactPulse * 1.8
            - dynamics.privacyDamping * 4.2
            - dynamics.supportWarmth * 1.4).clamped(to: -28 ... -4)
        return AudioSceneMix(
            sceneID: base.sceneID,
            ambientNoise: ambient,
            fanAmount: fan,
            outsideAmount: outside,
            mirrorResonance: mirror,
            reverbLevel: reverb
        )
    }

    private func makeNarrativeImpactAudioEvent(for impact: NarrativeChoiceImpact, chapter: NarrativeChapter) -> NarrativeImpactAudioEvent {
        let tone = narrativeImpactTone(for: impact)
        let cueKind: AudioCueKind
        let intensity: Double
        var position = narrativeImpactBasePosition(for: chapter)

        switch tone {
        case .risk:
            cueKind = .heartbeat
            intensity = 0.86
            position.x = 0
            position.z = -0.25
        case .safety:
            cueKind = .phone
            intensity = 0.7
            position.x += 1.15
            position.z -= 0.45
        case .privacy:
            cueKind = .paper
            intensity = 0.56
            position.x -= 0.9
            position.z -= 0.2
        case .support:
            cueKind = .whisper
            intensity = 0.48
            position.x -= 0.7
            position.z += 0.35
        case .investigate:
            cueKind = .paper
            intensity = 0.5
            position.x += 0.45
            position.z -= 0.65
        }

        return NarrativeImpactAudioEvent(
            id: impact.id,
            tone: tone,
            cueKind: cueKind,
            intensity: intensity,
            positionX: Float(position.x),
            positionY: Float(position.y),
            positionZ: Float(position.z)
        )
    }

    private func narrativeImpactTone(for impact: NarrativeChoiceImpact) -> NarrativeImpactAudioTone {
        let signalIDs = Set(impact.signalIDs)
        if signalIDs.contains("risk") { return .risk }
        if signalIDs.contains("adult") || signalIDs.contains("safety") { return .safety }
        if signalIDs.contains("privacy") || signalIDs.contains("boundary") { return .privacy }
        if signalIDs.contains("support") || signalIDs.contains("selfCare") { return .support }
        return .investigate
    }

    private func narrativeImpactBasePosition(for chapter: NarrativeChapter) -> SCNVector3 {
        switch chapter {
        case .classroom:
            return SCNVector3(-1.1, 0.9, 1.25)
        case .mirror:
            return SCNVector3(0, 0.95, -1.7)
        case .noteTrace:
            return SCNVector3(0.8, 0.9, -1.35)
        case .stairwell:
            return SCNVector3(0, 1.05, -1.55)
        case .counseling:
            return SCNVector3(0, 0.85, -0.65)
        case .epilogue:
            return SCNVector3(0, 0.9, 0.2)
        }
    }

    func updateListener(position: SCNVector3, orientation: SCNVector3) {
        environment?.listenerPosition = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        environment?.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: Float(orientation.y * 180 / .pi),
            pitch: Float(orientation.x * 180 / .pi),
            roll: Float(orientation.z * 180 / .pi)
        )
    }

    func playWarning() {
        NSSound.beep()
        targetAmplitude = max(targetAmplitude, 0.12)
    }

    func playCue(kind: AudioCueKind, intensity: Double, position: SCNVector3) {
        guard engine.isRunning else { return }
        if playAssetCue(kind: kind, intensity: intensity, position: position) {
            return
        }

        let frequency = frequency(for: kind)
        let totalFrames = AVAudioFrameCount(44_100 * duration(for: kind))
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        var phase = 0.0
        var frameCursor: AVAudioFrameCount = 0
        let amplitude = Float(max(0.04, min(0.24, intensity * 0.2))) * cueGain

        let cue = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let progress = min(1, Double(frameCursor) / Double(max(1, totalFrames)))
                let envelope = Float(pow(max(0, 1 - progress), 1.8))
                phase += 2.0 * .pi * frequency / 44_100.0
                let tone = sin(phase)
                let texture = self.texture(kind: kind, phase: phase, frame: frameCursor)
                let sample = Float(tone) * texture * amplitude * envelope
                for buffer in abl {
                    let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                    pointer[frame] = sample
                }
                frameCursor += 1
            }
            return noErr
        }

        cue.position = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        cue.reverbBlend = kind == .heartbeat ? 0 : 0.35
        cue.sourceMode = kind == .heartbeat ? .bypass : .spatializeIfMono
        cue.pointSourceInHeadMode = kind == .heartbeat ? .mono : .bypass

        if spatialCueSources.count > 12 {
            let stale = spatialCueSources.removeFirst()
            stale.reset()
            engine.detach(stale)
        }
        spatialCueSources.append(cue)
        engine.attach(cue)
        engine.connect(cue, to: outputNode(for: kind), format: format)

        if (kind == .crying || kind == .lights) && cueGain > 0.02 {
            NSSound.beep()
        }
    }

    func stop() {
        engine.stop()
        targetAmplitude = 0
        targetAmbientNoise = 0
        targetFanAmount = 0
        targetOutsideAmount = 0
        targetMirrorResonance = 0
        mirrorResonance = 0
        loopPlayers.values.forEach {
            $0.stop()
            engine.detach($0)
        }
        loopPlayers.removeAll()
        spatialCueSources.forEach {
            $0.reset()
            engine.detach($0)
        }
        spatialCuePlayers.forEach {
            $0.stop()
            engine.detach($0)
        }
        spatialCueSources.removeAll()
        spatialCuePlayers.removeAll()
    }

    private func startAmbientLoops() {
        for name in loopAssetNames {
            guard let url = audioLoopURL(named: name),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                continue
            }
            try? file.read(into: buffer)
            let player = AVAudioPlayerNode()
            player.volume = 0
            loopPlayers[name] = player
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        }
    }

    private func updateAmbientLoopVolumes(classroomNoise: Double) {
        loopPlayers["light_hum"]?.volume = 0.16 * ambienceGain
        loopPlayers["pen_scratch"]?.volume = Float((0.08 + classroomNoise * 0.28).clamped(to: 0.04...0.36)) * ambienceGain
        loopPlayers["ceiling_fan"]?.volume = targetFanAmount * 0.22 * ambienceGain
        loopPlayers["outside_night"]?.volume = targetOutsideAmount * 0.24 * ambienceGain
    }

    private func audioLoopURL(named name: String) -> URL? {
        audioURL(named: name, subdirectory: "AudioLoops")
    }

    private func playAssetCue(kind: AudioCueKind, intensity: Double, position: SCNVector3) -> Bool {
        guard let url = audioAssetURL(for: kind), let file = try? AVAudioFile(forReading: url) else {
            return false
        }

        let player = AVAudioPlayerNode()
        player.position = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        player.reverbBlend = kind == .heartbeat ? 0 : 0.32
        player.sourceMode = kind == .heartbeat ? .bypass : .spatializeIfMono
        player.pointSourceInHeadMode = kind == .heartbeat ? .mono : .bypass
        player.volume = Float(max(0.06, min(1.0, intensity))) * cueGain

        if spatialCuePlayers.count > 10 {
            let stale = spatialCuePlayers.removeFirst()
            stale.stop()
            engine.detach(stale)
        }

        spatialCuePlayers.append(player)
        engine.attach(player)
        engine.connect(player, to: outputNode(for: kind), format: file.processingFormat)
        player.scheduleFile(file, at: nil)
        player.play()
        return true
    }

    private func outputNode(for kind: AudioCueKind) -> AVAudioNode {
        if kind == .heartbeat || environment == nil {
            return engine.mainMixerNode
        }
        return environment!
    }

    private static func makeEnvironmentNodeIfAvailable() -> AVAudioEnvironmentNode? {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_SpatialMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard AudioComponentFindNext(nil, &description) != nil else {
            return nil
        }
        return AVAudioEnvironmentNode()
    }

    private func audioAssetURL(for kind: AudioCueKind) -> URL? {
        audioURL(named: assetBaseName(for: kind), subdirectory: "AudioCues")
    }

    private func audioURL(named baseName: String, subdirectory: String) -> URL? {
        for ext in supportedAudioExtensions {
            if let url = externalAudioURL(named: baseName, extension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = Bundle.module.url(forResource: baseName, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }

    private func externalAudioURL(named baseName: String, extension ext: String, subdirectory: String) -> URL? {
        guard let root = externalAudioRootURL() else { return nil }
        let directory = root.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func externalAudioRootURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LateStudySimulator", isDirectory: true)
    }

    private func assetBaseName(for kind: AudioCueKind) -> String {
        switch kind {
        case .teacherCough: return "teacher_cough"
        case .teacherSigh: return "teacher_sigh"
        default: return String(describing: kind)
        }
    }

    private func frequency(for kind: AudioCueKind) -> Double {
        switch kind {
        case .footstep: return 140
        case .paper: return 1_900
        case .phone: return 880
        case .whisper: return 420
        case .chair: return 220
        case .crying: return 520
        case .lights: return 1_300
        case .heartbeat: return 90
        case .broadcast: return 740
        case .bell: return 660
        case .knock: return 180
        case .stomach: return 82
        case .wrapper: return 2_200
        case .teacherCough: return 180
        case .teacherSigh: return 260
        }
    }

    private func duration(for kind: AudioCueKind) -> Double {
        switch kind {
        case .footstep, .chair: return 0.24
        case .paper, .phone: return 0.32
        case .whisper, .crying: return 0.55
        case .lights: return 0.72
        case .heartbeat: return 0.38
        case .broadcast: return 0.9
        case .bell: return 1.2
        case .knock: return 0.42
        case .stomach: return 0.5
        case .wrapper: return 0.36
        case .teacherCough: return 0.48
        case .teacherSigh: return 0.82
        }
    }

    private func texture(kind: AudioCueKind, phase: Double, frame: AVAudioFrameCount) -> Float {
        switch kind {
        case .paper:
            return Float.random(in: -1...1) * 0.65 + Float(sin(phase * 2.7)) * 0.35
        case .footstep, .chair:
            return frame % 2 == 0 ? 1 : -0.7
        case .phone:
            return sin(phase * 0.18) > 0 ? 1 : 0.35
        case .whisper, .crying:
            return Float.random(in: -0.7...0.7) * 0.5 + 0.5
        case .lights:
            return Float(sin(phase * 3.1)) * 0.6 + Float.random(in: -0.25...0.25)
        case .heartbeat:
            return sin(phase) > 0.82 ? 1 : 0
        case .broadcast:
            return Float(sin(phase * 0.08)) * 0.55 + Float.random(in: -0.12...0.12) + 0.45
        case .bell:
            return Float(0.72 + sin(phase * 0.012) * 0.2 + sin(phase * 0.004) * 0.08)
        case .knock:
            return frame % 8 < 3 ? 1.0 : -0.35
        case .stomach:
            return Float(sin(phase * 0.17)) * 0.65 + Float(sin(phase * 0.05)) * 0.35
        case .wrapper:
            return Float.random(in: -1...1) * 0.85 + Float(sin(phase * 4.3)) * 0.15
        case .teacherCough:
            return frame % 5 < 3 ? Float.random(in: -0.8...0.8) + 0.4 : Float(sin(phase * 0.12)) * 0.35
        case .teacherSigh:
            return Float(sin(phase * 0.06)) * 0.45 + Float.random(in: -0.22...0.22) + 0.28
        }
    }
}
