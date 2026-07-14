import Foundation
import XCTest
@testable import HotLyricMac

final class LyricCacheTests: XCTestCase {
    private let track = Track(
        title: "缓存测试歌曲",
        artist: "测试歌手",
        album: "测试专辑",
        duration: 180,
        position: 0,
        isPlaying: true,
        player: .appleMusic
    )

    func testReplacingCacheRemovesStaleTranslationAndMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(cacheDirectory: directory)

        await service.storeCachedLyrics(
            ProviderLyrics(
                original: "[00:00.00]旧歌词",
                translation: "[00:00.00]old translation",
                provider: "NetEase",
                matchedTitle: "旧匹配",
                matchedArtists: ["旧歌手"]
            ),
            for: track
        )
        await service.storeCachedLyrics(
            ProviderLyrics(
                original: "[00:00.00]新歌词",
                translation: nil,
                provider: "QQMusic",
                matchedTitle: "新匹配",
                matchedArtists: ["新歌手"]
            ),
            for: track
        )

        let cached = await service.cachedLyrics(for: track)
        XCTAssertEqual(cached?.lines.map(\.text), ["新歌词"])
        XCTAssertEqual(cached?.translationLines, [])
        XCTAssertEqual(cached?.source, "QQMusic")
        XCTAssertEqual(cached?.matchedTitle, "新匹配")
        XCTAssertEqual(cached?.matchedArtists, ["新歌手"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testClearCacheCompletesBeforeSubsequentRead() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(cacheDirectory: directory)
        await service.storeCachedLyrics(
            ProviderLyrics(original: "[00:00.00]歌词", translation: nil, provider: "本地"),
            for: track
        )

        await service.clearCache()

        let cached = await service.cachedLyrics(for: track)
        XCTAssertNil(cached)
    }

    func testRemovingCurrentTrackCacheDoesNotRequireClearingEverything() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(cacheDirectory: directory)
        await service.storeCachedLyrics(
            ProviderLyrics(original: "[00:00.00]歌词", translation: nil, provider: "本地"),
            for: track
        )

        await service.removeCachedLyrics(for: track)

        let cached = await service.cachedLyrics(for: track)
        XCTAssertNil(cached)
    }

    func testMaintenanceRemovesEntriesOlderThanPolicy() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(
            cacheDirectory: directory,
            cachePolicy: LyricCachePolicy(maxBytes: 1_000_000, maxEntries: 100, maxAge: 60)
        )
        await service.storeCachedLyrics(
            ProviderLyrics(original: "[00:00.00]过期歌词", translation: nil, provider: "测试"),
            for: track
        )
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-61)], ofItemAtPath: file.path)

        let statistics = await service.maintainCache(now: now)

        XCTAssertEqual(statistics, .empty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testMaintenanceKeepsOnlyConfiguredEntryCount() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(
            cacheDirectory: directory,
            cachePolicy: LyricCachePolicy(maxBytes: 1_000_000, maxEntries: 2, maxAge: 3_600)
        )
        for index in 0..<3 {
            await service.storeCachedLyrics(
                ProviderLyrics(original: "[00:00.00]歌词\(index)", translation: nil, provider: "测试"),
                for: cacheTrack(index)
            )
        }

        let statistics = await service.cacheStatistics()

        XCTAssertEqual(statistics.entryCount, 2)
    }

    func testMaintenanceEnforcesTotalByteLimit() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(
            cacheDirectory: directory,
            cachePolicy: LyricCachePolicy(maxBytes: 128, maxEntries: 100, maxAge: 3_600)
        )
        await service.storeCachedLyrics(
            ProviderLyrics(
                original: "[00:00.00]\(String(repeating: "很长的歌词", count: 100))",
                translation: nil,
                provider: "测试"
            ),
            for: track
        )

        let statistics = await service.cacheStatistics()

        XCTAssertEqual(statistics, .empty)
    }

    func testReadingCacheRefreshesItsLastAccessTime() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LyricService(
            cacheDirectory: directory,
            cachePolicy: LyricCachePolicy(maxBytes: 1_000_000, maxEntries: 100, maxAge: 60)
        )
        await service.storeCachedLyrics(
            ProviderLyrics(original: "[00:00.00]歌词", translation: nil, provider: "测试"),
            for: track
        )
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-59)],
            ofItemAtPath: file.path
        )

        _ = await service.cachedLyrics(for: track)
        let statistics = await service.maintainCache(now: Date().addingTimeInterval(2))

        XCTAssertEqual(statistics.entryCount, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HotLyricMacTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func cacheTrack(_ index: Int) -> Track {
        Track(
            title: "缓存测试歌曲 \(index)",
            artist: "测试歌手",
            album: "测试专辑",
            duration: 180 + Double(index),
            position: 0,
            isPlaying: true,
            player: .appleMusic
        )
    }
}
