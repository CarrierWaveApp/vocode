import SwiftUI

/// Palette lifted from carrierwave.app
enum CW {
    static let bg = Color(hex: 0x0E0F11)
    static let surface = Color(hex: 0x131518)
    static let raised = Color(hex: 0x1A1D21)
    static let border = Color(hex: 0x1F2328)
    static let text = Color(hex: 0xC9CDD6)
    static let dim = Color(hex: 0x666C7A)
    static let xdim = Color(hex: 0x35393F)
    static let white = Color(hex: 0xF2F4F8)
    static let blue = Color(hex: 0x4A8CFF)
    static let green = Color(hex: 0x22C55E)
    static let amber = Color(hex: 0xF59E0B)
    static let red = Color(hex: 0xEF4444)

    static func sans(_ size: CGFloat, _ weight: SansWeight = .regular) -> Font {
        .custom(weight.name, size: size)
    }

    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }

    enum SansWeight {
        case regular, medium, semibold
        var name: String {
            switch self {
            case .regular: return "Outfit-Regular"
            case .medium: return "Outfit-Medium"
            case .semibold: return "Outfit-SemiBold"
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// "// SECTION" label like the site
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text("// " + text.uppercased())
            .font(CW.mono(11))
            .tracking(1.2)
            .foregroundStyle(CW.dim)
            .textCase(nil)
    }
}

/// Shared list chrome
struct CWListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CW.bg)
            .listRowBackground(CW.surface)
            .listRowSeparatorTint(CW.border)
            .foregroundStyle(CW.text)
            .font(CW.sans(15))
            .tint(CW.blue)
    }
}

extension View {
    func cwList() -> some View {
        modifier(CWListStyle())
    }
}

/// Pill button matching the site's CTA
struct PillButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CW.sans(13, .medium))
            .foregroundStyle(filled ? CW.bg : CW.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(filled ? CW.blue : CW.raised)
            .overlay(
                Capsule().stroke(filled ? .clear : CW.border, lineWidth: 1)
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
