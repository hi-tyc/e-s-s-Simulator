import Foundation

/// 把 3D 教室场景渲染成字符画。
///
/// 设计目标：让 AI 能像人类一样"看见"当前视角。
/// 采用第一人称射线投射：从玩家眼位向视角方向发射射线，
/// 命中最前的物体并按其类型输出字符。
///
/// 坐标系（与 ClassroomSceneView 一致）：
/// - x: -4（左墙）→ +4（右墙），右为走廊
/// - y: 0（地面）→ 3.5（天花板）
/// - z: -6（前墙/黑板）→ +6（后墙）
@MainActor
enum SceneASCIIRenderer {

    /// 世界中的一个可渲染物体。
    struct Entity {
        var name: String
        var glyph: Character
        var x: Double
        var z: Double
        var width: Double
        var height: Double
        var depth: Double
        /// 渲染优先级：数值越大越"靠前"，同深度时优先显示。
        var priority: Int
    }

    /// 视角参数。
    struct Camera {
        var x: Double
        var y: Double
        var z: Double
        /// 水平朝向（弧度）。0 = 面向 -z（黑板方向），正值为向左。
        var yaw: Double
        /// 俯仰（弧度）。正为抬头。
        var pitch: Double
        var fov: Double
    }

    /// 构建教室中的静态实体（桌椅、黑板、老师、同学）。
    static func buildEntities(game: GameManager) -> [Entity] {
        var entities: [Entity] = []

        // 黑板（前墙）
        entities.append(Entity(name: "黑板", glyph: "▬", x: 0, z: -5.9, width: 3.2, height: 1.1, depth: 0.1, priority: 10))
        // 讲台
        entities.append(Entity(name: "讲台", glyph: "▰", x: 0, z: -4.6, width: 1.2, height: 0.5, depth: 0.6, priority: 9))
        // 前后门
        entities.append(Entity(name: "前门", glyph: "▯", x: 4.0, z: -4.0, width: 0.15, height: 2.0, depth: 0.9, priority: 8))
        entities.append(Entity(name: "后门", glyph: "▯", x: 4.0, z: 4.0, width: 0.15, height: 2.0, depth: 0.9, priority: 8))
        // 钟
        entities.append(Entity(name: "钟", glyph: "◷", x: 2.85, z: -5.85, width: 0.3, height: 0.3, depth: 0.1, priority: 7))

        return entities
    }

    /// 渲染当前帧。
    ///
    /// - Parameters:
    ///   - width: 字符画宽度
    ///   - height: 字符画高度
    static func render(game: GameManager, width: Int = 78, height: Int = 26) -> String {
        let camera = cameraFor(game: game)
        var grid = Array(repeating: Array(repeating: Character(" "), count: width), count: height)
        var depthBuffer = Array(repeating: Double.greatestFiniteMagnitude, count: width * height)

        // 收集实体
        var entities = buildEntities(game: game)
        entities.append(contentsOf: deskEntities(game: game))
        entities.append(contentsOf: classmateEntities(game: game))
        if let teacher = teacherEntity(game: game) { entities.append(teacher) }

        // 对每个像素做射线投射
        for row in 0..<height {
            for col in 0..<width {
                // 屏幕坐标 → 视角偏移
                let ndcX = (Double(col) / Double(width - 1)) * 2 - 1
                let ndcY = 1 - (Double(row) / Double(height - 1)) * 2
                // 字符宽高比约 1:2，因此水平方向需要更小的角度跨度。
                let fovX = camera.fov * 0.55
                let fovY = camera.fov

                let rayYaw = camera.yaw + ndcX * fovX / 2
                let rayPitch = camera.pitch + ndcY * fovY / 2

                let dirX = -sin(rayYaw) * cos(rayPitch)
                let dirY = sin(rayPitch)
                let dirZ = -cos(rayYaw) * cos(rayPitch)

                var best: (entity: Entity, distance: Double)?

                for entity in entities {
                    if let distance = rayIntersectsBox(
                        origin: (camera.x, camera.y, camera.z),
                        direction: (dirX, dirY, dirZ),
                        entity: entity
                    ) {
                        if best == nil || distance < best!.distance {
                            best = (entity, distance)
                        }
                    }
                }

                let index = row * width + col
                if let hit = best, hit.distance < depthBuffer[index] {
                    depthBuffer[index] = hit.distance
                    grid[row][col] = hit.entity.glyph
                }
            }
        }

        // 把网格转成字符串，并叠加 HUD
        var lines: [String] = []
        for row in 0..<height {
            lines.append(String(grid[row]))
        }
        return lines.joined(separator: "\n")
    }

