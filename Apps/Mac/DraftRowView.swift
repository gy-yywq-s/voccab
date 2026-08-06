import SwiftUI
import VocabKit

/// Which field of which row holds the caret.
enum DraftFocus: Hashable {
    case word(UUID)
    case note(UUID)
}

/// One line of the workspace.
///
/// Layout is two stacked bands rather than a strict grid: the editable pair
/// (word | notes) on top, and — only when the dictionary has something to say —
/// a quiet definition strip underneath, indented to start under the word
/// column. The strip is the affordance for the inspector: it is the rendered
/// definition, and clicking the rendered definition opens the full entry.
struct DraftRowView: View {
    @Binding var row: DraftRow
    let index: Int
    let isLast: Bool

    @FocusState.Binding var focus: DraftFocus?

    let onReturn: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    let onInspect: (String) -> Void

    @EnvironmentObject private var env: MacEnvironment

    @State private var lookup: LookupResult = .empty
    @State private var isHovering = false

    private var isFocused: Bool {
        focus == DraftFocus.word(row.id) || focus == DraftFocus.note(row.id)
    }

    private var background: Color {
        if isFocused { return Mac.focusWash }
        if isHovering { return Mac.hover }
        return index.isMultiple(of: 2) ? .clear : Mac.stripe
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                editors
                definitionStrip
            }
            .padding(.horizontal, Mac.pageInset)
            .padding(.vertical, Mac.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(Rectangle())

            if !isLast { MacHairline() }
        }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        // Debounced live lookup: `task(id:)` cancels and restarts whenever the
        // word changes, so the 300 ms sleep only completes once typing pauses.
        .task(id: row.word) {
            let term = row.trimmedWord
            guard !term.isEmpty else {
                lookup = .empty
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            lookup = env.lookup(term)
        }
    }

    // MARK: - Editors

    private var editors: some View {
        HStack(alignment: .top, spacing: 0) {
            TextField("", text: $row.word, prompt: wordPrompt)
                .textFieldStyle(.plain)
                .font(Mac.wordField)
                .autocorrectionDisabled()
                .focused($focus, equals: DraftFocus.word(row.id))
                .onSubmit(onReturn)
                .frame(width: Mac.wordColumnWidth, alignment: .leading)
                .accessibilityLabel("Word, row \(index + 1)")

            TextField("", text: $row.note, prompt: notePrompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Mac.notesField)
                .lineLimit(1...12)
                .focused($focus, equals: DraftFocus.note(row.id))
                .onSubmit(onReturn)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    // Column rule, drawn only where the two fields meet.
                    Rectangle()
                        .fill(Mac.hairline)
                        .frame(width: 0.5)
                        .opacity(0.7)
                }
                .accessibilityLabel("Notes, row \(index + 1)")

            deleteButton
        }
    }

    private var wordPrompt: Text? {
        index == 0 ? Text("word").font(Mac.wordField).foregroundStyle(.tertiary) : nil
    }

    private var notePrompt: Text? {
        index == 0 ? Text("what you want to remember").font(Mac.notesField).foregroundStyle(.tertiary) : nil
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        // A zero-opacity view still takes clicks; a delete button must not.
        .allowsHitTesting(isHovering)
        .help("Delete this row")
        .accessibilityLabel("Delete row \(index + 1)")
    }

    // MARK: - Live definition

    @ViewBuilder
    private var definitionStrip: some View {
        switch lookup {
        case .empty:
            EmptyView()

        case .unavailable:
            strip {
                Text("Dictionary unavailable")
                    .font(Mac.inline)
                    .foregroundStyle(.tertiary)
            }

        case .missing:
            // Quiet, never an error: the word may simply be a proper noun, a
            // phrase, or something the user is about to spell correctly.
            strip {
                Text("no entry")
                    .font(Mac.inline)
                    .foregroundStyle(.tertiary)
            }

        case .found(let word):
            Button {
                onInspect(word.word)
            } label: {
                strip {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(displayLines(for: word).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Mac.inline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open the full entry for “\(word.word)”")
        }
    }

    /// Up to three lines: ECDICT's Chinese translation when it has one, its
    /// English definition otherwise, prefixed with the phonetic.
    private func displayLines(for word: DictWord) -> [String] {
        var lines = word.translationLines
        if lines.isEmpty { lines = word.definitionLines }
        var display = Array(lines.prefix(3))
        let phonetic = word.phonetic.trimmingCharacters(in: .whitespaces)
        if !phonetic.isEmpty {
            if display.isEmpty {
                display = ["/\(phonetic)/"]
            } else {
                display[0] = "/\(phonetic)/  " + display[0]
            }
        }
        return display.isEmpty ? [word.word] : display
    }

    private func strip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if case .found(let word) = lookup {
            Button("Open “\(word.word)” in Inspector") { onInspect(word.word) }
            Divider()
        }
        Button("Insert Row Below") { onReturn() }
        Button("Move Up") { onMove(-1) }
        Button("Move Down") { onMove(1) }
        Divider()
        Button("Delete Row", role: .destructive) { onDelete() }
    }
}
