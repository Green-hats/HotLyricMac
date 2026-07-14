import XCTest
@testable import HotLyricMac

final class LRCParserTests: XCTestCase {
    func testParsesAndSortsTimestamps() {
        let lrc = "[00:12.34]second\n[00:01.5][00:03.50]first"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.text), ["first", "first", "second"])
        XCTAssertEqual(lines.map(\.time), [1.5, 3.5, 12.34])
    }

    func testFindsCurrentLine() {
        let lyrics = Lyrics(lines: [
            .init(time: 1, text: "one"),
            .init(time: 5, text: "two")
        ], translationLines: [], source: "test")
        XCTAssertNil(lyrics.lineIndex(at: 0.9))
        XCTAssertEqual(lyrics.lineIndex(at: 5), 1)
        XCTAssertEqual(lyrics.lineIndex(at: 4.5, offset: 0.5), 1)
    }

    func testTranslationMatchesOriginalTimestampWithTolerance() {
        let lyrics = Lyrics(
            lines: [.init(time: 10, text: "hello")],
            translationLines: [.init(time: 10.35, text: "你好")],
            source: "test"
        )
        XCTAssertEqual(lyrics.translation(forOriginalLineAt: 0), "你好")
    }

    func testPreservesMatchedLyricMetadata() {
        let lyrics = Lyrics(
            lines: [.init(time: 0, text: "hello")],
            translationLines: [],
            source: "网易云音乐",
            matchedTitle: "匹配歌曲",
            matchedArtists: ["歌手甲", "歌手乙"]
        )

        XCTAssertEqual(lyrics.matchedTitle, "匹配歌曲")
        XCTAssertEqual(lyrics.matchedArtists, ["歌手甲", "歌手乙"])
        XCTAssertEqual(lyrics.source, "网易云音乐")
    }

    func testParsesNetEaseYRCWordTiming() {
        let lines = LRCParser.parse("[1000,1200](1000,300,0)你(1400,300,0)好(1900,200,0)！")

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "你好！")
        XCTAssertEqual(lines[0].words.map(\.text), ["你", "好", "！"])
        XCTAssertEqual(lines[0].words[1].startTime, 1.4, accuracy: 0.0001)
        XCTAssertEqual(lines[0].words[1].duration, 0.3, accuracy: 0.0001)
    }

    func testParsesQQQRCWordTiming() {
        let lines = LRCParser.parse("[1000,1200]你(1000,300)好(1400,300)！(1900,200)")

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "你好！")
        XCTAssertEqual(lines[0].words.map(\.text), ["你", "好", "！"])
        XCTAssertEqual(lines[0].words[2].startTime, 1.9, accuracy: 0.0001)
    }

    func testWordTimingPlannerHoldsProgressAcrossGap() {
        let words = [
            LyricWord(startTime: 1, duration: 0.5, text: "你"),
            LyricWord(startTime: 2, duration: 0.5, text: "好")
        ]
        let spans = KaraokeTimingPlanner.characterSpans(for: words)
        let plan = KaraokeTimingPlanner.plan(spans: spans, at: 1.5, lineEnd: 3)

        XCTAssertEqual(plan?.initialProgress, 0.5)
        XCTAssertEqual(plan?.duration, 1.5)
        XCTAssertTrue(plan?.values.contains(0.5) == true)
        XCTAssertEqual(plan?.values.last, 1)
    }
}
