import XCTest
@testable import HotLyricMac

final class LyricWindowLayoutPlannerTests: XCTestCase {
    func testFontAndTwoRowWindowHeightRoundTrip() {
        let height = LyricWindowLayoutPlanner.windowHeight(forFontSize: 42, secondRowType: .translationOrNext)
        XCTAssertEqual(LyricWindowLayoutPlanner.fontSize(forWindowHeight: height, secondRowType: .translationOrNext), 42)
    }

    func testFontAndSingleRowWindowHeightRoundTrip() {
        let height = LyricWindowLayoutPlanner.windowHeight(forFontSize: 28, secondRowType: .hidden)
        XCTAssertEqual(LyricWindowLayoutPlanner.fontSize(forWindowHeight: height, secondRowType: .hidden), 28)
    }

    func testPlannerClampsSupportedFontRange() {
        XCTAssertEqual(LyricWindowLayoutPlanner.fontSize(forWindowHeight: 20, secondRowType: .hidden), 20)
        XCTAssertEqual(LyricWindowLayoutPlanner.fontSize(forWindowHeight: 1_000, secondRowType: .translationOrNext), 64)
    }
}
