import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    let resetPosition: () -> Void

    var body: some View {
        Form {
            Section("播放器") {
                Picker("优先读取", selection: $preferences.playerPriority) {
                    ForEach(PlayerKind.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("播放器绑定", selection: $preferences.playerSelectionMode) {
                    ForEach(PlayerSelectionMode.allCases) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("当前歌曲", value: currentSongText)
                if let track = model.track {
                    LabeledContent("播放状态", value: TrackDisplayFormatter.playbackLine(for: track, lyricSource: ""))
                }
                LabeledContent("歌词来源") {
                    if model.lyrics.source.isEmpty {
                        Text("—")
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.lyrics.matchedTitle ?? model.track?.title ?? "未知歌曲")
                                .lineLimit(1)
                            Text("\(matchedLyricArtists) · \(model.lyrics.source)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                if model.automationPermissionDenied {
                    HStack {
                        Label("没有读取播放器的自动化权限", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("打开系统设置", action: model.openAutomationSettings)
                    }
                }
            }

            Section("桌面歌词") {
                Picker("歌词主题", selection: $preferences.themeName) {
                    ForEach(LyricTheme.presets) { Text($0.name).tag($0.name) }
                    Text("自定义").tag("自定义")
                }
                if preferences.themeName == "自定义" {
                    HStack {
                        ColorPicker("原文", selection: colorBinding(\.customLyric), supportsOpacity: true)
                        ColorPicker("高亮", selection: colorBinding(\.customKaraoke), supportsOpacity: true)
                        ColorPicker("背景", selection: colorBinding(\.customBackground), supportsOpacity: true)
                    }
                    HStack {
                        ColorPicker("原文描边", selection: colorBinding(\.customLyricStroke), supportsOpacity: true)
                        ColorPicker("高亮描边", selection: colorBinding(\.customKaraokeStroke), supportsOpacity: true)
                        ColorPicker("边框", selection: colorBinding(\.customBorder), supportsOpacity: true)
                    }
                }
                Picker("字体", selection: $preferences.fontFamily) {
                    ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Picker("字重", selection: $preferences.fontWeight) {
                    ForEach(LyricFontWeight.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("字号")
                    Slider(value: $preferences.fontSize, in: 20...64, step: 1)
                    Text("\(Int(preferences.fontSize))")
                        .monospacedDigit()
                        .frame(width: 28)
                }
                Picker("第二行", selection: $preferences.secondRowType) {
                    ForEach(SecondRowType.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("锁定歌词（鼠标穿透）", isOn: $preferences.locked)
                HStack {
                    Text("时间偏移")
                    Slider(value: $preferences.lyricOffset, in: -5...5, step: 0.1)
                    Text(String(format: "%+.1f 秒", preferences.lyricOffset))
                        .monospacedDigit()
                        .frame(width: 66)
                }
            }

            Section("系统") {
                Toggle("登录时启动", isOn: $preferences.launchAtLogin)
                    .onAppear(perform: preferences.refreshLaunchAtLoginStatus)
                if let error = preferences.launchAtLoginError {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("登录项设置", action: preferences.openLoginItemSettings)
                    }
                }
                Toggle("没有播放器时自动隐藏歌词", isOn: $preferences.autoHideWithoutPlayer)
            }

            Section("全局快捷键") {
                LabeledContent("播放/暂停", value: "⌥⌘Space")
                LabeledContent("上一首 / 下一首", value: "⌥⌘←  /  ⌥⌘→")
                LabeledContent("锁定歌词", value: "⌥⌘L")
                LabeledContent("显示/隐藏歌词", value: "⌥⌘H")
                if model.hotKeyStatus != "已启用" {
                    Text(model.hotKeyStatus).font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Button("重新匹配歌词", action: model.reloadLyrics)
                    Button("手动选择歌词", action: model.searchLyricsManually)
                        .disabled(model.track == nil || model.isSearchingLyrics)
                    Button("导入 LRC…", action: model.importLocalLyric)
                        .disabled(model.track == nil)
                    Button("重置窗口位置", action: resetPosition)
                }
                HStack {
                    Label(
                        "缓存 \(model.cacheStatistics.entryCount) 首 · \(model.cacheStatistics.formattedSize)",
                        systemImage: "internaldrive"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("清理过期缓存", action: model.cleanExpiredCache)
                    Button("清空全部缓存", role: .destructive, action: model.clearCache)
                }
                Text("自动保留 90 天，最多 2,000 首或 100 MB；启动及写入新缓存时会自动清理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.isSearchingLyrics {
                    HStack { ProgressView(); Text("正在搜索网易云和 QQ 音乐…") }
                }
                if !model.lyricCandidates.isEmpty {
                    DisclosureGroup("搜索结果（选择后会记住该歌曲）") {
                        ForEach(model.lyricCandidates) { candidate in
                            Button {
                                model.selectLyric(candidate)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                    Text(candidate.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
                if let message = model.operationMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("使用提示") {
                Text("首次读取播放器时，请在 macOS 的自动化权限提示中选择允许。锁定后可从菜单栏的“热词”图标解除。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 620)
    }

    private var fontFamilies: [String] {
        ["系统默认"] + NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var currentSongText: String {
        guard let track = model.track else { return "未检测到" }
        return track.artist.isEmpty ? track.title : "\(track.title) - \(track.artist)"
    }

    private var matchedLyricArtists: String {
        let value = model.lyrics.matchedArtists.joined(separator: ", ")
        if !value.isEmpty { return value }
        return model.track?.artist.isEmpty == false ? model.track!.artist : "未知歌手"
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, String>) -> Binding<Color> {
        Binding(
            get: { LyricTheme.color(preferences[keyPath: keyPath]) },
            set: { preferences[keyPath: keyPath] = LyricTheme.argb($0) }
        )
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel, preferences: Preferences, resetPosition: @escaping () -> Void) {
        let content = SettingsView(model: model, preferences: preferences, resetPosition: resetPosition)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "热词设置"
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppWindowCoordinator {
    let overlay: OverlayWindowController
    let settings: SettingsWindowController
    let hotKeys: GlobalHotKeyManager

    init(model: AppModel, preferences: Preferences) {
        let overlay = OverlayWindowController(model: model, preferences: preferences)
        self.overlay = overlay
        settings = SettingsWindowController(model: model, preferences: preferences) { [weak overlay] in
            overlay?.resetPosition()
        }
        hotKeys = GlobalHotKeyManager(actions: [
            .playPause: { [weak model] in model?.togglePlayPause() },
            .previous: { [weak model] in model?.previousTrack() },
            .next: { [weak model] in model?.nextTrack() },
            .toggleLock: { [weak preferences] in preferences?.locked.toggle() },
            .toggleVisibility: { [weak overlay] in overlay?.toggleVisibility() }
        ])
        if !hotKeys.errors.isEmpty { model.updateHotKeyStatus(hotKeys.errors.joined(separator: "；")) }
        overlay.show()
    }

    func showSettings() { settings.present() }
    func toggleOverlay() { overlay.toggleVisibility() }
}
