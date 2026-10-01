import Foundation

/// 把 3D 教室场景渲染成**带光照与颜色的字符画**。
///
/// 与初版渲染器的区别：初版只有几何轮廓（谁在前、谁在后），
/// 本版重建了完整的光照管线，使输出接近玩家看到的画面：
///
///  1. **材质**：每个实体带基础色（取自 ClassroomSceneView 的实际定义）
///  2. **光照**：环境光（随时间/氛围变化）+ 可选点光源（教师压力灯、手机蓝光）
///  3. **后处理**：饱和度衰减（疲劳）、暗角（压力）、整体明度
///  4. **字符映射**：由该像素的**亮度**决定字符密度（暗→空，亮→密）
///
/// 输出两种形式：
///  - `render(...)`        带 ANSI 24 位真彩色的字符画（终端可直接看）
///  - `renderSampleGrid(...)` 每格的字符 + RGB 数值（供 AI 精确解析）
@MainActor
enum SceneRGBRenderer {

    /// 世界中的一个可渲染物体。
    struct Entity {
        var name: String
        var baseColor: SceneMaterials.RGB
        /// 自发光（手机蓝光、灯管、压力灯）——不受环境光影响。
        var emission: SceneMaterials.RGB? = nil
        var x: Double
        var z: Double
        var width: Double
        var height: Double
        var depth: Double
        /// 垂直位置偏移（桌面 0.72、半身像等）
        var baseY: Double = 0
    }

    struct Camera {
        var x: Double
        var y: Double
        var z: Double
        var yaw: Double
        var pitch: Double
        var fov: Double
    }

    /// 一次渲染的完整参数。
    struct RenderContext {
        var camera: Camera
        var entities: [Entity]
        /// 环境光颜色与强度
        var ambientColor: SceneMaterials.RGB
        var ambientIntensity: Double
        /// 点光源列表（位置 + 颜色 + 强度 + 影响半径）
        var pointLights: [PointLight]
        /// 饱和度（0...1），疲劳时降低
        var saturation: Double
        /// 暗角强度（0...1），压力高时增强
        var vignette: Double

        struct PointLight {
            var x: Double
            var y: Double
            var z: Double
            var color: SceneMaterials.RGB
            var intensity: Double
            var radius: Double
        }
    }

    // MARK: - 入口

    /// 构建渲染上下文（从游戏状态推导光照与后处理）。
    static func context(game: GameManager) -> RenderContext {
        let camera = cameraFor(game: game)
        var entities = buildEntities(game: game)

        // 环境光：按当前时段
        let period = mapPeriod(game.currentPeriod)
        let nightDim = game.classroomLightLevel
        var ambient = SceneMaterials.skyColor(for: period)
        var ambientIntensity = SceneMaterials.ambientIntensity(for: period) * nightDim

        // 停电事件会把灯降到很低
        if game.classroomLightLevel < 0.6 {
            ambient = ambient.mixed(with: SceneMaterials.RGB.from(0.18, 0.22, 0.36), ratio: 0.6)
            ambientIntensity *= 0.55
        }

        // 教师靠近时补一盏暖色点光，让"被盯着"在画面里可见
        var lights: [RenderContext.PointLight] = []
        if game.teacher.isNearPlayer {
            let teacherPos = teacherPosition(game: game)
            lights.append(RenderContext.PointLight(
                x: teacherPos.0, y: 1.6, z: teacherPos.1,
                color: SceneMaterials.pressureLight,
                intensity: 0.85, radius: 3.2
            ))
        }
        // 手机亮着时给玩家位置补一点蓝光
        if let mate = game.classmates.first(where: { $0.state == .usingPhone }) {
            let x = Double(mate.seat.column) * 1.2 - 2.4
            let z = Double(mate.seat.row) * 1.45 - 2.25
            lights.append(RenderContext.PointLight(
                x: x, y: 0.85, z: z,
                color: SceneMaterials.phoneGlow,
                intensity: 0.6, radius: 1.1
            ))
            entities = entities.map { entity in
                var copy = entity
                if entity.name == mate.name { copy.emission = SceneMaterials.phoneGlow.scaled(0.45) }
                return copy
            }
        }

        // 后处理：疲劳降低饱和度，压力提高暗角
        let fatigue = 1 - game.player.focusQuality
        let saturation = max(0.25, 1.0 - fatigue * 0.34)
        let vignette = min(1.0, 0.45 + fatigue * 1.15 + game.player.stress / 200)

        return RenderContext(
            camera: camera,
            entities: entities,
            ambientColor: ambient,
            ambientIntensity: ambientIntensity,
            pointLights: lights,
            saturation: saturation,
            vignette: vignette
        )
    }

