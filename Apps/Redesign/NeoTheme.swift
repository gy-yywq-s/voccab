import SwiftUI

/// Voccab Neo design language — native-first iOS, calibrated against the
/// Passage reference screens: pure system background, SF type for all
/// interface text (serif reserved for dictionary headwords as content),
/// bold sans section titles with a short leading rule, hairline separators,
/// pale-blue task actions, a deep-navy commit, and native controls
/// (toggles, segmented pickers, wheel sheets) everywhere else.
enum Neo {

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Ink roles map straight onto system labels.
    static let ink = Color.primary
    static let graphite = Color.secondary
    static let faint = Color(uiColor: .tertiaryLabel)

    // Blue roles (Passage: interactive signal + deep navy commitment).
    static let blue = dynamic(
        light: UIColor(red: 0.13, green: 0.35, blue: 0.66, alpha: 1),
        dark: UIColor(red: 0.42, green: 0.62, blue: 0.94, alpha: 1)
    )
    static let paleBlue = dynamic(
        light: UIColor(red: 0.13, green: 0.35, blue: 0.66, alpha: 0.09),
        dark: UIColor(red: 0.42, green: 0.62, blue: 0.94, alpha: 0.16)
    )
    static let navy = dynamic(
        light: UIColor(red: 0.12, green: 0.23, blue: 0.42, alpha: 1),
        dark: UIColor(red: 0.24, green: 0.42, blue: 0.70, alpha: 1)
    )

    // Signals.
    static let warm = dynamic(
        light: UIColor(red: 0.64, green: 0.42, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.88, green: 0.64, blue: 0.30, alpha: 1)
    )
    static let green = Color(uiColor: .systemGreen)
    static let red = Color(uiColor: .systemRed)

    // Boundaries.
    static let hairline = Color(uiColor: .separator)
    static let sectionRule = dynamic(
        light: UIColor(white: 0.25, alpha: 1),
        dark: UIColor(white: 0.75, alpha: 1)
    )

    /// Serif appears exactly once in the app: the masthead wordmark,
    /// mirroring Passage's type allocation. Everything else is SF.
    static let masthead: Font = .system(size: 23, weight: .medium, design: .serif)

    // MARK: Type roles measured from the Passage reference screens.
    // Hierarchy is carried by size + weight + gray level, never by family:
    //   pageTitle    28 bold primary      ("Sessions")
    //   sectionTitle 24 bold primary      ("Scheduled delivery")
    //   rowTitle     20 semibold primary  (session/item titles, nav titles)
    //   body         17 regular primary   (main statements)
    //   bodyQuiet    17 regular secondary (summaries, helper prose)
    //   contextLabel 17 regular secondary ("Archive", "reject", "targeted")
    //   caption      15 regular secondary/tertiary ("Command of Evidence · …")
    //   action       20 semibold blue     ("Begin today")
    //   warm body    17 regular warm      (risk/note prose)
    static let pageTitle: Font = .system(size: 28, weight: .bold)
    static let sectionTitle: Font = .system(size: 24, weight: .bold)
    static let rowTitle: Font = .system(size: 20, weight: .semibold)
    static let bodyFont: Font = .system(size: 17)
    static let caption: Font = .system(size: 15)
    static let action: Font = .system(size: 20, weight: .semibold)
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

/// Passage-style section heading: short dark rule above a bold sans title,
/// with an optional trailing action slot aligned to the title baseline.
struct NeoSectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Neo.sectionRule)
                .frame(width: 28, height: 2)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Neo.sectionTitle)
                Spacer()
                trailing()
            }
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
