import AppKit
import SwiftUI

@main
struct HotLyricMacApp: App {
    @StateObject private var preferences: Preferences
    @StateObject private var model: AppModel
    private let windows: AppWindowCoordinator

    init() {
        let preferences = Preferences()
        let model = AppModel(preferences: preferences)
        _preferences = StateObject(wrappedValue: preferences)
        _model = StateObject(wrappedValue: model)
        windows = AppWindowCoordinator(model: model, preferences: preferences)
    }

    var body: some Scene {
        MenuBarExtra("热词", systemImage: preferences.locked ? "lock.fill" : "music.note") {
            VStack(alignment: .leading, spacing: 3) {
                if let track = model.track {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist.isEmpty ? "未知歌手" : track.artist)
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: model.estimatedPosition(), total: max(track.duration, 1))
                    Text(TrackDisplayFormatter.playbackLine(for: track, lyricSource: model.lyrics.source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("未检测到正在播放的歌曲").font(.headline)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 300, alignment: .leading)

            Divider()
            Button(model.track?.isPlaying == true ? "暂停" : "播放", action: model.togglePlayPause)
                .keyboardShortcut(.space, modifiers: [])
            Button("上一首", action: model.previousTrack)
            Button("下一首", action: model.nextTrack)
            Button("重新匹配歌词", action: model.reloadLyrics)
            Divider()
            Menu("播放器绑定") {
                ForEach(PlayerSelectionMode.allCases) { mode in
                    Button {
                        preferences.playerSelectionMode = mode
                    } label: {
                        if preferences.playerSelectionMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            }
            Button(model.isLyricWindowVisible ? "隐藏歌词窗口" : "显示歌词窗口", action: windows.toggleOverlay)
            Toggle("锁定歌词", isOn: $preferences.locked)
            Button("设置…", action: windows.showSettings)
            Divider()
            Button("退出热词") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
