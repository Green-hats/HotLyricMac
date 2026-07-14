import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var synchronizingWindowAndFont = false
    private var userWantsVisible = true
    private var currentHasTrack = false
    private var currentAutoHide = false
    private weak var model: AppModel?
    private weak var preferences: Preferences?
    var managedWindow: NSPanel { panel }

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
        self.currentHasTrack = model.track != nil
        self.currentAutoHide = preferences.autoHideWithoutPlayer
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 780,
                height: LyricWindowLayoutPlanner.windowHeight(
                    forFontSize: preferences.fontSize,
                    secondRowType: preferences.secondRowType
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model, preferences: preferences))
        panel.isReleasedWhenClosed = false
        updateSizeLimits(for: preferences.secondRowType)

        if let savedFrame = UserDefaults.standard.string(forKey: "overlayFrame") {
            panel.setFrame(from: savedFrame)
        } else if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - panel.frame.width / 2
            let y = screen.visibleFrame.minY + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        ensureWindowIsVisible()

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak panel] _ in
                guard let panel else { return }
                UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "overlayFrame")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self, weak preferences] _ in
                guard let self, let preferences, !self.synchronizingWindowAndFont else { return }
                UserDefaults.standard.set(NSStringFromRect(self.panel.frame), forKey: "overlayFrame")
                let plannedFont = LyricWindowLayoutPlanner.fontSize(
                    forWindowHeight: self.panel.frame.height,
                    secondRowType: preferences.secondRowType
                )
                if abs(preferences.fontSize - plannedFont) >= 0.1 {
                    self.synchronizingWindowAndFont = true
                    preferences.fontSize = plannedFont
                    self.synchronizingWindowAndFont = false
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.ensureWindowIsVisible() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.ensureWindowIsVisible() }
            .store(in: &cancellables)

        preferences.$locked
            .sink { [weak panel] locked in panel?.ignoresMouseEvents = locked }
            .store(in: &cancellables)

        preferences.$secondRowType
            .sink { [weak self, weak preferences] type in
                guard let self, let preferences else { return }
                self.updateSizeLimits(for: type)
                self.resizePanel(forFontSize: preferences.fontSize, secondRowType: type, animate: true)
            }
            .store(in: &cancellables)

        preferences.$fontSize
            .dropFirst()
            .sink { [weak self, weak preferences] fontSize in
                guard let self, let preferences, !self.synchronizingWindowAndFont else { return }
                self.resizePanel(forFontSize: fontSize, secondRowType: preferences.secondRowType, animate: false)
            }
            .store(in: &cancellables)

        model.$track.combineLatest(preferences.$autoHideWithoutPlayer)
            .sink { [weak self] track, autoHide in
                self?.currentHasTrack = track != nil
                self?.currentAutoHide = autoHide
                self?.updateVisibility()
            }
            .store(in: &cancellables)
    }

    func show() {
        userWantsVisible = true
        updateVisibility()
    }

    func toggleVisibility() {
        userWantsVisible.toggle()
        updateVisibility()
    }

    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.minY + 100
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updateSizeLimits(for type: SecondRowType) {
        panel.minSize = NSSize(
            width: 360,
            height: LyricWindowLayoutPlanner.windowHeight(forFontSize: 20, secondRowType: type)
        )
        panel.maxSize = NSSize(
            width: 2400,
            height: LyricWindowLayoutPlanner.windowHeight(forFontSize: 64, secondRowType: type)
        )
    }

    private func resizePanel(forFontSize fontSize: Double, secondRowType: SecondRowType, animate: Bool) {
        let newHeight = LyricWindowLayoutPlanner.windowHeight(forFontSize: fontSize, secondRowType: secondRowType)
        guard abs(panel.frame.height - newHeight) >= 0.5 else { return }
        synchronizingWindowAndFont = true
        var frame = panel.frame
        // Keep the top edge fixed, matching HotLyric's desktop-lyric resize behavior.
        frame.origin.y -= newHeight - frame.height
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: animate)
        synchronizingWindowAndFont = false
    }

    private func ensureWindowIsVisible() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else { return }
        let adjusted = WindowPlacementPlanner.adjustedFrame(panel.frame, visibleFrames: screens)
        if adjusted != panel.frame { panel.setFrame(adjusted, display: true) }
    }

    private func updateVisibility() {
        let shouldShow = userWantsVisible && !(currentAutoHide && !currentHasTrack)
        if shouldShow { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        model?.updateLyricWindowVisibility(shouldShow)
    }
}

