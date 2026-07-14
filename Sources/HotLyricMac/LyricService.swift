import CryptoKit
import Foundation

struct ProviderLyrics: Sendable {
    let original: String
    let translation: String?
    let provider: String
    let matchedTitle: String?
    let matchedArtists: [String]

    init(
        original: String,
        translation: String?,
        provider: String,
        matchedTitle: String? = nil,
        matchedArtists: [String] = []
    ) {
        self.original = original
        self.translation = translation
        self.provider = provider
        self.matchedTitle = matchedTitle
        self.matchedArtists = matchedArtists
    }
}

struct LyricSearchCandidate: Identifiable, Equatable, Sendable {
    let provider: String
    let songID: String
    let title: String
    let artists: [String]
    var id: String { "\(provider):\(songID)" }
    var subtitle: String { "\(artists.joined(separator: ", ")) · \(provider)" }
}

private struct MusicInformation: Sendable {
    let id: String
    let name: String
    let artists: [String]
}

private struct CachedLyricMatch: Codable {
    let title: String
    let artists: [String]
}

private struct CachedLyricsDocument: Codable {
    let version: Int
    let original: String
    let translation: String?
    let provider: String
    let matchedTitle: String?
    let matchedArtists: [String]
}

struct LyricCachePolicy: Equatable, Sendable {
    let maxBytes: Int64
    let maxEntries: Int
    let maxAge: TimeInterval

    static let standard = LyricCachePolicy(
        maxBytes: 100 * 1_024 * 1_024,
        maxEntries: 2_000,
        maxAge: 90 * 24 * 60 * 60
    )
}

struct LyricCacheStatistics: Equatable, Sendable {
    let entryCount: Int
    let totalBytes: Int64

    static let empty = LyricCacheStatistics(entryCount: 0, totalBytes: 0)

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

private protocol LyricProvider: Sendable {
    var name: String { get }
    func search(title: String, artist: String) async -> [MusicInformation]
    func fetch(id: String) async -> ProviderLyrics?
    func fetch(title: String, artist: String, duration: TimeInterval) async -> ProviderLyrics?
}

private extension LyricProvider {
    func fetch(title: String, artist: String, duration: TimeInterval) async -> ProviderLyrics? {
        let candidates = await search(title: title, artist: artist)
        guard let match = bestMatch(title: title, artist: artist, candidates: candidates) else { return nil }
        guard let result = await fetch(id: match.id) else { return nil }
        return ProviderLyrics(
            original: result.original,
            translation: result.translation,
            provider: result.provider,
            matchedTitle: match.name,
            matchedArtists: match.artists
        )
    }
}

private struct NetEaseLyricProvider: LyricProvider {
    let name = "NetEase"

    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            struct Artist: Decodable { let name: String }
            let id: Int64
            let name: String
            let ar: [Artist]?
            let artists: [Artist]?
        }
        let result: Result?
    }

    private struct LyricResponse: Decodable {
        struct Part: Decodable { let lyric: String? }
        let lrc: Part?
        let tlyric: Part?
        let yrc: Part?
        let ytlrc: Part?
    }

    func search(title: String, artist: String) async -> [MusicInformation] {
        guard let url = URL(string: "https://music.163.com/api/cloudsearch/pc") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let query = "s=\(urlEncode("\(title) \(artist)"))&type=1&limit=20&offset=0"
        request.httpBody = Data(query.utf8)

        guard
            let data = try? await URLSession.shared.data(for: request).0,
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return [] }

        return (response.result?.songs ?? []).map {
            MusicInformation(id: String($0.id), name: $0.name, artists: ($0.ar ?? $0.artists ?? []).map(\.name))
        }
    }

    func fetch(id: String) async -> ProviderLyrics? {
        var components = URLComponents(string: "https://interface3.music.163.com/api/song/lyric/v1")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "cp", value: "false"),
            URLQueryItem(name: "lv", value: "0"),
            URLQueryItem(name: "kv", value: "0"),
            URLQueryItem(name: "tv", value: "0"),
            URLQueryItem(name: "rv", value: "0"),
            URLQueryItem(name: "yv", value: "0"),
            URLQueryItem(name: "ytv", value: "0"),
            URLQueryItem(name: "yrv", value: "0")
        ]
        guard
            let lyricURL = components.url,
            let lyricData = try? await URLSession.shared.data(from: lyricURL).0,
            let lyric = try? JSONDecoder().decode(LyricResponse.self, from: lyricData)
        else { return nil }
        let classic = lyric.lrc?.lyric
        let enhanced = lyric.yrc?.lyric
        let original = enhanced.flatMap { value in
            LRCParser.parse(value).contains { !$0.words.isEmpty } ? value : nil
        } ?? classic
        guard let original, !original.isEmpty else { return nil }
        return ProviderLyrics(
            original: original,
            translation: lyric.ytlrc?.lyric ?? lyric.tlyric?.lyric,
            provider: name
        )
    }
}

