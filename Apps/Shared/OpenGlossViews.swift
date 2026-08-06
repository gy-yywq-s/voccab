import SwiftUI
import VocabKit

// The three OpenGloss dictionaries share one downloaded database and the
// "in a dictionary" rendering language of DictionaryRendering.swift: serif
// body, small-caps field labels over hairlines, and invisible jump links.

/// Shown in place of content while the OpenGloss resource is not on the
/// device (all three OpenGloss dictionaries need the same download).
struct OpenGlossUnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenGloss isn't downloaded yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Get it under Settings → Data → Resources. One download powers all three OpenGloss dictionaries.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

/// OpenGloss definitions: senses grouped by part of speech, numbered, with
/// examples set as indented italic serif lines.
struct OpenGlossDefinitionsView: View {
    let entry: OpenGlossEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(entry.sensesByPOS.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 12) {
                    DictionaryFieldLabel(text: group.pos)
                    ForEach(Array(group.senses.enumerated()), id: \.offset) { index, sense in
                        senseRow(number: index + 1, sense: sense)
                    }
                }
            }
        }
    }

    private func senseRow(number: Int, sense: OpenGlossSense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(DictionaryType.senseNumber)
                .foregroundStyle(.secondary)
                .frame(minWidth: 12, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                Text(sense.definition)
                    .font(DictionaryType.body)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(sense.examples.prefix(2).enumerated()), id: \.offset) { _, example in
                    Text("“\(example)”")
                        .font(Font.system(.subheadline, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !sense.synonyms.isEmpty {
                    SynonymFlowText(words: Array(sense.synonyms.prefix(8)))
                        .padding(.top, 1)
                }
            }
        }
    }
}

/// OpenGloss Usage: collocations and word forms — the "how it combines"
/// view. Every word and phrase is an invisible jump link.
struct OpenGlossUsageView: View {
    let entry: OpenGlossEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if entry.collocations.isEmpty && entry.inflections.isEmpty && entry.derivations.isEmpty {
                Text("No usage information for this word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.collocations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: "Collocations")
                    SynonymFlowText(words: Array(entry.collocations.prefix(24)))
                }
            }
            if !entry.inflections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: "Forms")
                    SynonymFlowText(words: entry.inflections)
                }
            }
            if !entry.derivations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: "Derived Words")
                    SynonymFlowText(words: entry.derivations)
                }
            }
        }
    }
}

/// OpenGloss Story: the word's origin and a short encyclopedia article,
/// set as calm serif reading paragraphs.
struct OpenGlossStoryView: View {
    let entry: OpenGlossEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if entry.etymology == nil && entry.encyclopedia == nil {
                Text("No story for this word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let etymology = entry.etymology {
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: "Origin")
                    ForEach(Array(paragraphs(of: etymology).enumerated()), id: \.offset) { _, paragraph in
                        styledParagraph(paragraph)
                    }
                }
            }
            if let encyclopedia = entry.encyclopedia {
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: "In Depth")
                    ForEach(Array(paragraphs(of: encyclopedia).enumerated()), id: \.offset) { _, paragraph in
                        styledParagraph(paragraph)
                    }
                }
            }
            Text("AI-written background — read as a story, not a source.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The encyclopedia text arrives as markdown; headings duplicating the
    /// headword are dropped and the rest becomes plain paragraphs with
    /// inline emphasis parsed where possible.
    private func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" }
    }

    private func styledParagraph(_ paragraph: String) -> some View {
        let attributed = (try? AttributedString(
            markdown: paragraph,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(paragraph)
        return Text(attributed)
            .font(DictionaryType.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}
