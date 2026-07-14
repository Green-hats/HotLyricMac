import XCTest
@testable import HotLyricMac

final class PollingIntervalPlannerTests: XCTestCase {
    func testPlayingUsesFastPolling() {
        XCTAssertEqual(PollingIntervalPlanner.interval(hasTrack: true, isPlaying: true, lowPowerMode: false), 0.5)
    }

    func testPauseAndLowPowerReducePolling() {
        XCTAssertEqual(PollingIntervalPlanner.interval(hasTrack: true, isPlaying: false, lowPowerMode: true), 2.0)
        XCTAssertEqual(PollingIntervalPlanner.interval(hasTrack: false, isPlaying: false, lowPowerMode: true), 3.0)
    }
}
