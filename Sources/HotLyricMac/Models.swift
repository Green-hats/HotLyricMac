import Foundation

enum PlayerKind: String, Codable, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"

    var id: String { rawValue }
}

enum PlayerSelectionMode: String, CaseIterable, Identifiable {
    case automatic = "自动选择"
    case appleMusic = "锁定 Apple Music"
    case spotify = "锁定 Spotify"

    var id: String { rawValue }
    var forcedPlayer: PlayerKind? {
        switch self {
        case .automatic: nil
        case .appleMusic: .appleMusic
        case .spotify: .spotify
        }
    }
}

enum PlayerAccessState: Equatable, Sendable {
    case available
    case notRunning
    case permissionDenied
    case unavailable(String)
}

struct PlayerPollResult: Sendable {
    let track: Track?
    let access: [PlayerKind: PlayerAccessState]
}

struct Track: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let player: PlayerKind

    var identity: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

enum TrackDisplayFormatter {
    static func metadataLine(for track: Track, status: String? = nil) -> String {
        var parts = [track.artist, track.album, track.player.rawValue]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let status, !status.isEmpty { parts.append(status) }
        return parts.joined(separator: " · ")
    }

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func playbackLine(for track: Track, lyricSource: String) -> String {
        let state = track.isPlaying ? "播放中" : "已暂停"
        let time = "\(self.time(track.position)) / \(self.time(track.duration))"
        return [track.player.rawValue, state, time, lyricSource].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct LyricWord: Equatable, Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String

    var endTime: TimeInterval { startTime + duration }
}

struct LyricLine: Equatable, Sendable {
    let time: TimeInterval
    let text: String
    let words: [LyricWord]

    init(time: TimeInterval, text: String, words: [LyricWord] = []) {
        self.time = time
        self.text = text
        self.words = words
    }
}

struct Lyrics: Equatable, Sendable {
    let lines: [LyricLine]
    let translationLines: [LyricLine]
    let source: String
    let matchedTitle: String?
    let matchedArtists: [String]

    init(
        lines: [LyricLine],
        translationLines: [LyricLine],
        source: String,
        matchedTitle: String? = nil,
        matchedArtists: [String] = []
    ) {
        self.lines = lines
        self.translationLines = translationLines
        self.source = source
        self.matchedTitle = matchedTitle
        self.matchedArtists = matchedArtists
    }

    static let empty = Lyrics(lines: [], translationLines: [], source: "")

    var hasWordTiming: Bool { lines.contains { !$0.words.isEmpty } }

    func lineIndex(at position: TimeInterval, offset: TimeInterval = 0) -> Int? {
        guard !lines.isEmpty else { return nil }
        let timestamp = position + offset
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= timestamp {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func translation(at position: TimeInterval, offset: TimeInterval = 0) -> String? {
        guard !translationLines.isEmpty else { return nil }
        let timestamp = position + offset
        var candidate: LyricLine?
        for line in translationLines {
            if line.time <= timestamp { candidate = line } else { break }
        }
        return candidate?.text.isEmpty == false ? candidate?.text : nil
    }

    func translation(forOriginalLineAt index: Int) -> String? {
        guard lines.indices.contains(index), !translationLines.isEmpty else { return nil }
        let target = lines[index].time
        if let closest = translationLines.min(by: { abs($0.time - target) < abs($1.time - target) }),
           abs(closest.time - target) <= 1.0,
           !closest.text.isEmpty {
            return closest.text
        }
        return translation(at: target + 0.001)
    }
}

enum SecondRowType: String, CaseIterable, Identifiable {
    case translationOrNext = "显示翻译或下一行歌词"
    case nextOnly = "仅显示下一行歌词"
    case hidden = "隐藏"

    var id: String { rawValue }
}

enum LRCParser {
    private static let timestamp = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )
    private static let enhancedHeader = try! NSRegularExpression(
        pattern: #"^\[(\d+),(\d+)\](.*)$"#
    )
    private static let yrcWord = try! NSRegularExpression(
        pattern: #"\((\d+),(\d+)(?:,\d+)?\)([^\(]*)"#
    )
    private static let qrcWord = try! NSRegularExpression(
        pattern: #"([^\(\)]*)\((\d+),(\d+)(?:,\d+)?\)"#
    )

    static func parse(_ content: String) -> [LyricLine] {
        var result: [LyricLine] = []
        content.enumerateLines { rawLine, _ in
            if let enhanced = parseEnhancedLine(rawLine) {
                result.append(enhanced)
                return
            }
            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            let matches = timestamp.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { return }

            let last = matches[matches.count - 1]
            let textStart = Range(last.range, in: rawLine)!.upperBound
            let text = String(rawLine[textStart...]).trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard
                    let minutesRange = Range(match.range(at: 1), in: rawLine),
                    let secondsRange = Range(match.range(at: 2), in: rawLine),
                    let minutes = Double(rawLine[minutesRange]),
                    let seconds = Double(rawLine[secondsRange])
                else { continue }

                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: rawLine) {
                    let digits = String(rawLine[fractionRange])
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                result.append(LyricLine(time: minutes * 60 + seconds + fraction, text: text))
            }
        }
        return result.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.text < rhs.text : lhs.time < rhs.time
        }
    }

