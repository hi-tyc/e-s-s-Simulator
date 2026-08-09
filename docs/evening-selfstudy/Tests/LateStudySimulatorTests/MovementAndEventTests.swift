import XCTest
@testable import LateStudySimulator

@MainActor
final class MovementAndEventTests: XCTestCase {
    func testContinuousLookDoesNotSnapToPoseCenter() {
        let game = makePlayingGame()

        game.rotateStudentView(deltaX: -50, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .forward)
        XCTAssertEqual(game.studentLookYaw, 0.3, accuracy: 0.0001)

        game.rotateStudentView(deltaX: -30, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .left)
        XCTAssertEqual(game.studentLookYaw, 0.48, accuracy: 0.0001)

        game.rotateStudentView(deltaX: -10, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .left)
        XCTAssertEqual(game.studentLookYaw, 0.54, accuracy: 0.0001)
    }

    func testMovementUsesFacingDirectionForForwardAndStrafe() {
        let game = makeRoamingGame(yaw: 0)

        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        XCTAssertEqual(game.freeRoam.positionX, 5, accuracy: 0.0001)
        XCTAssertLessThan(game.freeRoam.positionZ, 0)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.freeRoam.yaw = .pi / 2
        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        XCTAssertLessThan(game.freeRoam.positionX, 5)
        XCTAssertEqual(game.freeRoam.positionZ, 0, accuracy: 0.0001)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.moveStudentFreeRoam(forward: 0, strafe: 1, deltaTime: 0.1)
        XCTAssertEqual(game.freeRoam.positionX, 5, accuracy: 0.0001)
        XCTAssertLessThan(game.freeRoam.positionZ, 0)
    }

    func testDiagonalMovementIsNotFasterThanStraightMovement() {
        let game = makeRoamingGame(yaw: 0)

        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        let straightDistance = hypot(game.freeRoam.positionX - 5, game.freeRoam.positionZ)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.moveStudentFreeRoam(forward: 1, strafe: 1, deltaTime: 0.1)
        let diagonalDistance = hypot(game.freeRoam.positionX - 5, game.freeRoam.positionZ)

        XCTAssertEqual(diagonalDistance, straightDistance, accuracy: 0.0001)
    }

