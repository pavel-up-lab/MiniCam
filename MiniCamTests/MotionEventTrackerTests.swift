import XCTest
@testable import MiniCam

final class MotionEventTrackerTests: XCTestCase {
    func testStandardSensitivityTracksThirtyPercentConfidenceMovement() {
        var tracker = MotionEventTracker()

        let appeared = tracker.process(
            [detection(confidence: 0.30, x: 0.10)],
            at: date(0)
        )
        let startedMoving = tracker.process(
            [detection(confidence: 0.30, x: 0.13)],
            at: date(0.5)
        )

        XCTAssertNil(appeared)
        XCTAssertEqual(
            startedMoving,
            MotionEventCandidate(startedAt: date(0), categories: [.person])
        )
    }

    func testStationaryObjectCreatesOneEventOnlyWhenMovementStarts() {
        var tracker = MotionEventTracker()

        let appeared = tracker.process(
            [detection(x: 0.10)],
            at: date(0)
        )
        let remainedStill = tracker.process(
            [detection(x: 0.10)],
            at: date(1)
        )
        let startedMoving = tracker.process(
            [detection(x: 0.13)],
            at: date(2)
        )
        let keptMoving = tracker.process(
            [detection(x: 0.16)],
            at: date(3)
        )

        XCTAssertNil(appeared)
        XCTAssertNil(remainedStill)
        XCTAssertEqual(
            startedMoving,
            MotionEventCandidate(startedAt: date(1), categories: [.person])
        )
        XCTAssertNil(keptMoving)
    }

    func testConfirmedStopAllowsAnotherMovementEvent() {
        var tracker = MotionEventTracker()
        _ = tracker.process([detection(x: 0.10)], at: date(0))
        let firstStart = tracker.process([detection(x: 0.13)], at: date(1))
        _ = tracker.process([detection(x: 0.13)], at: date(2))
        _ = tracker.process([detection(x: 0.13)], at: date(3))

        let secondStart = tracker.process([detection(x: 0.16)], at: date(4))

        XCTAssertEqual(
            firstStart,
            MotionEventCandidate(startedAt: date(0), categories: [.person])
        )
        XCTAssertEqual(
            secondStart,
            MotionEventCandidate(startedAt: date(3), categories: [.person])
        )
    }

    func testTracksObjectsIndependentlyAndForgetsThemAfterThirtySeconds() {
        var tracker = MotionEventTracker()
        _ = tracker.process(
            [detection(x: 0.10), detection(category: .car, x: 0.55)],
            at: date(0)
        )

        let combinedStart = tracker.process(
            [detection(x: 0.13), detection(category: .car, x: 0.58)],
            at: date(1)
        )
        _ = tracker.process([], at: date(31))
        let reappeared = tracker.process([detection(x: 0.70)], at: date(32))
        let movedAgain = tracker.process([detection(x: 0.73)], at: date(33))

        XCTAssertEqual(
            combinedStart,
            MotionEventCandidate(startedAt: date(0), categories: [.person, .car])
        )
        XCTAssertNil(reappeared)
        XCTAssertEqual(
            movedAgain,
            MotionEventCandidate(startedAt: date(32), categories: [.person])
        )
    }

    private func detection(
        category: MotionObjectCategory = .person,
        confidence: Double = 0.9,
        x: Double
    ) -> ObjectDetection {
        ObjectDetection(
            category: category,
            confidence: confidence,
            bounds: CGRect(x: x, y: 0.20, width: 0.10, height: 0.30)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
