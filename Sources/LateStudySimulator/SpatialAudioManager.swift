import AppKit
import AVFoundation
import SceneKit

final class SpatialAudioManager {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var source: AVAudioSourceNode?
    private var ambientSource: AVAudioSourceNode?
    private var spatialCueSources: [AVAudioSourceNode] = []
    private var spatialCuePlayers: [AVAudioPlayerNode] = []
    private var loopPlayers: [String: AVAudioPlayerNode] = [:]
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

        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0.8, z: 1.5)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = -18

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
                    pointer[frame] = tick
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

            for frame in 0..<Int(frameCount) {
                self.ambientPhase += 2.0 * .pi / 44_100.0
                self.fanPhase += 2.0 * .pi * 58 / 44_100.0
                let lightHum = Float(sin(self.ambientPhase * 132)) * 0.018
                let penScratch = Float.random(in: -1...1) * self.ambientNoise * 0.055
                let fan = (Float(sin(self.fanPhase)) * 0.028 + Float(sin(self.fanPhase * 0.47)) * 0.018) * self.fanAmount
                let outside = (Float(sin(self.ambientPhase * 9.0)) * 0.012 + Float.random(in: -1...1) * 0.01) * self.outsideAmount
                let sample = lightHum + penScratch + fan + outside
                for buffer in abl {
                    let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                    pointer[frame] = sample
                }
            }
            return noErr
        }
        ambientSource = ambient
        engine.attach(ambient)
        engine.connect(ambient, to: engine.mainMixerNode, format: format)
        startAmbientLoops()

        do {
            try engine.start()
        } catch {
            NSSound.beep()
        }
    }

    func updateStress(energy: Double, stress: Double, teacherNear: Bool, support: Double, classroomNoise: Double) {
        let supportBuffer = support / 360
        let intensity = max(0, min(1, (100 - energy) / 100 + stress / 180 + classroomNoise * 0.22 + (teacherNear ? 0.18 : 0) - supportBuffer))
        targetAmplitude = Float(intensity * 0.08)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: teacherNear ? 25 : 0, pitch: 0, roll: 0)
    }

    func updateAmbient(classroomNoise: Double, period: StudyPeriod, lightLevel: Double, elapsedMinutes: Int) {
        let breakNoise = period.isBreak ? 0.16 : 0
        let lateFatigue = period == .third ? 0.12 : 0
        targetAmbientNoise = Float((0.04 + classroomNoise * 0.18 + breakNoise + lateFatigue).clamped(to: 0.02...0.34))
        targetFanAmount = Float(period == .third ? 1.0 : (lightLevel < 0.6 ? 0.45 : 0.18))
        targetOutsideAmount = Float(elapsedMinutes >= 90 ? 0.18 : 0.08)
        updateAmbientLoopVolumes(classroomNoise: classroomNoise)
    }

    func updateListener(position: SCNVector3, orientation: SCNVector3) {
        environment.listenerPosition = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
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
        let amplitude = Float(max(0.04, min(0.24, intensity * 0.2)))

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
        engine.connect(cue, to: kind == .heartbeat ? engine.mainMixerNode : environment, format: format)

        if kind == .crying || kind == .lights {
            NSSound.beep()
        }
    }

    func stop() {
        engine.stop()
        targetAmplitude = 0
        targetAmbientNoise = 0
        targetFanAmount = 0
        targetOutsideAmount = 0
        loopPlayers.values.forEach { $0.stop() }
        loopPlayers.removeAll()
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
        loopPlayers["light_hum"]?.volume = 0.16
        loopPlayers["pen_scratch"]?.volume = Float((0.08 + classroomNoise * 0.28).clamped(to: 0.04...0.36))
        loopPlayers["ceiling_fan"]?.volume = targetFanAmount * 0.22
        loopPlayers["outside_night"]?.volume = targetOutsideAmount * 0.24
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
        player.volume = Float(max(0.06, min(1.0, intensity)))

        if spatialCuePlayers.count > 10 {
            let stale = spatialCuePlayers.removeFirst()
            stale.stop()
            engine.detach(stale)
        }

        spatialCuePlayers.append(player)
        engine.attach(player)
        engine.connect(player, to: kind == .heartbeat ? engine.mainMixerNode : environment, format: file.processingFormat)
        player.scheduleFile(file, at: nil)
        player.play()
        return true
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
