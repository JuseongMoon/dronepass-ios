import XCTest
@testable import DronePass

final class UserActivityTrackingTests: XCTestCase {
    func testFirstAuthenticatedActivityIsRecorded() {
        XCTAssertTrue(
            shouldRecordUserActivity(
                lastRecordedAt: nil,
                now: Date(timeIntervalSince1970: 1_000)
            )
        )
    }

    func testActivityWithinThrottleWindowIsSkipped() {
        XCTAssertFalse(
            shouldRecordUserActivity(
                lastRecordedAt: Date(timeIntervalSince1970: 1_000),
                now: Date(timeIntervalSince1970: 1_899)
            )
        )
    }

    func testActivityAtThrottleBoundaryIsRecorded() {
        XCTAssertTrue(
            shouldRecordUserActivity(
                lastRecordedAt: Date(timeIntervalSince1970: 1_000),
                now: Date(timeIntervalSince1970: 1_900)
            )
        )
    }
}
