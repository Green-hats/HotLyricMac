import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var lyrics = Lyrics.empty
    @Published private(set) var currentIndex: Int?
    @Published private(set) var status = "等待播放器"
    @Published private(set) var playerAccess: [PlayerKind: PlayerAccessState] = [:]
    @Published private(set) var playbackRevision = 0
    @Published private(set) var lyricCandidates: [LyricSearchCandidate] = []
    @Published private(set) var isSearchingLyrics = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var isLyricWindowVisible = true
    @Published private(set) var hotKeyStatus = "已启用"
    @Published private(set) var cacheStatistics = LyricCacheStatistics.empty

    let preferences: Preferences
    private let playerService = PlayerService()
    private let lyricService: LyricService
    private var pollTimer: Timer?
    private var lyricTask: Task<Void, Never>?
    private var lastIdentity = ""
    private var sampleDate = Date()
    private var isRefreshing = false
    private var lineBoundaryTimer: Timer?

    init(
        preferences: Preferences,
        lyricService: LyricService = LyricService(),
        automaticallyMaintainsCache: Bool = true
    ) {
        self.preferences = preferences
        self.lyricService = lyricService
        schedulePoll(after: 0.05)
        if automaticallyMaintainsCache {
            Task { [weak self] in
                guard let self else { return }
                cacheStatistics = await lyricService.maintainCache()
            }
        }
    }

    var currentLine: String {
        guard let currentIndex, lyrics.lines.indices.contains(currentIndex), !lyrics.lines[currentIndex].text.isEmpty else {
            return track?.title ?? "打开 Apple Music 或 Spotify 开始播放"
        }
        return lyrics.lines[currentIndex].text
    }

    var nextLine: String? {
        guard let currentIndex else { return lyrics.lines.first?.text }
        let next = currentIndex + 1
        return lyrics.lines.indices.contains(next) ? lyrics.lines[next].text : nil
    }

    var secondaryLine: String? {
        guard preferences.secondRowType != .hidden else { return nil }
        guard let currentIndex, lyrics.lines.indices.contains(currentIndex), !lyrics.lines[currentIndex].text.isEmpty else {
            if let track { return TrackDisplayFormatter.metadataLine(for: track, status: status) }
            return "Apple Music · Spotify · 等待播放"
        }
        if preferences.secondRowType == .translationOrNext,
           let translation = lyrics.translation(forOriginalLineAt: currentIndex) {
            return translation
        }
        return nextLine
    }

    var lyricProgress: Double { lyricProgress(at: Date()) }

    var currentWordTimings: [LyricWord] {
        guard let currentIndex, lyrics.lines.indices.contains(currentIndex) else { return [] }
        return lyrics.lines[currentIndex].words
    }

    var lyricPlaybackPosition: TimeInterval {
        estimatedPosition() + preferences.lyricOffset
    }

    func estimatedPosition(at date: Date = Date()) -> TimeInterval {
        guard let track else { return 0 }
        let elapsed = track.isPlaying ? max(0, date.timeIntervalSince(sampleDate)) : 0
        return min(max(track.position + elapsed, 0), track.duration > 0 ? track.duration : .greatestFiniteMagnitude)
    }

    func lyricProgress(at date: Date) -> Double {
        guard let currentIndex, lyrics.lines.indices.contains(currentIndex) else { return 0 }
        let start = lyrics.lines[currentIndex].time
        let end = lyrics.lines.indices.contains(currentIndex + 1) ? lyrics.lines[currentIndex + 1].time : (track?.duration ?? start)
        guard end > start else { return 0 }
        return min(max((estimatedPosition(at: date) + preferences.lyricOffset - start) / (end - start), 0), 1)
    }

    var currentLineRemainingDuration: TimeInterval {
        guard let currentIndex, lyrics.lines.indices.contains(currentIndex) else { return 0 }
        let end = lyrics.lines.indices.contains(currentIndex + 1) ? lyrics.lines[currentIndex + 1].time : (track?.duration ?? 0)
        return max(0, end - estimatedPosition() - preferences.lyricOffset)
    }

    func togglePlayPause() {
        guard let track else { return }
        Task { [weak self] in
            guard let self else { return }
            await playerService.togglePlayPause(for: track.player)
            refresh()
        }
    }

    func nextTrack() {
        guard let track else { return }
        Task { await playerService.next(for: track.player) }
    }

    func previousTrack() {
        guard let track else { return }
        Task { await playerService.previous(for: track.player) }
    }

    func reloadLyrics() {
        guard let track else { return }
        lyricTask?.cancel()
        status = "正在重新匹配歌词…"
        Task { [weak self] in
            guard let self else { return }
            await lyricService.removeCachedLyrics(for: track)
            guard self.track?.identity == track.identity else { return }
            self.lastIdentity = ""
            self.loadLyrics(for: track)
        }
    }

    func clearCache() {
        let currentTrack = track
        Task { [weak self] in
            guard let self else { return }
            await lyricService.clearCache()
            cacheStatistics = .empty
            operationMessage = "已清空全部歌词缓存"
            guard let currentTrack, self.track?.identity == currentTrack.identity else { return }
            self.lastIdentity = ""
            self.loadLyrics(for: currentTrack)
        }
    }

    func cleanExpiredCache() {
        Task { [weak self] in
            guard let self else { return }
            let before = await lyricService.cacheStatistics()
            let after = await lyricService.maintainCache()
            cacheStatistics = after
            let removed = max(0, before.entryCount - after.entryCount)
            operationMessage = removed == 0 ? "缓存已经符合清理策略" : "已清理 \(removed) 首过期或超限缓存"
        }
    }

    func searchLyricsManually() {
        guard let track, !isSearchingLyrics else { return }
        isSearchingLyrics = true
        lyricCandidates = []
        Task { [weak self] in
            guard let self else { return }
            let candidates = await lyricService.search(for: track)
            isSearchingLyrics = false
            guard self.track?.identity == track.identity else { return }
            lyricCandidates = candidates
        }
    }

    func selectLyric(_ candidate: LyricSearchCandidate) {
        guard let track else { return }
        isSearchingLyrics = true
        Task { [weak self] in
            guard let self else { return }
            let selected = await lyricService.lyrics(for: candidate, track: track)
            isSearchingLyrics = false
            guard self.track?.identity == track.identity else { return }
            if let selected {
                lyrics = selected
                status = ""
                currentIndex = selected.lineIndex(at: estimatedPosition(), offset: preferences.lyricOffset)
                playbackRevision &+= 1
                scheduleNextLineBoundary()
                lyricCandidates = []
                cacheStatistics = await lyricService.cacheStatistics()
            } else {
                status = "所选歌曲没有逐行歌词"
            }
        }
    }

    func importLocalLyric() {
        guard let track else { return }
        let panel = NSOpenPanel()
        panel.title = "选择当前歌曲的 LRC 歌词"
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [weak self] in
            guard let self else { return }
            let imported = await lyricService.importLocalLyric(from: url, for: track)
            guard self.track?.identity == track.identity else { return }
            if let imported {
                lyrics = imported
                currentIndex = imported.lineIndex(at: estimatedPosition(), offset: preferences.lyricOffset)
                playbackRevision &+= 1
                operationMessage = "已导入 \(url.lastPathComponent)"
                scheduleNextLineBoundary()
                cacheStatistics = await lyricService.cacheStatistics()
            } else {
                operationMessage = "无法读取该文件，或文件中没有有效时间轴歌词"
            }
        }
    }

    var automationPermissionDenied: Bool {
        playerAccess.values.contains(.permissionDenied)
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func updateLyricWindowVisibility(_ visible: Bool) { isLyricWindowVisible = visible }
    func updateHotKeyStatus(_ value: String) { hotKeyStatus = value }

    private func refresh() {
        guard !isRefreshing else { return }
        pollTimer?.invalidate()
        isRefreshing = true
        let preferred = preferences.playerPriority
        let forced = preferences.playerSelectionMode.forcedPlayer
        Task { [weak self] in
            guard let self else { return }
            let result = await playerService.currentTrack(preferred: preferred, forced: forced)
            applyPlayerSample(result)
        }
    }

    private func applyPlayerSample(_ result: PlayerPollResult) {
        isRefreshing = false
        playerAccess = result.access
        let newTrack = result.track
        let oldTrack = track
        let predictedPosition = estimatedPosition()
        if let oldTrack, let newTrack {
            let identityChanged = oldTrack.identity != newTrack.identity
            let stateChanged = oldTrack.isPlaying != newTrack.isPlaying
            let seeked = !identityChanged && abs(newTrack.position - predictedPosition) > 1.25
            if identityChanged || stateChanged || seeked { playbackRevision &+= 1 }
        } else if (oldTrack == nil) != (newTrack == nil) {
            playbackRevision &+= 1
        }
        sampleDate = Date()
        track = newTrack
        guard let newTrack else {
            lineBoundaryTimer?.invalidate()
            currentIndex = nil
            status = automationPermissionDenied ? "需要播放器自动化权限" : "等待播放器"
            scheduleNextPoll()
            return
        }
        if newTrack.identity != lastIdentity {
            lyricCandidates = []
            loadLyrics(for: newTrack)
        }
        currentIndex = lyrics.lineIndex(at: newTrack.position, offset: preferences.lyricOffset)
        scheduleNextLineBoundary()
        scheduleNextPoll()
    }

    private func loadLyrics(for track: Track) {
        lastIdentity = track.identity
        lyrics = .empty
        currentIndex = nil
        status = "正在匹配歌词…"
        lyricTask?.cancel()
        lyricTask = Task { [weak self] in
            guard let self else { return }
            let defaultProvider = AppConfiguration.current.options(for: track.player)?.defaultLrcProvider ?? "NetEase"
            let result = await lyricService.lyrics(for: track, defaultProvider: defaultProvider)
            let statistics = await lyricService.cacheStatistics()
            guard !Task.isCancelled, self.track?.identity == track.identity else { return }
            self.lyrics = result
            self.status = result.lines.isEmpty ? "未找到逐行歌词" : ""
            self.currentIndex = result.lineIndex(at: self.track?.position ?? 0, offset: self.preferences.lyricOffset)
            self.cacheStatistics = statistics
            self.scheduleNextLineBoundary()
        }
    }

    private func scheduleNextLineBoundary() {
        lineBoundaryTimer?.invalidate()
        guard track?.isPlaying == true, !lyrics.lines.isEmpty else { return }
        let position = estimatedPosition() + preferences.lyricOffset
        let nextIndex = (lyrics.lineIndex(at: position) ?? -1) + 1
        guard lyrics.lines.indices.contains(nextIndex) else { return }
        let delay = max(0.01, lyrics.lines[nextIndex].time - position)
        lineBoundaryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentIndex = lyrics.lineIndex(at: estimatedPosition(), offset: preferences.lyricOffset)
                scheduleNextLineBoundary()
            }
        }
    }

    private func scheduleNextPoll() {
        let interval = PollingIntervalPlanner.interval(
            hasTrack: track != nil,
            isPlaying: track?.isPlaying == true,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        schedulePoll(after: interval)
    }

    private func schedulePoll(after interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
}

enum PollingIntervalPlanner {
    static func interval(hasTrack: Bool, isPlaying: Bool, lowPowerMode: Bool) -> TimeInterval {
        if !hasTrack { return lowPowerMode ? 3.0 : 2.0 }
        if isPlaying { return lowPowerMode ? 1.0 : 0.5 }
        return lowPowerMode ? 2.0 : 1.0
    }
}
