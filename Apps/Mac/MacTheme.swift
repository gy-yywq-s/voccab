import AppKit
import SwiftUI

/// Voccab Mac design language.
///
/// The workspace is a *document*, not a form: paper-quiet background, a serif
/// column of headwords, SF for everything the interface says about itself, and
/// hairlines instead of boxes. Hierarchy comes from size, weight and gray
/// level — never from a border.
enum Mac {

    // MARK: - Metrics

    /// Width of the word column. Wide enough for the longest headwords a
    /// person actually collects, narrow enough that notes get the page.
    static let wordColumnWidth: CGFloat = 200
    /// Horizontal page inset for the workspace body.
    static let pageInset: CGFloat = 22
    /// Vertical breathing room inside a row.
    static let rowPadding: CGFloat = 10
    static let minWindowWidth: CGFloat = 820
    static let minWindowHeight: CGFloat = 520

    // MARK: - Type

    /// The built-in serif used for headwords. Iowan Old Style ships with
    /// macOS, but a font can always be disabled or removed by the user, so the
    /// name is probed once and the system serif stands in when it is absent.
    private static let serifName: String? = {
        for candidate in ["IowanOldStyle-Roman", "Iowan Old Style", "IowanOldStyle-Titling"] {
            if NSFont(name: candidate, size: 12) != nil { return candidate }
        }
        return nil
    }()

    /// Serif face for content words (headwords, dictionary prose).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let serifName {
            return .custom(serifName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// The word field in the workspace table.
    static var wordField: Font { serif(16) }
    /// The headword at the top of the inspector.
    static var headword: Font { serif(30, weight: .medium) }
    /// Dictionary body prose in the inspector.
    static var dictionaryBody: Font { serif(14) }
    /// Lead synonym of a thesaurus group.
    static var dictionaryLead: Font { serif(14, weight: .semibold) }

    /// Notes and every piece of interface text: SF, system sizes.
    static let notesField: Font = .system(size: 13)
    static let inline: Font = .system(size: 11.5)
    static let footer: Font = .system(size: 11)
    static let columnHeader: Font = .system(size: 10, weight: .semibold)

    // MARK: - Ink and surfaces

    static let ink = Color.primary
    static let graphite = Color.secondary
    static let faint = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)

    /// The writing surface — the same white/near-black a text view uses, so
    /// the workspace reads as a page rather than as a control.
    static let paper = Color(nsColor: .textBackgroundColor)
    /// Chrome above and below the page (header strip, footer bar).
    static let chrome = Color(nsColor: .underPageBackgroundColor)

    /// Alternating row wash — deliberately fainter than a table view's, since
    /// rows here are tall and text-heavy.
    static let stripe = Color.primary.opacity(0.022)
    /// Hover wash, one step stronger than the stripe.
    static let hover = Color.primary.opacity(0.05)
    /// Focused-row wash, tinted with the user's accent colour.
    static let focusWash = Color.accentColor.opacity(0.07)

    static let accent = Color.accentColor
}

// MARK: - Shared pieces

/// A 0.5pt rule. `Divider()` picks up group styling in odd places; this is
/// always exactly the hairline we asked for.
struct MacHairline: View {
    var body: some View {
        Rectangle()
            .fill(Mac.hairline)
            .frame(height: 0.5)
    }
}

/// Uppercase tracked caption with a hairline underneath — the Apple Dictionary
/// section-label idiom (DERIVATIVES, ORIGIN, …).
struct MacFieldLabel: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            MacHairline()
        }
    }
}

/// Small pill used for frequency band / exam tags in the inspector header.
struct MacChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

/// Wrapping run of views (synonym lists, related forms). Reimplemented for the
/// Mac target because `Apps/Shared` is UIKit-bound and cannot be compiled here.
struct MacFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        let width = maxWidth.isFinite ? min(widest, maxWidth) : widest
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
