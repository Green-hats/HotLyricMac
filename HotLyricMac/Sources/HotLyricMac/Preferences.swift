import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let fontSize = "fontSize"
        static let secondRowType = "secondRowType"
        static let locked = "locked"
        static let lyricOffset = "lyricOffset"
        static let playerPriority = "playerPriority"
        static let playerSelectionMode = "playerSelectionMode"
        static let themeName = "themeName"
        static let fontFamily = "fontFamily"
        static let fontWeight = "fontWeight"
        static let customBorder = "customBorder"
        static let customBackground = "customBackground"
        static let customLyric = "customLyric"
        static let customKaraoke = "customKaraoke"
        static let customLyricStroke = "customLyricStroke"
        static let customKaraokeStroke = "customKaraokeStroke"
        static let autoHideWithoutPlayer = "autoHideWithoutPlayer"
        static let launchAtLogin = "launchAtLogin"
    }

    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }
    @Published var secondRowType: SecondRowType {
        didSet { defaults.set(secondRowType.rawValue, forKey: Key.secondRowType) }
    }
    @Published var locked: Bool { didSet { defaults.set(locked, forKey: Key.locked) } }
    @Published var lyricOffset: Double { didSet { defaults.set(lyricOffset, forKey: Key.lyricOffset) } }
    @Published var playerPriority: PlayerKind {
        didSet { defaults.set(playerPriority.rawValue, forKey: Key.playerPriority) }
    }
    @Published var playerSelectionMode: PlayerSelectionMode {
        didSet { defaults.set(playerSelectionMode.rawValue, forKey: Key.playerSelectionMode) }
    }
    @Published var themeName: String { didSet { defaults.set(themeName, forKey: Key.themeName) } }
    @Published var fontFamily: String { didSet { defaults.set(fontFamily, forKey: Key.fontFamily) } }
    @Published var fontWeight: LyricFontWeight { didSet { defaults.set(fontWeight.rawValue, forKey: Key.fontWeight) } }
    @Published var customBorder: String { didSet { defaults.set(customBorder, forKey: Key.customBorder) } }
    @Published var customBackground: String { didSet { defaults.set(customBackground, forKey: Key.customBackground) } }
    @Published var customLyric: String { didSet { defaults.set(customLyric, forKey: Key.customLyric) } }
    @Published var customKaraoke: String { didSet { defaults.set(customKaraoke, forKey: Key.customKaraoke) } }
    @Published var customLyricStroke: String { didSet { defaults.set(customLyricStroke, forKey: Key.customLyricStroke) } }
    @Published var customKaraokeStroke: String { didSet { defaults.set(customKaraokeStroke, forKey: Key.customKaraokeStroke) } }
    @Published var autoHideWithoutPlayer: Bool { didSet { defaults.set(autoHideWithoutPlayer, forKey: Key.autoHideWithoutPlayer) } }
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }
    @Published private(set) var launchAtLoginError: String?
    private var synchronizingLaunchAtLogin = false

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Key.fontSize: 34.0,
            Key.secondRowType: SecondRowType.translationOrNext.rawValue,
            Key.locked: false,
            Key.lyricOffset: 0.0,
            Key.playerPriority: PlayerKind.appleMusic.rawValue,
            Key.playerSelectionMode: PlayerSelectionMode.automatic.rawValue,
            Key.themeName: "默认",
            Key.fontFamily: "系统默认",
            Key.fontWeight: LyricFontWeight.semibold.rawValue,
            Key.customBorder: "#548F8F8F",
            Key.customBackground: "#FF2C2C2C",
            Key.customLyric: "#FFFFFFFF",
            Key.customKaraoke: "#FFFFA04D",
            Key.customLyricStroke: "#FF000000",
            Key.customKaraokeStroke: "#FF000000",
            Key.autoHideWithoutPlayer: false
        ])
        fontSize = defaults.double(forKey: Key.fontSize)
        secondRowType = SecondRowType(rawValue: defaults.string(forKey: Key.secondRowType) ?? "") ?? .translationOrNext
        locked = defaults.bool(forKey: Key.locked)
        lyricOffset = defaults.double(forKey: Key.lyricOffset)
        playerPriority = PlayerKind(rawValue: defaults.string(forKey: Key.playerPriority) ?? "") ?? .appleMusic
        playerSelectionMode = PlayerSelectionMode(rawValue: defaults.string(forKey: Key.playerSelectionMode) ?? "") ?? .automatic
        themeName = defaults.string(forKey: Key.themeName) ?? "默认"
        fontFamily = defaults.string(forKey: Key.fontFamily) ?? "系统默认"
        fontWeight = LyricFontWeight(rawValue: defaults.string(forKey: Key.fontWeight) ?? "") ?? .semibold
        customBorder = defaults.string(forKey: Key.customBorder) ?? "#548F8F8F"
        customBackground = defaults.string(forKey: Key.customBackground) ?? "#FF2C2C2C"
        customLyric = defaults.string(forKey: Key.customLyric) ?? "#FFFFFFFF"
        customKaraoke = defaults.string(forKey: Key.customKaraoke) ?? "#FFFFA04D"
        customLyricStroke = defaults.string(forKey: Key.customLyricStroke) ?? "#FF000000"
        customKaraokeStroke = defaults.string(forKey: Key.customKaraokeStroke) ?? "#FF000000"
        autoHideWithoutPlayer = defaults.bool(forKey: Key.autoHideWithoutPlayer)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
    }

    var theme: LyricTheme {
        if themeName == "自定义" {
            return .custom(
                border: customBorder,
                background: customBackground,
                lyric: customLyric,
                karaoke: customKaraoke,
                lyricStroke: customLyricStroke,
                karaokeStroke: customKaraokeStroke
            )
        }
        return .named(themeName)
    }

    func refreshLaunchAtLoginStatus() {
        synchronizingLaunchAtLogin = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        synchronizingLaunchAtLogin = false
    }

    func openLoginItemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateLaunchAtLogin() {
        guard !synchronizingLaunchAtLogin else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            refreshLaunchAtLoginStatus()
        }
    }
}
