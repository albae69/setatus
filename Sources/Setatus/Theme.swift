import AppKit
import SwiftUI

// V3 neo brutalism: hard edges, ink strokes, flat offset shadows.
enum Bru {
    static let ink = dynamic(light: 0x111111, dark: 0xF4EFE4)
    static let paper = dynamic(light: 0xFFFDF7, dark: 0x181818)
    static let cream = dynamic(light: 0xF4EFE4, dark: 0x0D0D0D)
    static let muted = dynamic(light: 0x6B6459, dark: 0xA39B8C)
    static let onInk = dynamic(light: 0xFFFDF7, dark: 0x111111)
    static let yellow = Color(hex: 0xFFD93D)
    static let blue = Color(hex: 0x4D7CFE)
    static let green = Color(hex: 0x4ADE80)
    static let red = Color(hex: 0xFF5C5C)
    static let cardInk = Color(hex: 0x111111)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: darkMode ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

struct CardStyle: ViewModifier {
    var fill: Color = Bru.paper
    var shadow: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if shadow > 0 {
                        Rectangle().fill(Bru.ink).offset(x: shadow, y: shadow)
                    }
                    Rectangle().fill(fill)
                }
            )
            .overlay(Rectangle().stroke(Bru.ink, lineWidth: 3))
    }
}

extension View {
    func card(_ fill: Color = Bru.paper, shadow: CGFloat = 6) -> some View {
        modifier(CardStyle(fill: fill, shadow: shadow))
    }

    func slab(_ fill: Color, line: CGFloat = 2, shadow: CGFloat = 0) -> some View {
        background(
            ZStack {
                if shadow > 0 {
                    Rectangle().fill(Bru.ink).offset(x: shadow, y: shadow)
                }
                Rectangle().fill(fill)
            }
        )
        .overlay(Rectangle().stroke(Bru.ink, lineWidth: line))
    }
}
