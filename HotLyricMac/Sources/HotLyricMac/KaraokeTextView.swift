import AppKit
import QuartzCore
import SwiftUI

struct KaraokeTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let fontFamily: String
    let fontWeight: LyricFontWeight
    let theme: LyricTheme
    let progress: Double
    let remainingDuration: TimeInterval
    let wordTimings: [LyricWord]
    let playbackPosition: TimeInterval
    let isPlaying: Bool
    let synchronizationToken: Int

    func makeNSView(context: Context) -> KaraokeLayerView { KaraokeLayerView() }

    func updateNSView(_ view: KaraokeLayerView, context: Context) {
        view.update(
            text: text,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            theme: theme,
            progress: progress,
            remainingDuration: remainingDuration,
            wordTimings: wordTimings,
            playbackPosition: playbackPosition,
            isPlaying: isPlaying,
            synchronizationToken: synchronizationToken
        )
    }
}

final class KaraokeLayerView: NSView {
    private let textContainer = CALayer()
    private let normalLayer = CATextLayer()
    private let karaokeLayer = CATextLayer()
    private let progressMask = CALayer()
    private var renderedTextWidth = 0.0
    private var glyphTextWidth = 0.0
    private var wordProgressSpans: [KaraokeProgressSpan] = []
    private var state: State?

    private struct State {
        let text: String
        let fontSize: Double
        let fontFamily: String
        let fontWeight: LyricFontWeight
        let theme: LyricTheme
        let themeSignature: String
        let progress: Double
        let remainingDuration: TimeInterval
        let wordTimings: [LyricWord]
        let playbackPosition: TimeInterval
        let isPlaying: Bool
        let synchronizationToken: Int
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textContainer.masksToBounds = true
        layer?.addSublayer(textContainer)
        for textLayer in [normalLayer, karaokeLayer] {
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            textLayer.alignmentMode = .center
            textLayer.isWrapped = false
            textLayer.shadowColor = NSColor.black.cgColor
            textLayer.shadowOpacity = 0.72
            textLayer.shadowRadius = 4
            textLayer.shadowOffset = CGSize(width: 0, height: -1)
            textContainer.addSublayer(textLayer)
        }
        progressMask.backgroundColor = NSColor.white.cgColor
        progressMask.anchorPoint = CGPoint(x: 0, y: 0.5)
        karaokeLayer.mask = progressMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        textContainer.frame = bounds
        guard let state else { return }
        updateText(state)
        updateAnimations(state, continueFromPresentation: false)
    }

    func update(
        text: String,
        fontSize: Double,
        fontFamily: String,
        fontWeight: LyricFontWeight,
        theme: LyricTheme,
        progress: Double,
        remainingDuration: TimeInterval,
        wordTimings: [LyricWord],
        playbackPosition: TimeInterval,
        isPlaying: Bool,
        synchronizationToken: Int
    ) {
        let newState = State(
            text: text,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            theme: theme,
            themeSignature: [theme.border, theme.background, theme.lyric, theme.karaoke, theme.lyricStroke, theme.karaokeStroke].joined(),
            progress: min(max(progress, 0), 1),
            remainingDuration: remainingDuration,
            wordTimings: wordTimings,
            playbackPosition: playbackPosition,
            isPlaying: isPlaying,
            synchronizationToken: synchronizationToken
        )
        let textChanged = state?.text != text || state?.fontSize != fontSize || state?.fontFamily != fontFamily || state?.fontWeight != fontWeight || state?.themeSignature != newState.themeSignature
        let timingChanged = state?.wordTimings != wordTimings
        let clockReset = state?.synchronizationToken != synchronizationToken
        state = newState
        if textChanged || timingChanged { updateText(newState) }
        updateAnimations(newState, continueFromPresentation: !textChanged && !timingChanged && !clockReset)
    }

    private func updateText(_ state: State) {
        let theme = state.theme
        let font = state.fontFamily == "系统默认"
            ? NSFont.systemFont(ofSize: state.fontSize, weight: state.fontWeight.nsWeight)
            : (NSFont(name: state.fontFamily, size: state.fontSize) ?? NSFont.systemFont(ofSize: state.fontSize, weight: state.fontWeight.nsWeight))
        glyphTextWidth = (state.text as NSString).size(withAttributes: [.font: font]).width
        renderedTextWidth = max(bounds.width, glyphTextWidth + 12)
        let textFrame = CGRect(x: 0, y: 0, width: renderedTextWidth, height: bounds.height)
        normalLayer.frame = textFrame
        karaokeLayer.frame = textFrame
        normalLayer.string = attributed(state.text, font: font, fill: LyricTheme.nsColor(theme.lyric), stroke: LyricTheme.nsColor(theme.lyricStroke))
        karaokeLayer.string = attributed(state.text, font: font, fill: LyricTheme.nsColor(theme.karaoke), stroke: LyricTheme.nsColor(theme.karaokeStroke))
        wordProgressSpans = measuredWordSpans(state.wordTimings, font: font)
    }

