import SceneKit

extension ClassroomCoordinator {
    static func prologueArrivalCamera(
        elapsed: TimeInterval,
        reduceMotion: Bool
    ) -> (position: SCNVector3, yaw: Float) {
        let progress = Float((elapsed / 7).clamped(to: 0...1))
        let fullYaw: Float
        if progress < 0.42 {
            fullYaw = -0.68 * (progress / 0.42)
        } else if progress < 0.72 {
            fullYaw = -0.68 + 1.36 * ((progress - 0.42) / 0.3)
        } else {
            fullYaw = 0.68 * (1 - (progress - 0.72) / 0.28)
        }
        let yaw = fullYaw * (reduceMotion ? 0.35 : 1)
        return (SCNVector3(17.8, 1.62, 19.5 - 10.5 * progress), yaw)
    }

    static func isTutorialToggle(keyCode: UInt16, characters: String?) -> Bool {
        keyCode == 17 || characters?.lowercased() == "t"
    }

    static func isCompleteTutorialKey(keyCode: UInt16, characters: String?) -> Bool {
        keyCode == 8 || characters?.lowercased() == "c"
    }
}