    private static func parseEnhancedLine(_ rawLine: String) -> LyricLine? {
        let fullRange = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
        guard
            let header = enhancedHeader.firstMatch(in: rawLine, range: fullRange),
            let startRange = Range(header.range(at: 1), in: rawLine),
            let durationRange = Range(header.range(at: 2), in: rawLine),
            let bodyRange = Range(header.range(at: 3), in: rawLine),
            let lineStartMS = Double(rawLine[startRange]),
            Double(rawLine[durationRange]) != nil
        else { return nil }

        let body = String(rawLine[bodyRange])
        let words = body.hasPrefix("(") ? parseYRCWords(body) : parseQRCWords(body)
        guard !words.isEmpty else { return nil }
        return LyricLine(time: lineStartMS / 1_000, text: words.map(\.text).joined(), words: words)
    }

    private static func parseYRCWords(_ body: String) -> [LyricWord] {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return yrcWord.matches(in: body, range: range).compactMap { match in
            word(from: match, in: body, startGroup: 1, durationGroup: 2, textGroup: 3)
        }.filter { !$0.text.isEmpty }
    }

    private static func parseQRCWords(_ body: String) -> [LyricWord] {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return qrcWord.matches(in: body, range: range).compactMap { match in
            word(from: match, in: body, startGroup: 2, durationGroup: 3, textGroup: 1)
        }.filter { !$0.text.isEmpty }
    }

    private static func word(
        from match: NSTextCheckingResult,
        in source: String,
        startGroup: Int,
        durationGroup: Int,
        textGroup: Int
    ) -> LyricWord? {
        guard
            let startRange = Range(match.range(at: startGroup), in: source),
            let durationRange = Range(match.range(at: durationGroup), in: source),
            let textRange = Range(match.range(at: textGroup), in: source),
            let start = Double(source[startRange]),
            let duration = Double(source[durationRange])
        else { return nil }
        return LyricWord(
            startTime: start / 1_000,
            duration: max(0, duration / 1_000),
            text: String(source[textRange])
        )
    }
}

struct KaraokeProgressSpan: Equatable, Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let startProgress: Double
    let endProgress: Double
}

struct KaraokeAnimationPlan: Equatable, Sendable {
    let initialProgress: Double
    let duration: TimeInterval
    let keyTimes: [Double]
    let values: [Double]
}

enum KaraokeTimingPlanner {
    static func characterSpans(for words: [LyricWord]) -> [KaraokeProgressSpan] {
        let lengths = words.map { Double(($0.text as NSString).length) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return [] }
        var consumed = 0.0
        return zip(words, lengths).map { word, length in
            defer { consumed += length }
            return KaraokeProgressSpan(
                startTime: word.startTime,
                duration: word.duration,
                startProgress: consumed / total,
                endProgress: (consumed + length) / total
            )
        }
    }

    static func plan(
        spans: [KaraokeProgressSpan],
        at position: TimeInterval,
        lineEnd: TimeInterval
    ) -> KaraokeAnimationPlan? {
        guard !spans.isEmpty, lineEnd > position else { return nil }
        let duration = lineEnd - position
        let ordered = spans.sorted { $0.startTime < $1.startTime }
        var initial = ordered.first?.startProgress ?? 0

        for span in ordered {
            if position < span.startTime { break }
            if position >= span.startTime + span.duration || span.duration <= 0 {
                initial = span.endProgress
            } else {
                let amount = (position - span.startTime) / span.duration
                initial = span.startProgress + (span.endProgress - span.startProgress) * amount
                break
            }
        }

        var points: [(time: TimeInterval, value: Double)] = [(0, initial)]
        for span in ordered {
            let startOffset = span.startTime - position
            let endOffset = span.startTime + span.duration - position
            if startOffset > 0, startOffset < duration {
                points.append((startOffset, span.startProgress))
            }
            if endOffset > 0, endOffset < duration {
                points.append((endOffset, span.endProgress))
            }
        }
        let finalValue = max(initial, ordered.last?.endProgress ?? initial)
        points.append((duration, finalValue))
        points.sort { $0.time < $1.time }

        var compact: [(TimeInterval, Double)] = []
        for point in points {
            if let last = compact.last, abs(last.0 - point.time) < 0.000_001 {
                compact[compact.count - 1] = point
            } else {
                compact.append(point)
            }
        }
        return KaraokeAnimationPlan(
            initialProgress: initial,
            duration: duration,
            keyTimes: compact.map { min(max($0.0 / duration, 0), 1) },
            values: compact.map { min(max($0.1, 0), 1) }
        )
    }
}
