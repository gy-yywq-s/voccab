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

/// The system dictionary flattened into the page: full-bleed, sized to its
/// own content with internal scrolling disabled, so the page scrolls as one.
/// The view controller is cached per term (creating it is what caused the
/// tap stall) and `dictionaryHasDefinition` is never called synchronously —
/// the embedded controller shows its own empty state when a word is missing.
struct AppleDictionaryInline: View {
    let term: String
    @State private var contentHeight: CGFloat = 420

    /// Creating the first UIReferenceLibraryViewController loads dictionary
    /// assets and stalls the main thread; do it once at an idle moment.
    @MainActor
    static func warmUp() {
        _ = UIReferenceLibraryViewController(term: "hello")
    }

    var body: some View {
        FlattenedReferenceView(term: term, contentHeight: $contentHeight)
            .frame(height: max(contentHeight, 320))
    }
}

private struct FlattenedReferenceView: UIViewControllerRepresentable {
    let term: String
    @Binding var contentHeight: CGFloat

    static let cache = NSCache<NSString, UIReferenceLibraryViewController>()

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        let controller: UIReferenceLibraryViewController
        if let cached = Self.cache.object(forKey: term as NSString) {
            controller = cached
        } else {
            controller = UIReferenceLibraryViewController(term: term)
            Self.cache.setObject(controller, forKey: term as NSString)
        }
        context.coordinator.flatten(controller, into: $contentHeight)
        return controller
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var observation: NSKeyValueObservation?

        /// Finds the controller's internal scroll view once it exists,
        /// disables its own scrolling, and mirrors its content height out so
        /// the SwiftUI frame grows to fit — one page, one scroll.
        func flatten(_ controller: UIViewController, into height: Binding<CGFloat>) {
            func attempt(retries: Int) {
                guard retries > 0 else { return }
                guard let scrollView = Self.findScrollView(in: controller.view) else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        attempt(retries: retries - 1)
                    }
                    return
                }
                scrollView.isScrollEnabled = false
                observation = scrollView.observe(\.contentSize, options: [.initial, .new]) { scrollView, _ in
                    let newHeight = scrollView.contentSize.height
                    guard newHeight > 60 else { return }
                    DispatchQueue.main.async {
                        if abs(height.wrappedValue - (newHeight + 24)) > 2 {
                            height.wrappedValue = newHeight + 24
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                attempt(retries: 8)
            }
        }

        private static func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) { return found }
            }
            return nil
        }
    }
}