    private static func mapPeriod(_ period: StudyPeriod) -> SceneMaterials.Period {
        switch period {
        case .first: return .first
        case .breakOne: return .breakOne
        case .second: return .second
        case .breakTwo: return .breakTwo
        case .third: return .third
        }
    }

    // MARK: - 渲染

    /// 渲染为带 ANSI 真彩色的字符画。
    ///
    /// 每个像素：
    /// 1. 射线投射找最近命中
    /// 2. 计算该点的颜色（材质 × 光照 + 自发光）
    /// 3. 应用后处理（饱和度、暗角）
    /// 4. 由亮度选字符，由颜色生成 ANSI 前景色
    static func render(context: RenderContext, width: Int = 78, height: Int = 26, colored: Bool = true) -> String {
        let grid = sample(context: context, width: width, height: height)
        let reset = "\u{001B}[0m"
        var lines: [String] = []

        for row in grid {
            var line = ""
            for pixel in row {
                if colored {
                    line += pixel.color.ansiForeground + String(pixel.glyph)
                } else {
                    line += String(pixel.glyph)
                }
            }
            lines.append(colored ? line + reset : line)
        }
        return lines.joined(separator: "\n")
    }

    /// 一个采样像素。
    struct Pixel {
        var glyph: Character
        var color: SceneMaterials.RGB
        var luminance: Double
        var distance: Double
        var entityName: String?
    }

    /// 逐像素采样（供 AI 解析的精确数据）。
    static func sample(context: RenderContext, width: Int, height: Int) -> [[Pixel]] {
        var result: [[Pixel]] = []
        result.reserveCapacity(height)

        for row in 0..<height {
            var line: [Pixel] = []
            line.reserveCapacity(width)
            for col in 0..<width {
                line.append(samplePixel(context: context, col: col, row: row, width: width, height: height))
            }
            result.append(line)
        }
        return result
    }

    private static func samplePixel(
        context: RenderContext,
        col: Int, row: Int,
        width: Int, height: Int
    ) -> Pixel {
        let camera = context.camera
        let ndcX = (Double(col) / Double(width - 1)) * 2 - 1
        let ndcY = 1 - (Double(row) / Double(height - 1)) * 2
        let fovX = camera.fov * 0.55
        let fovY = camera.fov
        let rayYaw = camera.yaw + ndcX * fovX / 2
        let rayPitch = camera.pitch + ndcY * fovY / 2

        let dirX = -sin(rayYaw) * cos(rayPitch)
        let dirY = sin(rayPitch)
        let dirZ = -cos(rayYaw) * cos(rayPitch)

        var best: (entity: Entity, distance: Double, hitPoint: (Double, Double, Double))?

        for entity in context.entities {
            if let hit = rayIntersectsBox(
                origin: (camera.x, camera.y, camera.z),
                direction: (dirX, dirY, dirZ),
                entity: entity
            ) {
                if best == nil || hit.distance < best!.distance {
                    best = (entity, hit.distance, hit.point)
                }
            }
        }

        // 暗角：屏幕边缘整体压暗
        let radial = sqrt(ndcX * ndcX + ndcY * ndcY * 0.6)
        let vignetteFactor = 1 - context.vignette * radial * radial * 0.85

        guard let hit = best else {
            // 未命中任何物体：显示环境/天空
            let color = context.ambientColor
                .scaled(context.ambientIntensity * vignetteFactor)
                .desaturated(1 - context.saturation)
                .clamped()
            let lum = luminance(color)
            return Pixel(
                glyph: glyphFor(luminance: lum),
                color: color,
                luminance: lum,
                distance: .greatestFiniteMagnitude,
                entityName: nil
            )
        }

        // 材质基础色
        var color = hit.entity.baseColor.scaled(context.ambientIntensity)

        // 环境光叠加（让暗处不至于全黑，带一点环境色温）
        color = color.mixed(with: context.ambientColor.scaled(context.ambientIntensity * 0.35), ratio: 0.4)

        // 点光源
        for light in context.pointLights {
            let dx = hit.hitPoint.0 - light.x
            let dy = hit.hitPoint.1 - light.y
            let dz = hit.hitPoint.2 - light.z
            let dist = sqrt(dx * dx + dy * dy + dz * dz)
            guard dist < light.radius else { continue }
            let falloff = (1 - dist / light.radius)
            let contribution = falloff * falloff * light.intensity
            color = color.mixed(with: light.color.scaled(contribution), ratio: min(1, contribution))
        }

        // 自发光（手机、灯管等）——不受环境光影响
        if let emission = hit.entity.emission {
            color = color.mixed(with: emission, ratio: 0.75)
        }

        color = color
            .desaturated(1 - context.saturation)
            .scaled(max(0.12, vignetteFactor))
            .clamped()

        let lum = luminance(color)
        return Pixel(
            glyph: glyphFor(luminance: lum),
            color: color,
            luminance: lum,
            distance: hit.distance,
            entityName: hit.entity.name
        )
    }

