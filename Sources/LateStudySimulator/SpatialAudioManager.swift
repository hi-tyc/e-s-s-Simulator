import AppKit
import AudioToolbox
import AVFoundation
import SceneKit
import os

/// 程序化音频合成与空间化播放。
///
/// 线程模型：
/// - 所有外部 `func`（update*/play*/start/stop）都在主线程调用；
/// - `AVAudioSourceNode` 的渲染块在音频实时线程执行。
///
/// 两个线程共享的可变状态收进 `locked`（`OSAllocatedUnfairLock`）。
/// 渲染块只做「读目标值 + 平滑逼近」，不做系统调用、不做堆分配、不发 ObjC 消息。
final class SpatialAudioManager {
    private let engine = AVAudioEngine()
    private let environment = SpatialAudioManager.makeEnvironmentNodeIfAvailable()

    /// 音频线程与主线程共享的可变状态。
    private struct SharedState {
        var amplitude: Float = 0
        var targetAmplitude: Float = 0
        var ambientNoise: Float = 0.05
        var targetAmbientNoise: Float = 0.05
        var fanAmount: Float = 0
        var targetFanAmount: Float = 0
        var outsideAmount: Float = 0.08
        var targetOutsideAmount: Float = 0.08
    }

    private let locked = OSAllocatedUnfairLock(initialState: SharedState())

    private var source: AVAudioSourceNode?
    private var ambientSource: AVAudioSourceNode?
    private var spatialCueSources: [AVAudioSourceNode] = []
    private var spatialCuePlayers: [AVAudioPlayerNode] = []
    private var loopPlayers: [String: AVAudioPlayerNode] = [:]
    private var didConfigureEngine = false
    private var ambienceVolume: Float = 0.7
    private var cueVolume: Float = 0.7
    private(set) var dialogueVolume: Float = 0.7

    /// 缓存素材扫描结果，避免在视图求值路径上反复访问文件系统。
    private var cachedAssetStatus: AudioAssetStatus?
    private var resolvedSampleRate: Double = 44_100
    /// 当前硬件输出能力（多声道 / 立体声 / 单声道回退链）。
    private(set) var outputCapability: AudioOutputCapability = .stereo(sampleRate: 44_100)

    private let loopAssetNames = ["light_hum", "pen_scratch", "ceiling_fan", "outside_night"]
    private let supportedAudioExtensions = ["wav", "mp3", "m4a", "aif", "aiff", "caf"]

    private static let maxCueSources = 12
    private static let maxAssetPlayers = 10

    private enum Tuning {
        static let heartbeatBaselineHz: Double = 1.8
        static let heartbeatGate: Double = 0.94
        static let amplitudeSmoothing: Float = 0.003
        static let ambientSmoothing: Float = 0.0015
        static let fanSmoothing: Float = 0.001
        static let outsideSmoothing: Float = 0.001
        static let lightHumRate: Double = 132
        static let fanHz: Double = 58
        static let fanSecondaryRatio: Double = 0.47
        static let outsideRate: Double = 9.0
        static let maxCueAmplitude: Float = 0.24
        static let minCueAmplitude: Float = 0.01
        static let warningAmplitude: Float = 0.12
        static let safeOutputVolume: Float = 0.85
    }

    var assetStatus: AudioAssetStatus {
        if let cachedAssetStatus { return cachedAssetStatus }
        let status = computeAssetStatus()
        cachedAssetStatus = status
        return status
    }

    /// 外部音频目录内容变化后调用，使素材状态缓存失效。
    func invalidateAssetStatus() {
        cachedAssetStatus = nil
    }

    var externalAudioDirectory: URL? {
        externalAudioRootURL()
    }

    // MARK: - 生命周期

    func start() {
        guard !engine.isRunning else { return }

        if !didConfigureEngine {
            configureEngine()
            didConfigureEngine = true
        }
        if loopPlayers.isEmpty {
            startAmbientLoops()
            // 立即套用一次音量，避免以 volume 0 静默播放、难以排查。
            refreshAmbientLoopVolumes(classroomNoise: 0.25)
        }

        do {
            try engine.start()
        } catch {
            // 音频不可用不应影响游戏；静默降级。
            didConfigureEngine = false
        }
    }

