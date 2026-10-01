import Foundation

/// 场景材质库。
///
/// 数值取自 `ClassroomSceneView` 中的实际定义，确保渲染结果与玩家看到的
/// 场景一致（同样的墙体、地面、桌椅、门窗颜色）。
///
/// 颜色以线性 0...1 的 RGB 存储，渲染时再按光照与后处理换算为最终像素。
struct SceneMaterials {

    struct RGB {
        var r: Double
        var g: Double
        var b: Double

        static func from(_ r: Double, _ g: Double, _ b: Double) -> RGB {
            RGB(r: r, g: g, b: b)
        }

        /// 按系数缩放（用于光照衰减）。
        func scaled(_ factor: Double) -> RGB {
            RGB(r: r * factor, g: g * factor, b: b * factor)
        }

        /// 与另一颜色按比例混合（用于环境光叠加）。
        func mixed(with other: RGB, ratio: Double) -> RGB {
            let t = min(max(ratio, 0), 1)
            return RGB(
                r: r * (1 - t) + other.r * t,
                g: g * (1 - t) + other.g * t,
                b: b * (1 - t) + other.b * t
            )
        }

        /// 去饱和（模拟疲劳导致的色彩衰减）。
        func desaturated(_ amount: Double) -> RGB {
            let luma = r * 0.299 + g * 0.587 + b * 0.114
            return mixed(with: RGB(r: luma, g: luma, b: luma), ratio: amount)
        }

        func clamped() -> RGB {
            RGB(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1))
        }

        var ansiForeground: String {
            let c = clamped()
            return "\u{001B}[38;2;\(Int(c.r * 255));\(Int(c.g * 255));\(Int(c.b * 255))m"
        }

        var hex: String {
            let c = clamped()
            return String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
        }
    }

    // MARK: - 环境

    /// 教室地面（木地板）
    static let floor = RGB.from(0.34, 0.35, 0.36)
    /// 走廊地面
    static let corridorFloor = RGB.from(0.34, 0.35, 0.36)
    /// 主墙面
    static let wall = RGB.from(0.72, 0.74, 0.70)
    /// 昏暗墙面（后墙/侧墙）
    static let dimWall = RGB.from(0.52, 0.55, 0.55)
    /// 天花板
    static let ceiling = RGB.from(0.60, 0.61, 0.60)
    /// 门外地面
    static let outdoorGround = RGB.from(0.04, 0.045, 0.05)

    // MARK: - 家具

    /// 黑板
    static let blackboard = RGB.from(0.12, 0.20, 0.14)
    /// 粉笔字
    static let chalk = RGB.from(0.94, 0.88, 0.62)
    /// 讲台
    static let podium = RGB.from(0.42, 0.30, 0.20)
    /// 课桌桌面
    static let deskTop = RGB.from(0.48, 0.38, 0.28)
    /// 课桌主体
    static let deskBody = RGB.from(0.30, 0.24, 0.19)
    /// 椅子座板
    static let chairSeat = RGB.from(0.28, 0.24, 0.22)
    /// 椅子靠背
    static let chairBack = RGB.from(0.25, 0.21, 0.19)
    /// 椅腿
    static let chairLeg = RGB.from(0.18, 0.18, 0.17)
    /// 门（木门）
    static let door = RGB.from(0.38, 0.25, 0.15)
    /// 储物柜
    static let locker = RGB.from(0.42, 0.44, 0.46)
    /// 墙钟
    static let clock = RGB.from(0.92, 0.92, 0.90)

    // MARK: - 人物

    /// 校服（默认）
    static let uniform = RGB.from(0.20, 0.24, 0.42)
    /// 教师服装
    static let teacherOutfit = RGB.from(0.28, 0.22, 0.30)
    /// 皮肤
    static let skin = RGB.from(0.85, 0.68, 0.56)
    /// 头发
    static let hair = RGB.from(0.12, 0.10, 0.10)

    // MARK: - 状态特效

    /// 手机蓝光
    static let phoneGlow = RGB.from(0.05, 0.20, 0.80)
    /// 教师压力灯（暖橙）
    static let pressureLight = RGB.from(1.0, 0.48, 0.24)
    /// 教师后门观察灯（冷蓝）
    static let rearObservationLight = RGB.from(0.35, 0.62, 1.0)
    /// 灯管（冷白）
    static let tubeLight = RGB.from(0.96, 0.97, 1.0)
    /// 吊扇
    static let ceilingFan = RGB.from(0.55, 0.56, 0.58)

    // MARK: - 时间氛围（天空随时间变化，取自 updateTimeAtmosphere）

    enum Period {
        case first          // 第一节：黄昏
        case breakOne
        case second         // 第二节：入夜
        case breakTwo
        case third          // 第三节：深夜
    }

    static func skyColor(for period: Period) -> RGB {
        switch period {
        case .first: return RGB.from(0.58, 0.78, 0.96)
        case .breakOne: return RGB.from(0.58, 0.78, 0.96)
        case .second: return RGB.from(0.72, 0.50, 0.34)
        case .breakTwo: return RGB.from(0.12, 0.16, 0.30)
        case .third: return RGB.from(0.015, 0.025, 0.075)
        }
    }

    /// 该时段的环境光强度（0...1），用于整体亮度。
    static func ambientIntensity(for period: Period) -> Double {
        switch period {
        case .first: return 1.0
        case .breakOne: return 0.92
        case .second: return 0.72
        case .breakTwo: return 0.55
        case .third: return 0.38
        }
    }
}
