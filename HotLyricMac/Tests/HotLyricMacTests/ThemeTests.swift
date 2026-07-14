import XCTest
@testable import HotLyricMac

final class ThemeTests: XCTestCase {
    func testARGBColorRoundTrip() {
        XCTAssertEqual(LyricTheme.argb(LyricTheme.color("#80402010")), "#80402010")
    }

    func testCustomThemeKeepsEveryChannel() {
        let theme = LyricTheme.custom(
            border: "#01020304",
            background: "#11121314",
            lyric: "#21222324",
            karaoke: "#31323334",
            lyricStroke: "#41424344",
            karaokeStroke: "#51525354"
        )
        XCTAssertEqual(theme.name, "自定义")
        XCTAssertEqual(theme.karaokeStroke, "#51525354")
    }
}