    private func measuredWordSpans(_ words: [LyricWord], font: NSFont) -> [KaraokeProgressSpan] {
        guard !words.isEmpty, glyphTextWidth > 0 else { return [] }
        var prefix = ""
        return words.map { word in
            let startWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            prefix.append(word.text)
            let endWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            return KaraokeProgressSpan(
                startTime: word.startTime,
                duration: word.duration,
                startProgress: layerProgress(forGlyphProgress: startWidth / glyphTextWidth),
                endProgress: layerProgress(forGlyphProgress: endWidth / glyphTextWidth)
            )
        }
    }

    private func layerProgress(forGlyphProgress progress: Double) -> Double {
        guard renderedTextWidth > 0 else { return 0 }
        let leadingSpace = max(0, (renderedTextWidth - glyphTextWidth) / 2)
        return min(max((leadingSpace + glyphTextWidth * progress) / renderedTextWidth, 0), 1)
    }

    private func attributed(_ text: String, font: NSFont, fill: NSColor, stroke: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: fill,
            .strokeColor: stroke,
            .strokeWidth: -2.0,
            .baselineOffset: max(0, (bounds.height - font.ascender + font.descender) / 2 - font.descender)
        ])
    }

    private func updateAnimations(_ state: State, continueFromPresentation: Bool) {
        guard renderedTextWidth > 0, bounds.width > 0 else { return }
        let progress = state.progress
        let precisePlan = KaraokeTimingPlanner.plan(
            spans: wordProgressSpans,
            at: state.playbackPosition,
            lineEnd: state.playbackPosition + state.remainingDuration
        )
        let currentMaskProgress = precisePlan?.initialProgress ?? layerProgress(forGlyphProgress: progress)
        let finalMaskProgress = precisePlan?.values.last ?? layerProgress(forGlyphProgress: 1)
        let overflow = max(0, renderedTextWidth - bounds.width)
        let currentMaskWidth = progressMask.presentation()?.bounds.width ?? renderedTextWidth * currentMaskProgress
        let currentNormalX = normalLayer.presentation()?.position.x ?? renderedTextWidth / 2 - overflow * progress
        let currentKaraokeX = karaokeLayer.presentation()?.position.x ?? currentNormalX

        progressMask.removeAnimation(forKey: "karaokeProgress")
        normalLayer.removeAnimation(forKey: "lyricScroll")
        karaokeLayer.removeAnimation(forKey: "lyricScroll")

        let pausedOffset = -overflow * progress
        let finalOffset = state.isPlaying ? -overflow : pausedOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressMask.position = CGPoint(x: 0, y: bounds.midY)
        progressMask.bounds = CGRect(
            x: 0,
            y: 0,
            width: renderedTextWidth * (state.isPlaying ? finalMaskProgress : currentMaskProgress),
            height: bounds.height
        )
        normalLayer.position.x = renderedTextWidth / 2 + finalOffset
        karaokeLayer.position.x = renderedTextWidth / 2 + finalOffset
        CATransaction.commit()

        guard state.isPlaying, state.remainingDuration > 0.01, progress < 1 else { return }

        if let precisePlan {
            let maskAnimation = CAKeyframeAnimation(keyPath: "bounds.size.width")
            var values = precisePlan.values.map { renderedTextWidth * $0 }
            if continueFromPresentation, !values.isEmpty { values[0] = currentMaskWidth }
            maskAnimation.values = values
            maskAnimation.keyTimes = precisePlan.keyTimes.map(NSNumber.init(value:))
            maskAnimation.duration = precisePlan.duration
            maskAnimation.calculationMode = .linear
            progressMask.add(maskAnimation, forKey: "karaokeProgress")
        } else {
            let maskAnimation = CABasicAnimation(keyPath: "bounds.size.width")
            maskAnimation.fromValue = continueFromPresentation ? currentMaskWidth : renderedTextWidth * currentMaskProgress
            maskAnimation.toValue = renderedTextWidth * finalMaskProgress
            maskAnimation.duration = state.remainingDuration
            maskAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
            progressMask.add(maskAnimation, forKey: "karaokeProgress")
        }

        if overflow > 0 {
            let scrollAnimation = CABasicAnimation(keyPath: "position.x")
            scrollAnimation.fromValue = continueFromPresentation ? currentNormalX : renderedTextWidth / 2 + pausedOffset
            scrollAnimation.toValue = renderedTextWidth / 2 - overflow
            scrollAnimation.duration = state.remainingDuration
            scrollAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
            normalLayer.add(scrollAnimation, forKey: "lyricScroll")

            let karaokeScroll = scrollAnimation.copy() as! CABasicAnimation
            karaokeScroll.fromValue = continueFromPresentation ? currentKaraokeX : renderedTextWidth / 2 + pausedOffset
            karaokeLayer.add(karaokeScroll, forKey: "lyricScroll")
        }
    }
}
