import AppKit
import XCTest
@testable import HotLyricMac

final class WindowPlacementPlannerTests: XCTestCase {
    func testMovesOffscreenWindowBackToVisibleDisplay() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let input = NSRect(x: 2_000, y: -400, width: 780, height: 132)
        let result = WindowPlacementPlanner.adjustedFrame(input, visibleFrames: [screen])
        XCTAssertTrue(screen.contains(result))
    }

    func testKeepsWindowOnDisplayWithLargestIntersection() {
        let left = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let right = NSRect(x: 1000, y: 0, width: 1200, height: 900)
        let input = NSRect(x: 1200, y: 100, width: 700, height: 150)
        XCTAssertEqual(WindowPlacementPlanner.adjustedFrame(input, visibleFrames: [left, right]), input)
    }
}