    // MARK: - 工具

    /// 由亮度选择字符密度。
    private static func glyphFor(luminance: Double) -> Character {
        let ramp: [Character] = [" ", ".", ":", "*", "o", "O", "@"]
        let index = Int((luminance * Double(ramp.count - 1)).rounded())
        return ramp[min(max(index, 0), ramp.count - 1)]
    }

    private static func luminance(_ color: SceneMaterials.RGB) -> Double {
        min(max(color.r * 0.299 + color.g * 0.587 + color.b * 0.114, 0), 1)
    }

    private static func cameraFor(game: GameManager) -> Camera {
        if game.freeRoam.isActive {
            return Camera(
                x: game.freeRoam.positionX,
                y: 1.58,
                z: game.freeRoam.positionZ,
                yaw: game.freeRoam.yaw,
                pitch: game.freeRoam.pitch,
                fov: 1.6
            )
        }
        let height = game.player.posture == .standing ? 1.58 : 1.18
        return Camera(
            x: -1.2,
            y: height,
            z: 1.5,
            yaw: game.studentLookYaw,
            pitch: game.studentLookPitch,
            fov: 1.6
        )
    }

    private static func teacherPosition(game: GameManager) -> (Double, Double) {
        let path: [(Double, Double)] = [
            (-2.7, -4.25), (2.6, -3.2), (2.6, -1.2), (1.2, 0.45),
            (0.2, 1.55), (-2.2, 0.4), (-2.8, -1.4), (0, -4.35), (-3.45, 4.25)
        ]
        let index = min(game.teacher.positionIndex, path.count - 1)
        return path[index]
    }

    // MARK: - 实体构建（带材质）

    private static func buildEntities(game: GameManager) -> [Entity] {
        var entities: [Entity] = []

        // 环境
        entities.append(Entity(name: "黑板", baseColor: SceneMaterials.blackboard,
                               x: 0, z: -5.9, width: 3.2, height: 1.1, depth: 0.1))
        entities.append(Entity(name: "讲台", baseColor: SceneMaterials.podium,
                               x: 0, z: -4.6, width: 1.2, height: 0.6, depth: 0.6))
        entities.append(Entity(name: "前门", baseColor: SceneMaterials.door,
                               x: 4.0, z: -4.0, width: 0.15, height: 2.0, depth: 0.9))
        entities.append(Entity(name: "后门", baseColor: SceneMaterials.door,
                               x: 4.0, z: 4.0, width: 0.15, height: 2.0, depth: 0.9))
        entities.append(Entity(name: "墙钟", baseColor: SceneMaterials.clock,
                               x: 2.85, z: -5.85, width: 0.3, height: 0.3, depth: 0.1, baseY: 2.4))
        entities.append(Entity(name: "前墙", baseColor: SceneMaterials.wall,
                               x: 0, z: -6.0, width: 8.0, height: 3.5, depth: 0.06))
        entities.append(Entity(name: "左墙", baseColor: SceneMaterials.dimWall,
                               x: -4.0, z: 0, width: 0.06, height: 3.5, depth: 12.0))

        // 课桌与椅子
        // 玩家固定座位（与 AgentGameSession 保持一致）。
        let playerSeat = (row: 2, column: 1)
        for row in 0..<5 {
            for column in 0..<4 {
                let x = Double(column) * 1.2 - 2.4
                let z = Double(row) * 1.45 - 2.25
                let isPlayer = row == playerSeat.row && column == playerSeat.column
                guard isPlayer == false else { continue }
                entities.append(Entity(name: "课桌", baseColor: SceneMaterials.deskTop,
                                       x: x, z: z, width: 0.55, height: 0.75, depth: 0.5))
                entities.append(Entity(name: "椅背", baseColor: SceneMaterials.chairBack,
                                       x: x, z: z + 0.55, width: 0.52, height: 0.85, depth: 0.06))
            }
        }

        // 同学
        entities.append(contentsOf: game.classmates.map { mate in
            let x = Double(mate.seat.column) * 1.2 - 2.4
            let z = Double(mate.seat.row) * 1.45 - 2.25
            return Entity(
                name: mate.name,
                baseColor: uniformColor(for: mate),
                x: x, z: z, width: 0.44, height: 1.2, depth: 0.42
            )
        })

        // 老师
        let (tx, tz) = teacherPosition(game: game)
        entities.append(Entity(name: "老师", baseColor: SceneMaterials.teacherOutfit,
                               x: tx, z: tz, width: 0.5, height: 1.7, depth: 0.5))

        return entities
    }

