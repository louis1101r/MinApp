import SwiftUI
import UIKit

/// Svejtsisk minimalisme (afsnit 6): sort/hvid, blå accent, rød til advarsler,
/// skarpe hjørner, 2 pt sorte streger og tal med fast bredde.
enum T {
    static let bg = dynamic(0xFFFFFF, 0x0B0B0C)
    static let ink = dynamic(0x000000, 0xF2F2F0)
    static let onInk = dynamic(0xFFFFFF, 0x0B0B0C)
    static let muted = dynamic(0x767676, 0x9C9C9C)
    static let line = dynamic(0x000000, 0xF2F2F0)
    static let hair = dynamic(0xDEDEDE, 0x2A2A2A)
    static let blue = dynamic(0x0033CC, 0x5C8DFF)
    static let red = dynamic(0xB00020, 0xFF6B6B)
    static let wash = dynamic(0xF1F1EF, 0x1B1B1D)

    static let maxWidth: CGFloat = 540

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typografi

extension View {
    /// .display
    func displayStyle(_ size: CGFloat = 38) -> some View {
        font(.system(size: size, weight: .heavy))
            .tracking(-size * 0.035)
            .foregroundStyle(T.ink)
    }

    /// .lead
    func leadStyle() -> some View {
        font(.system(size: 15)).foregroundStyle(T.muted)
    }

    /// .small .muted
    func smallMuted() -> some View {
        font(.system(size: 13)).foregroundStyle(T.muted)
    }
}

/// h2
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(T.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// .sec: 2 pt streg foroven.
struct Sec<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(T.line).frame(height: 2)
        }
        .padding(.top, 26)
    }
}

// MARK: - Knapper

/// .btn og .btn.o
struct BlockButtonStyle: ButtonStyle {
    var outline = false
    var small = false
    var fill: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let base = fill ?? T.ink
        configuration.label
            .font(.system(size: small ? 14 : 16, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: small ? 44 : 56)
            .foregroundStyle(outline ? T.ink : (fill == nil ? T.onInk : Color.white))
            .background(outline ? (configuration.isPressed ? T.wash : Color.clear) : base)
            .overlay(Rectangle().strokeBorder(base, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// .btn.link
struct TextLinkStyle: ButtonStyle {
    var color: Color = T.blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 12)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Knapper der skalerer ved tryk (chips, segmenter, ✓).
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Tastatur

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
