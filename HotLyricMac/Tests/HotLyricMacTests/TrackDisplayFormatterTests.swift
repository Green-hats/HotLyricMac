import XCTest
@testable import HotLyricMac

final class TrackDisplayFormatterTests: XCTestCase {
    private let track = Track(
        title: "晴天",
        artist: "周杰伦",
        album: "叶惠美",
        duration: 269,
        position: 65,
        isPlaying: true,
        player: .appleMusic
    )

    func testMetadataIncludesArtistAlbumPlayerAndStatus() {
        XCTAssertEqual(
            TrackDisplayFormatter.metadataLine(for: track, status: "正在匹配歌词…"),
            "周杰伦 · 叶惠美 · Apple Music · 正在匹配歌词…"
        )
    }

    func testPlaybackLineIncludesProgressAndLyricSource() {
        XCTAssertEqual(
            TrackDisplayFormatter.playbackLine(for: track, lyricSource: "QQMusic"),
            "Apple Music · 播放中 · 1:05 / 4:29 · QQMusic"
        )
    }
}