private struct QQMusicLyricProvider: LyricProvider {
    let name = "QQMusic"

    private struct SearchResponse: Decodable {
        struct DataBody: Decodable {
            struct SongBody: Decodable { let list: [Song] }
            let song: SongBody
        }
        struct Song: Decodable {
            struct Singer: Decodable { let name: String }
            let songmid: String
            let songname: String
            let singer: [Singer]
        }
        let data: DataBody
    }

    private struct LyricResponse: Decodable {
        let lyric: String?
        let trans: String?
        let qrc: String?
    }

    func search(title: String, artist: String) async -> [MusicInformation] {
        var components = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        components.queryItems = [
            URLQueryItem(name: "w", value: "\(title) \(artist)"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: "20"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        guard
            let data = try? await URLSession.shared.data(for: request).0,
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return [] }

        return response.data.song.list.map {
            MusicInformation(id: $0.songmid, name: $0.songname, artists: $0.singer.map(\.name))
        }
    }

    func fetch(id: String) async -> ProviderLyrics? {
        var lyricComponents = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        lyricComponents.queryItems = [
            URLQueryItem(name: "songmid", value: id),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1"),
            URLQueryItem(name: "qrc", value: "1")
        ]
        guard let lyricURL = lyricComponents.url else { return nil }
        var lyricRequest = URLRequest(url: lyricURL)
        lyricRequest.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        guard
            let lyricData = try? await URLSession.shared.data(for: lyricRequest).0,
            let lyric = try? JSONDecoder().decode(LyricResponse.self, from: lyricData)
        else { return nil }
        let enhanced = lyric.qrc.flatMap { value in
            LRCParser.parse(value).contains { !$0.words.isEmpty } ? value : nil
        }
        guard let original = enhanced ?? lyric.lyric, !original.isEmpty else { return nil }
        return ProviderLyrics(original: original, translation: lyric.trans, provider: name)
    }
}

actor LyricService {
    private let providers: [String: any LyricProvider] = [
        "NetEase": NetEaseLyricProvider(),
        "QQMusic": QQMusicLyricProvider()
    ]
    private let fileManager = FileManager.default
    private let instrumentalFlags = ["纯音乐，请欣赏", "此歌曲为没有填词的纯音乐，请您欣赏"]
    private let cacheDirectoryOverride: URL?
    private let cachePolicy: LyricCachePolicy

    init(cacheDirectory: URL? = nil, cachePolicy: LyricCachePolicy = .standard) {
        cacheDirectoryOverride = cacheDirectory
        self.cachePolicy = cachePolicy
    }

    func lyrics(for track: Track, defaultProvider: String = "NetEase") async -> Lyrics {
        if let cached = cachedLyrics(for: track) { return cached }

        var order = [defaultProvider]
        order.append(contentsOf: providers.keys.sorted().filter { $0 != defaultProvider })
        for name in order {
            guard let provider = providers[name], let result = await provider.fetch(
                title: track.title,
                artist: track.artist,
                duration: track.duration
            ) else { continue }
            let original = LRCParser.parse(result.original)
            guard isUseful(original) else { continue }
            let translation = result.translation.map(LRCParser.parse) ?? []
            storeCachedLyrics(result, for: track)
            return Lyrics(
                lines: original,
                translationLines: isUseful(translation) ? translation : [],
                source: result.provider,
                matchedTitle: result.matchedTitle,
                matchedArtists: result.matchedArtists
            )
        }
        return .empty
    }

    func search(for track: Track) async -> [LyricSearchCandidate] {
        var result: [LyricSearchCandidate] = []
        for name in ["NetEase", "QQMusic"] {
            guard let provider = providers[name] else { continue }
            let songs = await provider.search(title: track.title, artist: track.artist)
            result.append(contentsOf: songs.prefix(12).map {
                LyricSearchCandidate(provider: name, songID: $0.id, title: $0.name, artists: $0.artists)
            })
        }
        return result
    }

    func lyrics(for candidate: LyricSearchCandidate, track: Track) async -> Lyrics? {
        guard let provider = providers[candidate.provider], let result = await provider.fetch(id: candidate.songID) else { return nil }
        let original = LRCParser.parse(result.original)
        guard isUseful(original) else { return nil }
        let translation = result.translation.map(LRCParser.parse) ?? []
        let enrichedResult = ProviderLyrics(
            original: result.original,
            translation: result.translation,
            provider: result.provider,
            matchedTitle: candidate.title,
            matchedArtists: candidate.artists
        )
        storeCachedLyrics(enrichedResult, for: track)
        return Lyrics(
            lines: original,
            translationLines: isUseful(translation) ? translation : [],
            source: result.provider,
            matchedTitle: candidate.title,
            matchedArtists: candidate.artists
        )
    }

    func importLocalLyric(from url: URL, for track: Track) -> Lyrics? {
        guard
            let content = try? String(contentsOf: url, encoding: .utf8),
            isUseful(LRCParser.parse(content))
        else { return nil }
        let result = ProviderLyrics(
            original: content,
            translation: nil,
            provider: "本地歌词",
            matchedTitle: track.title,
            matchedArtists: track.artist.isEmpty ? [] : [track.artist]
        )
        storeCachedLyrics(result, for: track)
        return Lyrics(
            lines: LRCParser.parse(content),
            translationLines: [],
            source: "本地歌词",
            matchedTitle: track.title,
            matchedArtists: track.artist.isEmpty ? [] : [track.artist]
        )
    }

    func clearCache() { try? fileManager.removeItem(at: cacheDirectory) }

    @discardableResult
    func maintainCache(now: Date = Date()) -> LyricCacheStatistics {
        var entries = cacheEntries()
        let expirationDate = now.addingTimeInterval(-cachePolicy.maxAge)

        for entry in entries where entry.lastAccess < expirationDate {
            removeCacheEntry(entry)
        }
        entries.removeAll { $0.lastAccess < expirationDate }
        entries.sort { $0.lastAccess < $1.lastAccess }

        var totalBytes = entries.reduce(Int64(0)) { $0 + $1.totalBytes }
        while
            let oldest = entries.first,
            entries.count > max(0, cachePolicy.maxEntries) || totalBytes > max(0, cachePolicy.maxBytes)
        {
            removeCacheEntry(oldest)
            totalBytes -= oldest.totalBytes
            entries.removeFirst()
        }

        return LyricCacheStatistics(entryCount: entries.count, totalBytes: max(0, totalBytes))
    }

    func cacheStatistics() -> LyricCacheStatistics {
        let entries = cacheEntries()
        return LyricCacheStatistics(
            entryCount: entries.count,
            totalBytes: entries.reduce(Int64(0)) { $0 + $1.totalBytes }
        )
    }

    func removeCachedLyrics(for track: Track) {
        let key = cacheKey(for: track)
        try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent("\(key).json"))
        let legacyKey = legacyCacheKey(for: track)
        for suffix in ["", "_trans", "_source", "_match.json"] {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent("\(legacyKey)\(suffix)"))
        }
    }

    private func isUseful(_ lines: [LyricLine]) -> Bool {
        !lines.isEmpty && lines.contains { !$0.text.isEmpty } && !lines.contains { instrumentalFlags.contains($0.text) }
    }

    private var cacheDirectory: URL {
        if let cacheDirectoryOverride { return cacheDirectoryOverride }
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HotLyricMac/cache", isDirectory: true)
    }

    private func cacheKey(for track: Track) -> String {
        let duration = Int(track.duration.rounded())
        let key = "v2|\(track.title)|\(track.artist)|\(duration)"
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func legacyCacheKey(for track: Track) -> String {
        let key = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        return Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func cachedLyrics(for track: Track) -> Lyrics? {
        let key = cacheKey(for: track)
        let documentURL = cacheDirectory.appendingPathComponent("\(key).json")
        if
            let data = try? Data(contentsOf: documentURL),
            let document = try? JSONDecoder().decode(CachedLyricsDocument.self, from: data),
            document.version == 2
        {
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: documentURL.path)
            let lines = LRCParser.parse(document.original)
            guard isUseful(lines) else { return nil }
            let translation = document.translation.map(LRCParser.parse) ?? []
            return Lyrics(
                lines: lines,
                translationLines: isUseful(translation) ? translation : [],
                source: document.provider,
                matchedTitle: document.matchedTitle ?? track.title,
                matchedArtists: document.matchedArtists
            )
        }

        return cachedLegacyLyrics(for: track)
    }

    private func cachedLegacyLyrics(for track: Track) -> Lyrics? {
        let key = legacyCacheKey(for: track)
        let originalURL = cacheDirectory.appendingPathComponent(key)
        guard
            let originalText = try? String(contentsOf: originalURL, encoding: .utf8),
            isUseful(LRCParser.parse(originalText))
        else { return nil }
        let translationURL = cacheDirectory.appendingPathComponent("\(key)_trans")
        let translationText = try? String(contentsOf: translationURL, encoding: .utf8)
        let sourceURL = cacheDirectory.appendingPathComponent("\(key)_source")
        let source = (try? String(contentsOf: sourceURL, encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 } ?? "本地缓存"
        let matchURL = cacheDirectory.appendingPathComponent("\(key)_match.json")
        let match = (try? Data(contentsOf: matchURL)).flatMap { try? JSONDecoder().decode(CachedLyricMatch.self, from: $0) }
        let result = Lyrics(
            lines: LRCParser.parse(originalText),
            translationLines: translationText.map(LRCParser.parse) ?? [],
            source: source,
            matchedTitle: match?.title ?? track.title,
            matchedArtists: match?.artists ?? (track.artist.isEmpty ? [] : [track.artist])
        )
        storeCachedLyrics(
            ProviderLyrics(
                original: originalText,
                translation: translationText,
                provider: source,
                matchedTitle: result.matchedTitle,
                matchedArtists: result.matchedArtists
            ),
            for: track
        )
        return result
    }

    func storeCachedLyrics(_ lyrics: ProviderLyrics, for track: Track) {
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let key = cacheKey(for: track)
        let document = CachedLyricsDocument(
            version: 2,
            original: lyrics.original,
            translation: lyrics.translation.flatMap { $0.isEmpty ? nil : $0 },
            provider: lyrics.provider,
            matchedTitle: lyrics.matchedTitle,
            matchedArtists: lyrics.matchedArtists
        )
        guard
            let data = try? JSONEncoder().encode(document),
            (try? data.write(
                to: cacheDirectory.appendingPathComponent("\(key).json"),
                options: .atomic
            )) != nil
        else { return }

        let legacyKey = legacyCacheKey(for: track)
        for suffix in ["", "_trans", "_source", "_match.json"] {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent("\(legacyKey)\(suffix)"))
        }
        maintainCache()
    }

    private struct CacheFileRecord {
        let url: URL
        let size: Int64
        let modificationDate: Date
    }

    private struct CacheEntryRecord {
        let key: String
        let files: [CacheFileRecord]
        let totalBytes: Int64
        let lastAccess: Date
    }

    private func cacheEntries() -> [CacheEntryRecord] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var grouped: [String: [CacheFileRecord]] = [:]
        for url in urls {
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                values.isRegularFile == true
            else { continue }
            let record = CacheFileRecord(
                url: url,
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? .distantPast
            )
            grouped[cacheEntryKey(for: url.lastPathComponent), default: []].append(record)
        }

        return grouped.map { key, files in
            CacheEntryRecord(
                key: key,
                files: files,
                totalBytes: files.reduce(Int64(0)) { $0 + $1.size },
                lastAccess: files.map(\.modificationDate).max() ?? .distantPast
            )
        }
    }

    private func cacheEntryKey(for filename: String) -> String {
        for suffix in ["_match.json", "_trans", "_source"] where filename.hasSuffix(suffix) {
            return String(filename.dropLast(suffix.count))
        }
        if filename.hasSuffix(".json") { return String(filename.dropLast(5)) }
        return filename
    }

    private func removeCacheEntry(_ entry: CacheEntryRecord) {
        for file in entry.files { try? fileManager.removeItem(at: file.url) }
    }
}

private func urlEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

private func normalized(_ value: String) -> String {
    value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[-\(\)/\\&]"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
}

private func bestMatch(title: String, artist: String, candidates: [MusicInformation]) -> MusicInformation? {
    let target = normalized("\(title) \(artist)")
    let ranked = candidates.map { candidate -> (MusicInformation, Int) in
        let artistVariants = candidate.artists.indices.map {
            normalized("\(candidate.name) \(candidate.artists[0...$0].joined(separator: " "))")
        }
        let variants = artistVariants + [normalized(candidate.name)]
        return (candidate, variants.map { levenshtein(target, $0) }.min() ?? Int.max)
    }.sorted { $0.1 < $1.1 }
    guard let best = ranked.first else { return nil }
    let tolerance = max(3, min(12, target.count / 2))
    return best.1 <= tolerance ? best.0 : nil
}

private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs), b = Array(rhs)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var previous = Array(0...b.count)
    for (i, left) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, right) in b.enumerated() {
            current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1))
        }
        previous = current
    }
    return previous[b.count]
}