    func stop() {
        engine.stop()
        engine.reset()
        locked.withLock { state in
            state.targetAmplitude = 0
            state.amplitude = 0
            state.targetAmbientNoise = 0
            state.ambientNoise = 0
            state.targetFanAmount = 0
            state.fanAmount = 0
            state.targetOutsideAmount = 0
            state.outsideAmount = 0
        }
        detachAllNodes()
    }

    private func detachAllNodes() {
        loopPlayers.values.forEach {
            $0.stop()
            engine.detach($0)
        }
        loopPlayers.removeAll()
        spatialCuePlayers.forEach {
            $0.stop()
            engine.detach($0)
        }
        spatialCuePlayers.removeAll()
        spatialCueSources.forEach { engine.detach($0) }
        spatialCueSources.removeAll()
        // 常驻的心跳/环境节点一并移除，下次 start() 会重新配置。
        if let source { engine.detach(source) }
        if let ambientSource { engine.detach(ambientSource) }
        source = nil
        ambientSource = nil
        didConfigureEngine = false
    }

    private func configureEngine() {
        // 探测硬件输出能力，决定输出声道数与空间化策略。
        // 优先级：多声道沉浸式 → 立体声 → 单声道。
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let capability = AudioOutputCapability.detect(from: hardwareFormat)
        outputCapability = capability
        resolvedSampleRate = capability.sampleRate

        // 主输出格式按能力配置（多声道时系统有机会上混为 Dolby Atmos）。
        if let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: capability.sampleRate,
            channels: AVAudioChannelCount(capability.outputChannelCount)
        ) {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
        }

