import SwiftUI

/// Voccab Neo design language, derived from the applicable parts of the
/// passage-ios-ui-refinement skill: paper-white editorial surface, ink and
/// whitespace over cards, serif reserved for words and the masthead,
/// restrained blue as the interactive signal, differentiated hairlines,
/// compact quiet controls with invisible hit targets.
enum Neo {

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Surfaces
    static let paper = dynamic(
        light: UIColor(red: 0.99, green: 0.985, blue: 0.975, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1)
    )
    static let field = dynamic(
        light: .white,
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.115, alpha: 1)
    )

    // Ink
    static let ink = dynamic(
        light: UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1),
        dark: UIColor(red: 0.93, green: 0.92, blue: 0.90, alpha: 1)
    )
    static let graphite = dynamic(
        light: UIColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1)
    )
    static let faint = dynamic(
        light: UIColor(red: 0.58, green: 0.58, blue: 0.60, alpha: 1),
        dark: UIColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1)
    )

    // Blue roles
    static let blue = dynamic(
        light: UIColor(red: 0.16, green: 0.36, blue: 0.66, alpha: 1),
        dark: UIColor(red: 0.48, green: 0.65, blue: 0.92, alpha: 1)
    )
    static let navy = dynamic(
        light: UIColor(red: 0.10, green: 0.18, blue: 0.34, alpha: 1),
        dark: UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1)
    )
    static let paleBlue = dynamic(
        light: UIColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.18, blue: 0.27, alpha: 1)
    )
    static let navyFillText = dynamic(
        light: .white,
        dark: UIColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1)
    )

    // Signals
    static let warm = dynamic(
        light: UIColor(red: 0.80, green: 0.52, blue: 0.16, alpha: 1),
        dark: UIColor(red: 0.90, green: 0.65, blue: 0.30, alpha: 1)
    )
    static let green = dynamic(
        light: UIColor(red: 0.20, green: 0.52, blue: 0.30, alpha: 1),
        dark: UIColor(red: 0.42, green: 0.75, blue: 0.50, alpha: 1)
    )
    static let red = dynamic(
        light: UIColor(red: 0.72, green: 0.20, blue: 0.16, alpha: 1),
        dark: UIColor(red: 0.92, green: 0.42, blue: 0.38, alpha: 1)
    )

    // Rules (differentiated boundary roles)
    static let hairline = dynamic(
        light: UIColor(white: 0, alpha: 0.12),
        dark: UIColor(white: 1, alpha: 0.14)
    )
    static let sectionRule = dynamic(
        light: UIColor(white: 0, alpha: 0.22),
        dark: UIColor(white: 1, alpha: 0.26)
    )

    // Type
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static let masthead = serif(17, weight: .semibold)
    static let pageTitle = serif(30, weight: .semibold)
    static let sectionHead = sans(13, weight: .semibold)
}

// MARK: - Small shared pieces

/// Small-caps quiet section heading with a short title marker rule.
struct NeoSectionHeader: View {
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Neo.sectionRule)
                .frame(width: 22, height: 2)
            Text(title.uppercased())
                .font(Neo.sectionHead)
                .kerning(1.1)
                .foregroundStyle(Neo.graphite)
        }
    }
}

/// Full-width hairline.
struct NeoHairline: View {
    var body: some View {
        Rectangle()
            .fill(Neo.hairline)
            .frame(height: 0.7)
    }
}

/// Quiet metadata chip: hairline outline, no fill.
struct NeoTag: View {
    var text: String
    var color: Color = Neo.graphite

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Neo.hairline, lineWidth: 0.8)
            )
    }
}

/// Compact navy commitment button (rare, meaningful actions).
struct NeoPrimaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                }
                Text(title)
                    .font(Neo.sans(16, weight: .semibold))
            }
            .foregroundStyle(Neo.navyFillText)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Neo.navy)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            )
        }
        .buttonStyle(NeoPressStyle())
    }
}

/// Pale-blue quiet task action, flat at rest.
struct NeoQuietButton: View {
    var title: String
    var systemImage: String?
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                }
                Text(title)
                    .font(Neo.sans(15, weight: .medium))
            }
            .foregroundStyle(role == .destructive ? Neo.red : Neo.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(role == .destructive ? Neo.red.opacity(0.08) : Neo.paleBlue)
            )
        }
        .buttonStyle(NeoPressStyle())
    }
}

/// Press feedback: slight compression + tint, no permanent shadow.
struct NeoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
