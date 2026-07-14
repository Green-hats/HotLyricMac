import XCTest
@testable import HotLyricMac

final class MediaSessionSelectorTests: XCTestCase {
    private func track(_ player: PlayerKind, playing: Bool, title: String) -> Track {
        Track(title: title, artist: "artist", album: "album", duration: 180, position: 10, isPlaying: playing, player: player)
    }

    func testPausedActiveSessionDoesNotJumpBackToPreferredPlayer() {
        let selected = MediaSessionSelector.select(
            preferred: .appleMusic,
            active: .spotify,
            appleMusic: track(.appleMusic, playing: false, title: "old apple song"),
            spotify: track(.spotify, playing: false, title: "current spotify song")
        )
        XCTAssertEqual(selected?.player, .spotify)
        XCTAssertEqual(selected?.title, "current spotify song")
    }

    func testSwitchesWhenAnotherPlayerActuallyStartsPlaying() {
        let selected = MediaSessionSelector.select(
            preferred: .appleMusic,
            active: .spotify,
            appleMusic: track(.appleMusic, playing: true, title: "new apple song"),
            spotify: track(.spotify, playing: false, title: "paused spotify song")
        )
        XCTAssertEqual(selected?.player, .appleMusic)
    }

    func testForcedPlayerOverridesAutomaticSelection() {
        let selected = MediaSessionSelector.select(
            preferred: .appleMusic,
            active: .appleMusic,
            forced: .spotify,
            appleMusic: track(.appleMusic, playing: true, title: "apple"),
            spotify: track(.spotify, playing: false, title: "spotify")
        )
        XCTAssertEqual(selected?.player, .spotify)
    }

    func testSpotifyDurationIsConvertedFromMilliseconds() {
        XCTAssertEqual(PlayerTimeNormalizer.duration(245_500, player: .spotify), 245.5)
        XCTAssertEqual(PlayerTimeNormalizer.duration(245.5, player: .appleMusic), 245.5)
    }

    func testActivePlayerIsProbedAloneUntilSecondaryIntervalExpires() {
        let now = Date(timeIntervalSince1970: 100)
        let recentProbe = now.addingTimeInterval(-2)
        let players = PlayerProbePlanner.playersToProbe(
            forced: nil,
            active: .spotify,
            now: now,
            lastProbeDates: [.appleMusic: recentProbe],
            secondaryInterval: 5
        )
        XCTAssertEqual(players, [.spotify])
    }

    func testSecondaryPlayerIsProbedAtLowFrequency() {
        let now = Date(timeIntervalSince1970: 100)
        let oldProbe = now.addingTimeInterval(-5)
        let players = PlayerProbePlanner.playersToProbe(
            forced: nil,
            active: .spotify,
            now: now,
            lastProbeDates: [.appleMusic: oldProbe],
            secondaryInterval: 5
        )
        XCTAssertEqual(players, [.spotify, .appleMusic])
    }

    func testForcedPlayerNeverProbesTheOtherPlayer() {
        let players = PlayerProbePlanner.playersToProbe(
            forced: .appleMusic,
            active: .spotify,
            now: Date(),
            lastProbeDates: [:]
        )
        XCTAssertEqual(players, [.appleMusic])
    }
}
