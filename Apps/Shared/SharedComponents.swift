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
        private var timer: Timer?

        deinit { timer?.invalidate() }

        /// Flattens the controller into the page: polls for its internal
        /// scroll views (the dictionary content loads progressively and the
        /// hierarchy changes), disables scrolling on EVERY one found, and
        /// mirrors the tallest content height out so the SwiftUI frame grows
        /// to fit — one page, one scroll.
        func flatten(_ controller: UIViewController, into height: Binding<CGFloat>) {
            timer?.invalidate()
            var ticks = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak controller] timer in
                ticks += 1
                if ticks > 24 { timer.invalidate() }
                guard let controller else {
                    timer.invalidate()
                    return
                }
                let scrollViews = Self.allScrollViews(in: controller.view)
                var tallest: CGFloat = 0
                for scrollView in scrollViews {
                    scrollView.isScrollEnabled = false
                    scrollView.showsVerticalScrollIndicator = false
                    tallest = max(tallest, scrollView.contentSize.height)
                }
                guard tallest > 100 else { return }
                let newHeight = tallest + 24
                if abs(height.wrappedValue - newHeight) > 4 {
                    height.wrappedValue = newHeight
                }
            }
        }

        private static func allScrollViews(in view: UIView) -> [UIScrollView] {
            var found: [UIScrollView] = []
            if let scrollView = view as? UIScrollView { found.append(scrollView) }
            for subview in view.subviews {
                found.append(contentsOf: allScrollViews(in: subview))
            }
            return found
        }
    }
}

/// Segmented ("cells") session progress bar shared by both frontends: one
/// cell per card up to a cap; past the cap, cells stand for equal groups of
/// cards and fill fractionally, so the bar always reads "how many done, how
/// many left" at a glance.
struct SegmentedProgressBar: View {
    let completed: Int
    let total: Int
    var tint: Color = .accentColor
    var track: Color = Color(uiColor: .systemFill)

    private static let maxCells = 20

    var body: some View {
        let cells = max(1, min(total, Self.maxCells))
        let perCell = Double(max(1, total)) / Double(cells)
        HStack(spacing: 3) {
            ForEach(0..<cells, id: \.self) { index in
                let start = Double(index) * perCell
                let fraction = min(1, max(0, (Double(completed) - start) / perCell))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(track)
                        if fraction > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(tint)
                                .frame(width: max(2, proxy.size.width * fraction))
                        }
                    }
                }
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.2), value: completed)
    }
}

/// A real note editor — multi-line TextEditor in a sheet (the old alert
/// TextField was a single cramped line). Medium detent by default,
/// draggable to full screen.
struct NoteEditorSheet: View {
    let word: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .font(.body)
                .lineSpacing(4)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle(word)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear { focused = true }
                .accessibilityIdentifier("word.noteEditor")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