enum LyricWindowLayoutPlanner {
    static func windowHeight(forFontSize fontSize: Double, secondRowType: SecondRowType) -> Double {
        let clamped = min(max(fontSize, 20), 64)
        if secondRowType == .hidden {
            return clamped * 1.55 + 35
        }
        return clamped * 2.8 + 36
    }

    static func fontSize(forWindowHeight height: Double, secondRowType: SecondRowType) -> Double {
        let raw = secondRowType == .hidden ? (height - 35) / 1.55 : (height - 36) / 2.8
        return (min(max(raw, 20), 64) * 10).rounded() / 10
    }
}

enum WindowPlacementPlanner {
    static func adjustedFrame(_ input: NSRect, visibleFrames: [NSRect]) -> NSRect {
        guard let first = visibleFrames.first else { return input }
        let target = visibleFrames.max { intersectionArea(input, $0) < intersectionArea(input, $1) } ?? first
        var frame = input
        frame.size.width = min(frame.width, target.width)
        frame.size.height = min(frame.height, target.height)
        frame.origin.x = min(max(frame.minX, target.minX), target.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, target.minY), target.maxY - frame.height)
        return frame
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> Double {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

private struct OverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LyricTheme.color(preferences.theme.background).opacity(hovering && !preferences.locked ? 0.82 : 0.001))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LyricTheme.color(preferences.theme.border).opacity(hovering && !preferences.locked ? 1 : 0), lineWidth: 1)
                }

            VStack(spacing: 5) {
                KaraokeTextView(
                    text: model.currentLine,
                    fontSize: preferences.fontSize,
                    fontFamily: preferences.fontFamily,
                    fontWeight: preferences.fontWeight,
                    theme: preferences.theme,
                    progress: model.lyricProgress,
                    remainingDuration: model.currentLineRemainingDuration,
                    wordTimings: model.currentWordTimings,
                    playbackPosition: model.lyricPlaybackPosition,
                    isPlaying: model.track?.isPlaying == true,
                    synchronizationToken: model.playbackRevision
                )
                .frame(maxWidth: .infinity)
                .frame(height: preferences.fontSize * 1.55)

                if preferences.secondRowType != .hidden, let secondary = model.secondaryLine {
                    Text(secondary)
                        .font(secondaryFont)
                        .foregroundStyle(LyricTheme.color(preferences.theme.lyric).opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black, radius: 3, y: 1)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)

            if hovering && !preferences.locked {
                HStack(spacing: 14) {
                    Button(action: model.previousTrack) { Image(systemName: "backward.fill") }
                    Button(action: model.togglePlayPause) {
                        Image(systemName: model.track?.isPlaying == true ? "pause.fill" : "play.fill")
                    }
                    Button(action: model.nextTrack) { Image(systemName: "forward.fill") }
                    Button(action: model.reloadLyrics) { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    Text(model.track.map { "\($0.title) · \($0.artist)" } ?? "未连接播放器")
                        .lineLimit(1)
                    Spacer()
                    Button { preferences.locked = true } label: { Image(systemName: "lock.open.fill") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 7)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var secondaryFont: Font {
        let size = preferences.fontSize * 0.55
        if preferences.fontFamily == "系统默认" {
            return .system(size: size, weight: preferences.fontWeight.swiftUIWeight, design: .rounded)
        }
        return .custom(preferences.fontFamily, size: size).weight(preferences.fontWeight.swiftUIWeight)
    }
}
