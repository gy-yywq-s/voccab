import SwiftUI
import VocabKit

/// The right-hand inspector: the full entry for one word.
///
/// The Mac-native place for "more about the thing you just clicked" is an
/// inspector, not a sheet — a sheet would block the workspace, and the whole
/// point is to keep reading definitions while you keep typing words.
struct WordInspectorView: View {
    /// Lookup history, so clicking a synonym can be walked back.
    @Binding var history: [String]

    @EnvironmentObject private var env: MacEnvironment
    @State private var detail: MacWordDetail?

    private var term: String? { history.last }

    var body: some View {
        Group {
            if let term {
                content(term: term)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Mac.chrome)
        .task(id: term) {
            guard let term else {
                detail = nil
                return
            }
            detail = env.detail(for: term)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Click a definition in the workspace\nto read the full entry here.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(term: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(term: term)
                if let detail {
                    if detail.isEmpty {
                        Text("No dictionary entry for “\(term)”.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    translations(detail)
                    englishDefinitions(detail)
                    synonyms(detail)
                    webster(detail)
                    moby(detail)
                    related(detail)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private func header(term: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if history.count > 1 {
                Button {
                    _ = history.popLast()
                } label: {
                    Label {
                        Text(history[history.count - 2])
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(detail?.dictWord?.word ?? term)
                .font(Mac.headword)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let phonetic = detail?.dictWord?.phonetic.trimmingCharacters(in: .whitespaces),
               !phonetic.isEmpty {
                Text("/\(phonetic)/")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let chips = chipLabels, !chips.isEmpty {
                MacFlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(chips, id: \.self) { MacChip(text: $0) }
                }
            }
        }
    }

    private var chipLabels: [String]? {
        guard let word = detail?.dictWord else { return nil }
        var labels: [String] = []
        if word.rank > 0 { labels.append(Formatting.frequencyChip(word.frequencyBand)) }
        if let tag = examTagChipLabel(word.examTags) { labels.append(tag) }
        if word.collins > 0 { labels.append(String(repeating: "★", count: min(5, word.collins))) }
        return labels
    }

    // MARK: - Sections

    @ViewBuilder
    private func translations(_ detail: MacWordDetail) -> some View {
        let lines = detail.dictWord?.translationLines ?? []
        if !lines.isEmpty {
            section("English–Chinese") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.self) { MacTranslationLine(line: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private func englishDefinitions(_ detail: MacWordDetail) -> some View {
        let fallback = detail.dictWord?.definitionLines ?? []
        if !detail.senses.isEmpty || !fallback.isEmpty {
            section("English definition") {
                MacSenseSections(senses: detail.senses, fallbackLines: fallback)
            }
        }
    }

    @ViewBuilder
    private func synonyms(_ detail: MacWordDetail) -> some View {
        let sections = detail.synonymSections
        if !sections.isEmpty {
            section("Synonyms") {
                MacSynonymSections(sections: sections, onSelect: navigate)
            }
        }
    }

    @ViewBuilder
    private func webster(_ detail: MacWordDetail) -> some View {
        if let paragraphs = detail.webster, !paragraphs.isEmpty {
            section("Webster 1913") {
                MacWebsterEntryView(paragraphs: paragraphs)
            }
        }
    }

    @ViewBuilder
    private func moby(_ detail: MacWordDetail) -> some View {
        if let words = detail.moby, !words.isEmpty {
            section("Moby Thesaurus") {
                MacThesaurusParagraphs(words: words, onSelect: navigate)
            }
        }
    }

    @ViewBuilder
    private func related(_ detail: MacWordDetail) -> some View {
        if !detail.related.isEmpty {
            section("Related forms") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(detail.related.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            MacSynonymFlow(words: group.words, onSelect: navigate)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MacFieldLabel(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Navigation

    private func navigate(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != term?.lowercased() else { return }
        history.append(trimmed)
        // A workspace session can wander a long way through the thesaurus;
        // keep the trail bounded.
        if history.count > 40 { history.removeFirst(history.count - 40) }
    }
}
