import AppKit
import SwiftUI
import XCTest
@testable import HotLyricMac

@MainActor
final class WindowTests: XCTestCase {
    func testSettingsWindowIsExplicitlyPresented() {
        _ = NSApplication.shared
        let preferences = Preferences()
        let model = AppModel(preferences: preferences, automaticallyMaintainsCache: false)
        let controller = SettingsWindowController(model: model, preferences: preferences) {}

        controller.present()

        XCTAssertEqual(controller.window?.title, "热词设置")
        XCTAssertEqual(controller.window?.isVisible, true)
        XCTAssertEqual(controller.window?.contentView is NSHostingView<SettingsView>, true)
        controller.close()
    }
}