    func testControlSprintMovesFasterAndIncreasesHunger() {
        let game = makeRoamingGame(yaw: 0)
        let initialHunger = game.player.hunger

        for _ in 0..<10 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        }
        let walkingDistance = abs(game.freeRoam.positionZ)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.setFreeRoamSprinting(true)
        for _ in 0..<10 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        }
        game.setFreeRoamSprinting(false)
        let sprintingDistance = abs(game.freeRoam.positionZ)

        XCTAssertGreaterThan(sprintingDistance, walkingDistance * 1.6)
        XCTAssertGreaterThan(game.player.hunger, initialHunger)
        XCTAssertFalse(game.freeRoam.isSprinting)
    }

    func testEventPreservesRoamingPositionAndPausesCountdown() {
        let game = makeRoamingGame(yaw: 0.7)
        game.freeRoam.positionX = 5.4
        game.freeRoam.positionZ = -2.3
        let remainingBeforeEvent = game.freeRoam.endsAt.timeIntervalSinceNow

        game.presentEvent(kind: .knockOnDoor, title: "测试事件", body: "测试", choices: [])
        Thread.sleep(forTimeInterval: 0.2)
        game.continueAfterEvent()

        XCTAssertEqual(game.freeRoam.positionX, 5.4, accuracy: 0.0001)
        XCTAssertEqual(game.freeRoam.positionZ, -2.3, accuracy: 0.0001)
        XCTAssertEqual(game.freeRoam.yaw, 0.7, accuracy: 0.0001)
        XCTAssertTrue(game.freeRoam.isActive)
        XCTAssertEqual(game.freeRoam.endsAt.timeIntervalSinceNow, remainingBeforeEvent, accuracy: 0.08)
    }

    func testReturnToSeatKeepsRoamingUntilScreenIsCovered() async throws {
        let game = makeRoamingGame(yaw: 0.7)

        game.returnToSeatFromFreeRoam()
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertFalse(game.freeRoam.isActive)
        XCTAssertEqual(game.player.posture, .seated)
        XCTAssertEqual(game.cameraPose, .forward)

        try await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertFalse(game.isReturningToSeat)
    }

    func testTeacherCollisionStopsPlayerBeforeModelOverlap() {
        let game = makeRoamingGame(yaw: 0)
        game.teacher.positionIndex = 0
        game.freeRoam.positionX = -2.7
        game.freeRoam.positionZ = -3.55
        game.freeRoam.hasExitedClassroom = false

        for _ in 0..<20 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.05)
        }

        let teacher = game.teacherFreeRoamPosition
        let distance = hypot(game.freeRoam.positionX - teacher.x, game.freeRoam.positionZ - teacher.z)
        XCTAssertGreaterThanOrEqual(distance, 0.49)
        XCTAssertGreaterThan(game.freeRoam.positionZ, teacher.z)
        XCTAssertTrue(game.isTeacherBlockingFreeRoamPosition(x: teacher.x, z: teacher.z))
    }

    func testStandingHidesFirstPersonBodyButKeepsGroundedChair() {
        let coordinator = ClassroomCoordinator()
        let game = makePlayingGame()

        game.player.posture = .seated
        coordinator.update(game: game)
        XCTAssertTrue(coordinator.playerSeatedPropsVisible)
        XCTAssertTrue(coordinator.playerGroundedChairVisible)
        XCTAssertEqual(coordinator.playerGroundedChairLegCount, 4)

        game.player.posture = .standing
        game.freeRoam = StudentFreeRoamState(
            isActive: true,
            positionX: -0.6,
            positionZ: 1.65,
            yaw: 0,
            pitch: 0,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(60),
            hasExitedClassroom: false,
            isSideways: false,
            isSprinting: false,
            frontDoorOpen: false,
            rearDoorOpen: false
        )
        coordinator.update(game: game)
        XCTAssertFalse(coordinator.playerSeatedPropsVisible)
        XCTAssertTrue(coordinator.playerGroundedChairVisible)

        game.freeRoam = StudentFreeRoamState()
        game.player.posture = .seated
        game.viewMode = .teacher
        coordinator.update(game: game)
        XCTAssertFalse(coordinator.playerSeatedPropsVisible)
    }

    func testDoorInteractionAndLeafSizedCollision() {
        let game = makeRoamingGame(yaw: 0)
        game.frontDoorOpen = false
        game.freeRoam.frontDoorOpen = false
        game.freeRoam.positionX = 3.6
        game.freeRoam.positionZ = StudentDoor.front.centerZ

        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
        XCTAssertTrue(game.interactWithNearbyDoor())
        XCTAssertTrue(game.frontDoorOpen)
        XCTAssertFalse(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.31, z: StudentDoor.front.centerZ - 0.43))
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.31, z: StudentDoor.front.centerZ + 0.43))

        XCTAssertTrue(game.interactWithNearbyDoor())
        XCTAssertFalse(game.frontDoorOpen)
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
    }

    private func makePlayingGame() -> GameManager {
        let game = GameManager()
        game.gameState = .playing
        game.activeRole = .regularStudent
        game.viewMode = .student
        return game
    }

    private func makeRoamingGame(yaw: Double) -> GameManager {
        let game = makePlayingGame()
        game.player.posture = .standing
        game.studentLookYaw = yaw
        game.freeRoam = StudentFreeRoamState(
            isActive: true,
            positionX: 5,
            positionZ: 0,
            yaw: yaw,
            pitch: 0,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(60),
            hasExitedClassroom: true,
            isSideways: false,
            isSprinting: false,
            frontDoorOpen: true,
            rearDoorOpen: true
        )
        return game
    }
}