        if let environment, capability.usesSpatialEnvironment {
            engine.attach(environment)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0.8, z: 1.5)
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
            environment.reverbParameters.enable = true
            environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
            environment.reverbParameters.level = -18
        }

        // 总输出留安全余量，防止多路叠加削波。
        engine.mainMixerNode.outputVolume = Tuning.safeOutputVolume

        guard let format = AVAudioFormat(standardFormatWithSampleRate: resolvedSampleRate, channels: 1) else {
            return
        }
        let sampleRate = resolvedSampleRate

        // 心跳：相位状态是渲染块私有（捕获在闭包内），无需加锁。
        var heartbeatPhase: Double = 0
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            guard let buffer = SpatialAudioManager.firstMutableBuffer(audioBufferList) else { return noErr }

            let amplitude = self.locked.withLock { state -> Float in
                state.amplitude += (state.targetAmplitude - state.amplitude) * Tuning.amplitudeSmoothing
                return state.amplitude
            }

            for frame in 0..<Int(frameCount) {
                heartbeatPhase += 2.0 * .pi * Tuning.heartbeatBaselineHz / sampleRate
                let beat = sin(heartbeatPhase)
                buffer[frame] = beat > Double(Tuning.heartbeatGate) ? amplitude : 0
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        // 环境底噪：同样使用闭包私有相位 + 无系统调用的 xorshift PRNG。
        var ambientPhase: Double = 0
        var fanPhase: Double = 0
        var noiseState: UInt32 = 0x9E3779B9
        let ambient = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            guard let buffer = SpatialAudioManager.firstMutableBuffer(audioBufferList) else { return noErr }

            let (noise, fanAmount, outsideAmount) = self.locked.withLock { state -> (Float, Float, Float) in
                state.ambientNoise += (state.targetAmbientNoise - state.ambientNoise) * Tuning.ambientSmoothing
                state.fanAmount += (state.targetFanAmount - state.fanAmount) * Tuning.fanSmoothing
                state.outsideAmount += (state.targetOutsideAmount - state.outsideAmount) * Tuning.outsideSmoothing
                return (state.ambientNoise, state.fanAmount, state.outsideAmount)
            }

            for frame in 0..<Int(frameCount) {
                ambientPhase += 2.0 * .pi / sampleRate
                fanPhase += 2.0 * .pi * Tuning.fanHz / sampleRate
                let lightHum = Float(sin(ambientPhase * Tuning.lightHumRate)) * 0.018
                let penScratch = SpatialAudioManager.xorshift(&noiseState) * noise * 0.055
                let fan = (Float(sin(fanPhase)) * 0.028
                    + Float(sin(fanPhase * Tuning.fanSecondaryRatio)) * 0.018) * fanAmount
                let outside = (Float(sin(ambientPhase * Tuning.outsideRate)) * 0.012
                    + SpatialAudioManager.xorshift(&noiseState) * 0.01) * outsideAmount
                buffer[frame] = lightHum + penScratch + fan + outside
            }
            return noErr
        }
        ambientSource = ambient
        engine.attach(ambient)
        engine.connect(ambient, to: engine.mainMixerNode, format: format)
    }

    /// 无系统调用的 xorshift PRNG，返回 -1...1。
    /// 音频渲染线程禁止使用 `SystemRandomNumberGenerator`（内部走 arc4random 系统调用）。
    @inline(__always)
    private static func xorshift(_ state: inout UInt32) -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }

    private static func firstMutableBuffer(_ audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> UnsafeMutablePointer<Float>? {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let first = abl.first, let data = first.mData else { return nil }
        return data.assumingMemoryBound(to: Float.self)
    }

    // MARK: - 运行时更新

    func updateStress(energy: Double, stress: Double, teacherNear: Bool, support: Double, classroomNoise: Double) {
        let supportBuffer = support / 360
        let intensity = max(0, min(1, (100 - energy) / 100 + stress / 180 + classroomNoise * 0.22 + (teacherNear ? 0.18 : 0) - supportBuffer))
        locked.withLock { state in
            state.targetAmplitude = SpatialAudioManager.clampedAmplitude(Float(intensity * 0.08))
        }
        environment?.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: teacherNear ? 25 : 0, pitch: 0, roll: 0)
    }

    func updateAmbient(classroomNoise: Double, period: StudyPeriod, lightLevel: Double, elapsedMinutes: Int) {
        let breakNoise = period.isBreak ? 0.16 : 0
        let lateFatigue = period == .third ? 0.12 : 0
        let ambient = SpatialAudioManager.clamp01(Float(0.04 + classroomNoise * 0.18 + breakNoise + lateFatigue))
        let fan = SpatialAudioManager.clamp01(Float(period == .third ? 1.0 : (lightLevel < 0.6 ? 0.45 : 0.18)))
        let outside = SpatialAudioManager.clamp01(Float(elapsedMinutes >= 90 ? 0.18 : 0.08))
        locked.withLock { state in
            state.targetAmbientNoise = ambient
            state.targetFanAmount = fan
            state.targetOutsideAmount = outside
        }
        refreshAmbientLoopVolumes(classroomNoise: classroomNoise)
    }

    func setMixVolumes(dialogue: Double, ambience: Double, cues: Double) {
        dialogueVolume = Float(dialogue.clamped(to: 0...1))
        ambienceVolume = Float(ambience.clamped(to: 0...1))
        cueVolume = Float(cues.clamped(to: 0...1))
        refreshAmbientLoopVolumes(classroomNoise: 0.25)
    }

    func updateListener(position: SCNVector3, orientation: SCNVector3) {
        environment?.listenerPosition = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        environment?.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: Float(orientation.y * 180 / .pi),
            pitch: Float(orientation.x * 180 / .pi),
            roll: Float(orientation.z * 180 / .pi)
        )
    }

    /// 预警脉冲。不再调用 `NSSound.beep()`：它绕过应用音量与无障碍设置，
    /// 且与引擎输出无法统一限幅。
    func playWarning() {
        locked.withLock { state in
            state.targetAmplitude = SpatialAudioManager.clampedAmplitude(max(state.targetAmplitude, Tuning.warningAmplitude))
        }
    }

    // MARK: - 播放

    func playCue(kind: AudioCueKind, intensity: Double, position: SCNVector3) {
        guard engine.isRunning else { return }
        let mixedIntensity = intensity * Double(cueVolume)
        if playAssetCue(kind: kind, intensity: mixedIntensity, position: position) {
            return
        }

        let frequency = frequency(for: kind)
        let totalFrames = AVAudioFrameCount(resolvedSampleRate * duration(for: kind))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: resolvedSampleRate, channels: 1) else { return }
        let sampleRate = resolvedSampleRate
        let amplitude = min(max(Float(mixedIntensity * 0.2), Tuning.minCueAmplitude), Tuning.maxCueAmplitude)

        // 相位与游标是渲染块私有状态，用闭包捕获即可，无需加锁或字典。
        var phase: Double = 0
        var frameCursor: AVAudioFrameCount = 0
        var noiseState: UInt32 = 0x85EBCA6B

        let cue = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            guard let buffer = SpatialAudioManager.firstMutableBuffer(audioBufferList) else { return noErr }
            for frame in 0..<Int(frameCount) {
                let progress = min(1, Double(frameCursor) / Double(max(1, totalFrames)))
                let envelope = Float(pow(max(0, 1 - progress), 1.8))
                phase += 2.0 * .pi * frequency / sampleRate
                let tone = sin(phase)
                let texture = self.texture(kind: kind, phase: phase, frame: frameCursor, noise: &noiseState)
                buffer[frame] = Float(tone) * texture * amplitude * envelope
                frameCursor += 1
            }
            return noErr
        }

        applySpatial(cue, kind: kind, position: position)

        // 超过上限时回收最旧节点。节点只 attach/connect 一次，
        // 不 detach 正在参与渲染的节点，避免音频线程竞态与爆音。
        if spatialCueSources.count >= Self.maxCueSources {
            let stale = spatialCueSources.removeFirst()
            engine.detach(stale)
        }
        spatialCueSources.append(cue)
        engine.attach(cue)
        engine.connect(cue, to: outputNode(for: kind), format: format)
    }

    private func applySpatial(_ node: some AVAudioMixing, kind: AudioCueKind, position: SCNVector3) {
        node.position = AVAudio3DPoint(x: Float(position.x), y: Float(position.y), z: Float(position.z))
        // 程序化 cue 与素材 cue 使用同一组空间参数，避免听感不一致。
        node.reverbBlend = kind == .heartbeat ? 0 : 0.35
        node.sourceMode = kind == .heartbeat ? .bypass : .spatializeIfMono
        node.pointSourceInHeadMode = kind == .heartbeat ? .mono : .bypass
    }

    private func startAmbientLoops() {
        for name in loopAssetNames {
            guard let url = audioLoopURL(named: name),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                continue
            }
            do {
                try file.read(into: buffer)
            } catch {
                continue
            }
            let player = AVAudioPlayerNode()
            player.volume = 0
            loopPlayers[name] = player
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: monoFormat(matching: file.processingFormat))
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        }
    }

    private func refreshAmbientLoopVolumes(classroomNoise: Double) {
        let safeAmbience = min(1, ambienceVolume)
        loopPlayers["light_hum"]?.volume = min(1, 0.16 * safeAmbience)
        let scratch = Float((0.08 + classroomNoise * 0.28).clamped(to: 0.04...0.36)) * safeAmbience
        loopPlayers["pen_scratch"]?.volume = min(1, scratch)
        let (fan, outside) = locked.withLock { ($0.targetFanAmount, $0.targetOutsideAmount) }
        loopPlayers["ceiling_fan"]?.volume = min(1, fan * 0.22 * safeAmbience)
        loopPlayers["outside_night"]?.volume = min(1, outside * 0.24 * safeAmbience)
    }

    private func audioLoopURL(named name: String) -> URL? {
        audioURL(named: name, subdirectory: "AudioLoops")
    }

    private func playAssetCue(kind: AudioCueKind, intensity: Double, position: SCNVector3) -> Bool {
        guard let url = audioAssetURL(for: kind), let file = try? AVAudioFile(forReading: url) else {
            return false
        }

        let player = AVAudioPlayerNode()
        applySpatial(player, kind: kind, position: position)
        player.volume = Float(max(0.06, min(1.0, intensity)))

        if spatialCuePlayers.count >= Self.maxAssetPlayers {
            let stale = spatialCuePlayers.removeFirst()
            stale.stop()
            engine.detach(stale)
        }

        spatialCuePlayers.append(player)
        engine.attach(player)
        // 强制单声道：AVAudioEnvironmentNode 不接受立体声输入，直接连接会抛 ObjC 异常导致崩溃。
        engine.connect(player, to: outputNode(for: kind), format: monoFormat(matching: file.processingFormat))
        player.scheduleFile(file, at: nil)
        player.play()
        return true
    }

    private func monoFormat(matching format: AVAudioFormat) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) ?? format
    }

    private func outputNode(for kind: AudioCueKind) -> AVAudioNode {
        // 心跳是"颅内"信号，始终走主混音器不做空间定位。
        if kind == .heartbeat { return engine.mainMixerNode }
        // 单声道设备没有环境节点可用，直接回退主混音器。
        guard outputCapability.usesSpatialEnvironment else { return engine.mainMixerNode }
        return environment ?? engine.mainMixerNode
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

    // MARK: - 素材查找

    private func computeAssetStatus() -> AudioAssetStatus {
        var missingCues: [String] = []
        for kind in AudioCueKind.allCases {
            // 不仅检查文件存在，还要确认可解码，避免「报告可用但实际无声」。
            guard let url = audioAssetURL(for: kind), (try? AVAudioFile(forReading: url)) != nil else {
                missingCues.append(assetBaseName(for: kind))
                continue
            }
        }
        var missingLoops: [String] = []
        for name in loopAssetNames {
            guard let url = audioLoopURL(named: name), (try? AVAudioFile(forReading: url)) != nil else {
                missingLoops.append(name)
                continue
            }
        }
        return AudioAssetStatus(
            cueAvailable: AudioCueKind.allCases.count - missingCues.count,
            cueTotal: AudioCueKind.allCases.count,
            loopAvailable: loopAssetNames.count - missingLoops.count,
            loopTotal: loopAssetNames.count,
            missingCues: missingCues,
            missingLoops: missingLoops,
            outputDescription: outputCapability.displayName
        )
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
        // 读取路径不创建目录；目录创建职责在 GameManager.openExternalAudioDirectory。
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
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

    /// 各种 cue 的音色纹理。`noise` 由调用方传入渲染块私有的 PRNG 状态。
    private func texture(kind: AudioCueKind, phase: Double, frame: AVAudioFrameCount, noise: inout UInt32) -> Float {
        switch kind {
        case .paper:
            return SpatialAudioManager.xorshift(&noise) * 0.65 + Float(sin(phase * 2.7)) * 0.35
        case .footstep, .chair:
            return frame % 2 == 0 ? 1 : -0.7
        case .phone:
            return sin(phase * 0.18) > 0 ? 1 : 0.35
        case .whisper, .crying:
            return SpatialAudioManager.xorshift(&noise) * 0.35 + 0.5
        case .lights:
            return Float(sin(phase * 3.1)) * 0.6 + SpatialAudioManager.xorshift(&noise) * 0.25
        case .heartbeat:
            return sin(phase) > 0.82 ? 1 : 0
        case .broadcast:
            return Float(sin(phase * 0.08)) * 0.55 + SpatialAudioManager.xorshift(&noise) * 0.12 + 0.45
        case .knock:
            return frame % 8 < 3 ? 1.0 : -0.35
        case .stomach:
            return Float(sin(phase * 0.17)) * 0.65 + Float(sin(phase * 0.05)) * 0.35
        case .wrapper:
            return SpatialAudioManager.xorshift(&noise) * 0.85 + Float(sin(phase * 4.3)) * 0.15
        case .teacherCough:
            return frame % 5 < 3 ? SpatialAudioManager.xorshift(&noise) * 0.8 + 0.4 : Float(sin(phase * 0.12)) * 0.35
        case .teacherSigh:
            return Float(sin(phase * 0.06)) * 0.45 + SpatialAudioManager.xorshift(&noise) * 0.22 + 0.28
        }
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func clampedAmplitude(_ value: Float) -> Float {
        min(max(value, 0), 0.12)
    }
}