    /// 同学校服颜色（按性格，与真实场景一致）。
    private static func uniformColor(for mate: Classmate) -> SceneMaterials.RGB {
        let profile = mate.profile
        if profile.rebelliousness > 72 { return SceneMaterials.RGB.from(0.46, 0.18, 0.28) }
        if profile.orderliness > 72 { return SceneMaterials.RGB.from(0.15, 0.20, 0.46) }
        if profile.empathy > 72 { return SceneMaterials.RGB.from(0.22, 0.42, 0.38) }
        if profile.anxiety > 68 { return SceneMaterials.RGB.from(0.40, 0.34, 0.30) }
        return SceneMaterials.uniform
    }

    // MARK: - 射线与盒体求交

    private static func rayIntersectsBox(
        origin: (Double, Double, Double),
        direction: (Double, Double, Double),
        entity: Entity
    ) -> (distance: Double, point: (Double, Double, Double))? {
        let hw = entity.width / 2
        let hd = entity.depth / 2
        let minX = entity.x - hw, maxX = entity.x + hw
        let minY = entity.baseY, maxY = entity.baseY + entity.height
        let minZ = entity.z - hd, maxZ = entity.z + hd

        var tMin = 0.0
        var tMax = Double.greatestFiniteMagnitude
        var hitAxis = 0
        var hitSign = 1.0

        // X
        if abs(direction.0) < 1e-9 {
            if origin.0 < minX || origin.0 > maxX { return nil }
        } else {
            let t1 = (minX - origin.0) / direction.0
            let t2 = (maxX - origin.0) / direction.0
            if min(t1, t2) > tMin { tMin = min(t1, t2); hitAxis = 0; hitSign = t1 < t2 ? -1 : 1 }
            tMax = min(tMax, max(t1, t2))
        }
        // Y
        if abs(direction.1) < 1e-9 {
            if origin.1 < minY || origin.1 > maxY { return nil }
        } else {
            let t1 = (minY - origin.1) / direction.1
            let t2 = (maxY - origin.1) / direction.1
            if min(t1, t2) > tMin { tMin = min(t1, t2); hitAxis = 1; hitSign = t1 < t2 ? -1 : 1 }
            tMax = min(tMax, max(t1, t2))
        }
        // Z
        if abs(direction.2) < 1e-9 {
            if origin.2 < minZ || origin.2 > maxZ { return nil }
        } else {
            let t1 = (minZ - origin.2) / direction.2
            let t2 = (maxZ - origin.2) / direction.2
            if min(t1, t2) > tMin { tMin = min(t1, t2); hitAxis = 2; hitSign = t1 < t2 ? -1 : 1 }
            tMax = min(tMax, max(t1, t2))
        }

        guard tMax >= tMin, tMax > 0 else { return nil }
        let distance = tMin > 0 ? tMin : tMax
        let point = (
            origin.0 + direction.0 * distance,
            origin.1 + direction.1 * distance,
            origin.2 + direction.2 * distance
        )
        _ = (hitAxis, hitSign)
        return (distance, point)
    }
}