    private static func cameraFor(game: GameManager) -> Camera {
        // 六章叙事版没有座位选择：玩家固定坐在教室中排。
        let deskX = -1.2
        let deskZ = 1.5

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
            x: deskX,
            y: height,
            z: deskZ + 0.35,
            yaw: game.studentLookYaw,
            pitch: game.studentLookPitch,
            fov: 1.6
        )
    }

    // MARK: - 实体构建

    private static func deskEntities(game: GameManager) -> [Entity] {
        var result: [Entity] = []
        // 玩家固定座位（该版本无座位选择）。
        let playerSeat = AgentGameSession.fallbackPlayerSeat
        for row in 0..<5 {
            for column in 0..<4 {
                let x = Double(column) * 1.2 - 2.4
                let z = Double(row) * 1.45 - 2.25
                let isPlayer = row == playerSeat.row && column == playerSeat.column
                // 玩家自己的座位不参与渲染：相机就位于其上，否则会糊满整个画面。
                guard isPlayer == false else { continue }
                result.append(Entity(
                    name: "课桌",
                    glyph: "▢",
                    x: x, z: z, width: 0.55, height: 0.75, depth: 0.5,
                    priority: 5
                ))
            }
        }
        return result
    }

    private static func classmateEntities(game: GameManager) -> [Entity] {
        game.classmates.map { mate in
            let x = Double(mate.seat.column) * 1.2 - 2.4
            let z = Double(mate.seat.row) * 1.45 - 2.25
            return Entity(
                name: mate.name,
                glyph: glyph(for: mate.state),
                x: x, z: z, width: 0.45, height: 1.25, depth: 0.45,
                priority: 15
            )
        }
    }

    private static func teacherEntity(game: GameManager) -> Entity? {
        // 教师巡逻路径（与 ClassroomSceneView 保持一致）
        let path: [(Double, Double)] = [
            (-2.7, -4.25), (2.6, -3.2), (2.6, -1.2), (1.2, 0.45),
            (0.2, 1.55), (-2.2, 0.4), (-2.8, -1.4), (0, -4.35), (-3.45, 4.25)
        ]
        let index = min(game.teacher.positionIndex, path.count - 1)
        let (x, z) = path[index]
        return Entity(name: "老师", glyph: "☖", x: x, z: z, width: 0.5, height: 1.7, depth: 0.5, priority: 18)
    }

    private static func glyph(for state: ClassmateState) -> Character {
        switch state {
        case .studying: return "☺"
        case .anxious: return "◉"
        case .usingPhone: return "▤"
        case .sleeping: return "☁"
        case .lookingAtPlayer: return "⊙"
        case .offeringHelp: return "♥"
        case .crying: return "◍"
        case .covering: return "▥"
        }
    }

    // MARK: - 射线与盒体求交

    private static func rayIntersectsBox(
        origin: (Double, Double, Double),
        direction: (Double, Double, Double),
        entity: Entity
    ) -> Double? {
        let hw = entity.width / 2
        let hd = entity.depth / 2
        // 垂直方向：从地面到 height
        let minX = entity.x - hw, maxX = entity.x + hw
        let minY = 0.0, maxY = entity.height
        let minZ = entity.z - hd, maxZ = entity.z + hd

        var tMin = 0.0
        var tMax = Double.greatestFiniteMagnitude

        // X 轴
        if abs(direction.0) < 1e-9 {
            if origin.0 < minX || origin.0 > maxX { return nil }
        } else {
            let t1 = (minX - origin.0) / direction.0
            let t2 = (maxX - origin.0) / direction.0
            tMin = max(tMin, min(t1, t2))
            tMax = min(tMax, max(t1, t2))
        }
        // Y 轴
        if abs(direction.1) < 1e-9 {
            if origin.1 < minY || origin.1 > maxY { return nil }
        } else {
            let t1 = (minY - origin.1) / direction.1
            let t2 = (maxY - origin.1) / direction.1
            tMin = max(tMin, min(t1, t2))
            tMax = min(tMax, max(t1, t2))
        }
        // Z 轴
        if abs(direction.2) < 1e-9 {
            if origin.2 < minZ || origin.2 > maxZ { return nil }
        } else {
            let t1 = (minZ - origin.2) / direction.2
            let t2 = (maxZ - origin.2) / direction.2
            tMin = max(tMin, min(t1, t2))
            tMax = min(tMax, max(t1, t2))
        }

        guard tMax >= tMin, tMax > 0 else { return nil }
        return tMin > 0 ? tMin : tMax
    }
}
