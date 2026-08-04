import SwiftUI

/// Colors and fonts replicating the original app in both appearances.
enum ClassicTheme {

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Home blob greens (light: soft pastel; dark: deep forest).
    static let blobPrimary = dynamic(
        light: UIColor(red: 0.83, green: 0.93, blue: 0.79, alpha: 1.0),
        dark: UIColor(red: 0.16, green: 0.26, blue: 0.13, alpha: 1.0)
    )
    static let blobSecondary = dynamic(
        light: UIColor(red: 0.87, green: 0.95, blue: 0.83, alpha: 0.7),
        dark: UIColor(red: 0.20, green: 0.31, blue: 0.16, alpha: 0.7)
    )

    // Green list tile.
    static let tileGreen = dynamic(
        light: UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1.0),
        dark: UIColor(red: 0.16, green: 0.55, blue: 0.28, alpha: 1.0)
    )
    static let tileTitle = dynamic(light: .black, dark: .white)
    static let tileSubtitle = dynamic(
        light: UIColor(white: 0.35, alpha: 1.0),
        dark: UIColor(white: 0.85, alpha: 1.0)
    )

    // Word header card.
    static let cardBackground = dynamic(
        light: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
    )
    static let noteBackground = dynamic(
        light: UIColor(red: 0.82, green: 0.82, blue: 0.85, alpha: 1.0),
        dark: UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1.0)
    )

    // Tag chips.
    static let familiarityChip = dynamic(
        light: UIColor(red: 0.66, green: 0.34, blue: 0.16, alpha: 1.0),
        dark: UIColor(red: 0.55, green: 0.29, blue: 0.14, alpha: 1.0)
    )
    static let familiarityUnknownChip = dynamic(
        light: UIColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0),
        dark: UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1.0)
    )
    static let frequencyChip = dynamic(
        light: UIColor(red: 0.35, green: 0.78, blue: 0.42, alpha: 1.0),
        dark: UIColor(red: 0.16, green: 0.62, blue: 0.30, alpha: 1.0)
    )
    static let examChip = dynamic(
        light: UIColor(red: 0.35, green: 0.56, blue: 0.83, alpha: 1.0),
        dark: UIColor(red: 0.29, green: 0.45, blue: 0.65, alpha: 1.0)
    )
    static let listChip = dynamic(
        light: UIColor(red: 0.91, green: 0.70, blue: 0.49, alpha: 1.0),
        dark: UIColor(red: 0.55, green: 0.36, blue: 0.16, alpha: 1.0)
    )

    // Study buttons.
    static let studyButtonBackground = dynamic(
        light: UIColor(red: 0.82, green: 0.95, blue: 0.84, alpha: 1.0),
        dark: UIColor(red: 0.09, green: 0.25, blue: 0.12, alpha: 1.0)
    )
    static let studyButtonText = dynamic(
        light: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0),
        dark: UIColor(red: 0.28, green: 0.85, blue: 0.42, alpha: 1.0)
    )
    static let continueButtonBackground = dynamic(
        light: UIColor(red: 0.85, green: 0.91, blue: 0.99, alpha: 1.0),
        dark: UIColor(red: 0.08, green: 0.17, blue: 0.30, alpha: 1.0)
    )
    static let knowButtonBackground = dynamic(
        light: UIColor(red: 0.84, green: 0.95, blue: 0.85, alpha: 1.0),
        dark: UIColor(red: 0.09, green: 0.23, blue: 0.12, alpha: 1.0)
    )
    static let knowButtonText = dynamic(
        light: UIColor(red: 0.18, green: 0.70, blue: 0.32, alpha: 1.0),
        dark: UIColor(red: 0.30, green: 0.85, blue: 0.44, alpha: 1.0)
    )
    static let dontKnowButtonBackground = dynamic(
        light: UIColor(red: 0.99, green: 0.88, blue: 0.87, alpha: 1.0),
        dark: UIColor(red: 0.28, green: 0.10, blue: 0.10, alpha: 1.0)
    )
    static let dontKnowButtonText = dynamic(
        light: UIColor(red: 0.90, green: 0.25, blue: 0.22, alpha: 1.0),
        dark: UIColor(red: 0.95, green: 0.35, blue: 0.32, alpha: 1.0)
    )

    static let wordChipBackground = dynamic(
        light: UIColor(red: 0.80, green: 0.89, blue: 0.98, alpha: 1.0),
        dark: UIColor(red: 0.15, green: 0.25, blue: 0.38, alpha: 1.0)
    )

    // Fonts.
    static func scriptFont(size: CGFloat) -> Font {
        .custom("SnellRoundhand-Bold", size: size)
    }

    static func serifWord(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

/// Capsule tag chip used on word cards.
struct TagChip: View {
    var text: String
    var background: Color

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
