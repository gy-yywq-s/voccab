import SwiftUI

/// Minimal flow layout for chip rows, shared by both frontends.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// UIReferenceLibraryViewController wrapper (the system dictionary).
struct AppleDictionarySheet: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// The system dictionary embedded directly in the page (no modal slide-up).
/// Apple exposes no text API for its dictionaries, so the reference view
/// controller itself is hosted inline in the tab content area.
struct AppleDictionaryInline: View {
    let term: String

    var body: some View {
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
            AppleDictionarySheet(term: term)
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                )
        } else {
            Text("No entry for “\(term)” in the system dictionaries. Add dictionaries in Settings › General › Dictionary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
