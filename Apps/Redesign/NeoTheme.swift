import SwiftUI

/// Voccab Neo design language — "vintage study" edition, built from the
/// user's chosen palette sheets: warm cream pages, cocoa ink, sand-gold
/// emphasis, moss/olive greens for progress, and two blues (mid + deep)
/// as the only interactive hues. Interface type is rounded geometric
/// (SF Rounded, mirroring the palette sheets' Comfortaa look); serif is
/// reserved for word content. Terracotta is deliberately absent.
enum Neo {

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
    }

    // Grounds (Ge cream page, Cd bleached-cream card; cocoa world in dark).
    static let page = dynamic(light: hex(0xF7E6D4), dark: hex(0x2C2222))
    static let cardFill = dynamic(light: hex(0xFBFAE6), dark: hex(0x3B2F2F))
    /// Sand-gold emphasized surface (Gb) — Hard button, highlighted cards.
    static let sand = dynamic(light: hex(0xE7C58A), dark: hex(0xC9A76B))
    static let onSand = dynamic(light: hex(0x4B3535), dark: hex(0x2C2222))

    // Ink (cocoa on cream; cream on cocoa).
    static let ink = dynamic(light: hex(0x4B3535), dark: hex(0xF3E9DC))
    static let graphite = dynamic(light: hex(0x4B3535, 0.62), dark: hex(0xF3E9DC, 0.62))
    static let faint = dynamic(light: hex(0x4B3535, 0.38), dark: hex(0xF3E9DC, 0.38))
    /// Burnt gray (Df) — icons and truly neutral marks.
    static let neutral = dynamic(light: hex(0x5D5D5A), dark: hex(0xA5A5A0))

    // Blues — the interactive pair chosen to replace the vintage violet:
    // mid blue (Ff) for controls, deep blue (Ec) for commitment.
    static let blue = dynamic(light: hex(0x4E7CB2), dark: hex(0x85A9D6))
    static let paleBlue = dynamic(light: hex(0x4E7CB2, 0.13), dark: hex(0x85A9D6, 0.20))
    static let navy = dynamic(light: hex(0x253A82), dark: hex(0x8FA7E8))

    // Greens — learning signals: moss (Gc) for recall/success, grass (Ha)
    // for seeding/new growth, olive (Ca/Ad) as deep/soft accents.
    static let green = dynamic(light: hex(0x86B05D), dark: hex(0x97BE72))
    static let grass = dynamic(light: hex(0xD2E186), dark: hex(0x5A6A2E))
    static let onGrass = dynamic(light: hex(0x415111), dark: hex(0xE2EDB4))
    static let olive = dynamic(light: hex(0x587032), dark: hex(0xA3B565))
    static let softOlive = dynamic(light: hex(0xA3B565), dark: hex(0x7A8A4C))

    // Signals.
    static let warm = dynamic(light: hex(0x9A6B2F), dark: hex(0xE7C58A))
    static let red = Color(uiColor: .systemRed)

    // Boundaries — cocoa-tinted, never system gray.
    static let hairline = dynamic(light: hex(0x4B3535, 0.16), dark: hex(0xF3E9DC, 0.14))

    /// Rounded geometric wordmark, matching the palette sheets.
    static let masthead: Font = .system(size: 22, weight: .semibold, design: .rounded)

    // MARK: Type roles — rounded geometric interface (the palette sheets'
    // Comfortaa temperament via SF Rounded); serif never appears in chrome,
    // only in word content. Hierarchy from grouping, not ever-bigger bold.
    static let pageTitle: Font = .system(size: 25, weight: .semibold, design: .rounded)
    static let sectionTitle: Font = .system(size: 18, weight: .semibold, design: .rounded)
    static let rowTitle: Font = .system(size: 17, weight: .semibold, design: .rounded)
    static let bodyFont: Font = .system(size: 17, design: .rounded)
    static let caption: Font = .system(size: 15, design: .rounded)
    static let action: Font = .system(size: 19, weight: .semibold, design: .rounded)

    // MARK: Grouping surfaces.
    static let cardRadius: CGFloat = 16
    /// Uppercase tracked micro-label above a card.
    static let sectionLabel: Font = .system(size: 13, weight: .medium, design: .rounded)
}

/// Soft rounded grouping card — flat fill, continuous corners, no border.
struct NeoCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Neo.cardRadius, style: .continuous)
                    .fill(Neo.cardFill)
            )
    }
}

/// Small colored data chip (familiarity, counts, tags) — the original
/// app's way of showing status without a sentence.
struct NeoChip: View {
    let text: String
    var tint: Color = Neo.blue

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(tint.opacity(0.13)))
    }
}

/// The primary-entry bar, straight from Passage's "Begin today": full-width
/// pale-blue block, left-aligned blue semibold label, trailing icon.
struct NeoBeginBar: View {
    var title: String
    var systemImage: String = "arrow.right"
    var tint: Color = Neo.blue
    var background: Color = Neo.paleBlue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Neo.action)
                Spacer()
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(NeoPressStyle())
    }
}

// MARK: - Shared pieces

/// Section heading: bold sans title carrying hierarchy through size and
/// spacing alone, with an optional trailing action slot aligned to the
/// title baseline.
struct NeoSectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Neo.sectionTitle)
            Spacer()
            trailing()
        }
    }
}

struct NeoHairline: View {
    var body: some View {
        Rectangle()
            .fill(Neo.hairline)
            .frame(height: 0.5)
    }
}

/// Pale-blue task action ("Generate extra" style): icon + label on a soft
/// blue fill, flat at rest.
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
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(role == .destructive ? Neo.red : Neo.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(role == .destructive ? Neo.red.opacity(0.09) : Neo.paleBlue)
            )
        }
        .buttonStyle(NeoPressStyle())
    }
}

/// Press feedback: slight compression + tint change, no resting chrome.
struct NeoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Native-style rounded search field (Records reference): white fill, full
/// capsule, light shadow, no stroke.
struct NeoSearchField: View {
    var placeholder: String
    @Binding var text: String
    var onChange: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: text) { onChange() }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(
            Capsule().fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        )
    }
}
