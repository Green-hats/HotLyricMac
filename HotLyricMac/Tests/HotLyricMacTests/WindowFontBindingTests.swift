import AppKit
import XCTest
@testable import HotLyricMac

@MainActor
final class WindowFontBindingTests: XCTestCase {
    func testWindowResizeUpdatesFontAndFontChangeUpdatesWindow() {
        _ = NSApplication.shared
        let preferences = Preferences()
        preferences.secondRowType = .translationOrNext
        preferences.fontSize = 34
        let model = AppModel(preferences: preferences, automaticallyMaintainsCache: false)
        let controller = OverlayWindowController(model: model, preferences: preferences)

        var frame = controller.managedWindow.frame
        frame.size.height = LyricWindowLayoutPlanner.windowHeight(forFontSize: 46, secondRowType: .translationOrNext)
        controller.managedWindow.setFrame(frame, display: false)
        XCTAssertEqual(preferences.fontSize, 46, accuracy: 0.2)

        preferences.fontSize = 30
        XCTAssertEqual(
            controller.managedWindow.frame.height,
            LyricWindowLayoutPlanner.windowHeight(forFontSize: 30, secondRowType: .translationOrNext),
            accuracy: 0.5
        )
        controller.managedWindow.close()
    }
}
