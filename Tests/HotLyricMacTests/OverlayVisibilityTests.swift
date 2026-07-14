import AppKit
import XCTest
@testable import HotLyricMac

@MainActor
final class OverlayVisibilityTests: XCTestCase {
    func testAutoHideWithoutPlayerAndManualVisibilityToggle() {
        _ = NSApplication.shared
        let preferences = Preferences()
        preferences.autoHideWithoutPlayer = true
        let model = AppModel(preferences: preferences, automaticallyMaintainsCache: false)
        let controller = OverlayWindowController(model: model, preferences: preferences)

        controller.show()
        XCTAssertFalse(controller.managedWindow.isVisible)
        XCTAssertFalse(model.isLyricWindowVisible)

        preferences.autoHideWithoutPlayer = false
        XCTAssertTrue(controller.managedWindow.isVisible)
        controller.toggleVisibility()
        XCTAssertFalse(controller.managedWindow.isVisible)
        controller.managedWindow.close()
    }
}
