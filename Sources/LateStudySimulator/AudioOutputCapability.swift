import AVFoundation
import Foundation

/// 音频输出能力探测与回退策略。
///
/// macOS 上 App **无法**直接编码 Dolby Atmos（需要 Dolby 授权编解码器）。
/// 实际的 Atmos 渲染由系统音频层或接收端完成：App 只要向设备输出
/// 与其能力匹配的多声道 PCM，系统就有机会上混为 Atmos。
///
/// 因此本类型负责按以下优先级选择输出配置：
///
/// 1. `.immersive`  —— 设备支持 ≥6 声道（5.1 / 7.1），交给系统上混
/// 2. `.stereo`     —— 设备支持 2 声道，启用环境节点 HRTF 双耳空间化
/// 3. `.mono`       —— 设备仅单声道
enum AudioOutputCapability {
    /// 多声道沉浸式输出（≥6 声道）。系统可据此上混为 Dolby Atmos。
    case immersive(channels: Int, sampleRate: Double)
    /// 双声道立体声（HRTF 空间化）。
    case stereo(sampleRate: Double)
    /// 单声道回退。
    case mono(sampleRate: Double)

    var sampleRate: Double {
        switch self {
        case .immersive(_, let rate), .stereo(let rate), .mono(let rate):
            return rate
        }
    }

    /// 主混音器应向硬件输出的声道数。
    var outputChannelCount: Int {
        switch self {
        case .immersive(let channels, _): return channels
        case .stereo: return 2
        case .mono: return 1
        }
    }

    /// 是否需要启用环境节点做空间定位。
    /// 立体声与沉浸式都启用（沉浸式下环境节点会把单声道源铺开到多声道）。
    var usesSpatialEnvironment: Bool {
        switch self {
        case .immersive, .stereo: return true
        case .mono: return false
        }
    }

    var displayName: String {
        switch self {
        case .immersive(let channels, _):
            return "沉浸式多声道（\(channels) 声道，可被系统上混为杜比全景声）"
        case .stereo:
            return "立体声（双耳 HRTF 空间化）"
        case .mono:
            return "单声道"
        }
    }

    /// 探测当前默认输出设备能力并给出配置。
    ///
    /// - Parameter outputFormat: 硬件输出总线格式，通常来自
    ///   `engine.outputNode.outputFormat(forBus: 0)`。
    static func detect(from outputFormat: AVAudioFormat) -> AudioOutputCapability {
        let rate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        let availableChannels = Int(outputFormat.channelCount)
        switch availableChannels {
        case 6...:
            // 5.1 及以上：按可用声道数输出，但不超过 8（7.1）。
            return .immersive(channels: min(availableChannels, 8), sampleRate: rate)
        case 2...5:
            return .stereo(sampleRate: rate)
        default:
            return .mono(sampleRate: rate)
        }
    }
}
