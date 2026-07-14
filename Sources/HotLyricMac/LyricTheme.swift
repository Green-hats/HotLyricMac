import SwiftUI
import AppKit

struct LyricTheme: Identifiable {
    let name: String
    let border: String
    let background: String
    let lyric: String
    let karaoke: String
    let lyricStroke: String
    let karaokeStroke: String

    var id: String { name }

    static let presets: [LyricTheme] = [
        .init(name: "默认", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FFFFA04D", lyricStroke: "#FF000000", karaokeStroke: "#FF000000"),
        .init(name: "黑红", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FFFFD5D7", lyricStroke: "#FF000000", karaokeStroke: "#FFEF0B08"),
        .init(name: "粉紫", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FFFFD2E9", lyricStroke: "#FFFB71D1", karaokeStroke: "#FFE03AAE"),
        .init(name: "绿色", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FFE5FFBF", lyricStroke: "#FF2F4321", karaokeStroke: "#FF429F25"),
        .init(name: "橘蓝", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FF14A0FE", karaoke: "#FFEF8044", lyricStroke: "#FF000000", karaokeStroke: "#FF000000"),
        .init(name: "黄色", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FFF1E8A9", lyricStroke: "#FF323232", karaokeStroke: "#FFDBA714"),
        .init(name: "经典蓝", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FF3835F8", lyricStroke: "#FF000000", karaokeStroke: "#FFFFFFFF"),
        .init(name: "经典绿", border: "#548F8F8F", background: "#FF2C2C2C", lyric: "#FFFFFFFF", karaoke: "#FF189958", lyricStroke: "#FF000000", karaokeStroke: "#FFFFFFFF")
    ]

    static func named(_ name: String) -> LyricTheme { presets.first { $0.name == name } ?? presets[0] }

    static func custom(border: String, background: String, lyric: String, karaoke: String, lyricStroke: String, karaokeStroke: String) -> LyricTheme {
        .init(name: "自定义", border: border, background: background, lyric: lyric, karaoke: karaoke, lyricStroke: lyricStroke, karaokeStroke: karaokeStroke)
    }

    static func color(_ argb: String) -> Color {
        Color(nsColor(argb))
    }

    static func nsColor(_ argb: String) -> NSColor {
        let text = argb.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(text, radix: 16) else { return .clear }
        let a, r, g, b: Double
        if text.count == 8 {
            a = Double((value >> 24) & 0xff) / 255
            r = Double((value >> 16) & 0xff) / 255
            g = Double((value >> 8) & 0xff) / 255
            b = Double(value & 0xff) / 255
        } else {
            a = 1
            r = Double((value >> 16) & 0xff) / 255
            g = Double((value >> 8) & 0xff) / 255
            b = Double(value & 0xff) / 255
        }
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    static func argb(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        return String(
            format: "#%02X%02X%02X%02X",
            Int((nsColor.alphaComponent * 255).rounded()),
            Int((nsColor.redComponent * 255).rounded()),
            Int((nsColor.greenComponent * 255).rounded()),
            Int((nsColor.blueComponent * 255).rounded())
        )
    }
}

enum LyricFontWeight: String, CaseIterable, Identifiable {
    case regular = "常规"
    case medium = "中等"
    case semibold = "半粗体"
    case bold = "粗体"

    var id: String { rawValue }
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}
