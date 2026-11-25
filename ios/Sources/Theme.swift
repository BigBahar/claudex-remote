import SwiftUI
import UIKit

/// Claudex's own look: graphite and off-white with one ember accent.
enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg = dynamic(0xF7F6F2, 0x17171A)
    static let surface = dynamic(0xFFFFFF, 0x1F1F23)
    static let raised = dynamic(0xEFEDE6, 0x27272C)
    static let ink = dynamic(0x1C1B19, 0xEDEDEF)
    static let muted = dynamic(0x77736B, 0x9B9AA0)
    static let line = dynamic(0xE4E0D6, 0x2C2C31)
    static let ember = dynamic(0xE2621B, 0xFF8A42)
    static let ok = dynamic(0x2F8F5B, 0x58C98A)
    static let bad = dynamic(0xC0392B, 0xFF6B5E)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The Claudex mark: an ember C (Claude) holding a light x (Codex), drawn from the 512-point icon.
struct XMark: View {
    var size: CGFloat = 28
    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 512
            // The C: an arc of radius 145 around (282.7, 256), open on the right, traced point by point.
            var c = Path()
            let steps = 48
            for i in 0...steps {
                let a = (-69.7 - Double(i) / Double(steps) * 220.6) * .pi / 180
                let p = CGPoint(x: (282.7 + 145 * cos(a)) * k, y: (256 + 145 * sin(a)) * k)
                if i == 0 { c.move(to: p) } else { c.addLine(to: p) }
            }
            ctx.stroke(c, with: .color(Theme.ember), style: StrokeStyle(lineWidth: 52 * k, lineCap: .round, lineJoin: .round))
            var x = Path()
            x.move(to: CGPoint(x: 256 * k, y: 196 * k)); x.addLine(to: CGPoint(x: 358 * k, y: 316 * k))
            x.move(to: CGPoint(x: 358 * k, y: 196 * k)); x.addLine(to: CGPoint(x: 256 * k, y: 316 * k))
            ctx.stroke(x, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 52 * k, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension String {
    /// True when the first letter is Hebrew or Arabic, so a message sets and aligns right-to-left.
    var isRTL: Bool {
        for u in unicodeScalars {
            if (0x0590...0x08FF).contains(u.value) || (0xFB1D...0xFDFF).contains(u.value) || (0xFE70...0xFEFF).contains(u.value) { return true }
            if CharacterSet.letters.contains(u) { return false }
        }
        return false
    }
}

/// Text that lays itself out right-to-left when it is Hebrew.
struct BidiText: View {
    let text: String
    var markdown = false
    var body: some View {
        let rtl = text.isRTL
        Group {
            if markdown, let a = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(a)
            } else {
                Text(text)
            }
        }
        .multilineTextAlignment(rtl ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .textSelection(.enabled)
    }
}
