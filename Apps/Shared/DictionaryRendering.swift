import SwiftUI

// Shared dictionary-entry formatting, used by both frontends' word pages.
// The look is modeled on Apple Dictionary / Apple Thesaurus: serif body
// text, gray lowercase part-of-speech lines, small gray sense numbers,
// italic gray examples, small-caps field labels over a hairline — and
// synonym jump links that read as running text, not buttons.

// MARK: - Type roles

enum DictionaryType {
    /// Serif body for definition/thesaurus prose (Apple Dictionary uses
    /// New York for entry text).
    static let body = Font.system(.body, design: .serif)
    /// Lead synonym of a thesaurus group: semibold small-caps serif.
    static let lead = Font.system(.body, design: .serif).weight(.semibold).smallCaps()
    /// Gray lowercase part-of-speech line ("adjective").
    static let partOfSpeech = Font.system(.subheadline, design: .serif).italic()
    /// Small gray sense numbers in the left gutter.
    static let senseNumber = Font.system(.footnote, design: .serif)
}

// MARK: - Small-caps field label ("DERIVATIVES" / "NOUN" style)

/// Uppercase tracked caption with a hairline underneath — the Apple
/// Dictionary section-label idiom (DERIVATIVES, ORIGIN, …).
struct DictionaryFieldLabel: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text.uppercased())
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Synonym running text with invisible jump links

/// A wrapping run of comma-separated words where every word is tappable
/// (navigates to that word's page) yet styled as plain body text — primary
/// ink, no underline, no blue — so the interactivity stays invisible and
/// the block reads like a printed thesaurus paragraph.
struct SynonymFlowText: View {
    let words: [String]
    /// Render the first word as the bold small-caps lead (Apple Thesaurus
    /// leads each group with the headword-like key synonym).
    var boldLead = false
    /// Suppress the trailing comma of the last word (off when the caller
    /// continues the run in a following chunk).
    var terminal = true

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                NavigationLink(value: Route.wordDetail(word: word, context: [])) {
                    label(for: word,
                          lead: boldLead && index == 0,
                          comma: !(terminal && index == words.count - 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(for word: String, lead: Bool, comma: Bool) -> Text {
        var text = Text(word)
            .font(lead ? DictionaryType.lead : DictionaryType.body)
            .foregroundStyle(.primary)
        if comma {
            text = text + Text(",")
                .font(DictionaryType.body)
                .foregroundStyle(.secondary)
        }
        return text
    }
}

// MARK: - WordNet synonyms (Apple Thesaurus layout, less dense)

/// Synonym groups by part of speech: a small-caps gray pos label over a
/// hairline, then the synonyms as flowing tappable text with the lead
/// synonym emphasized.
struct SynonymSectionsView: View {
    let sections: [(pos: String, synonyms: [String])]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if sections.isEmpty {
                Text("No synonyms found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    DictionaryFieldLabel(text: section.pos)
                    SynonymFlowText(words: section.synonyms, boldLead: true)
                }
            }
        }
    }
}

// MARK: - Moby Thesaurus (flowing paragraphs)

/// One long thesaurus list rendered as a few flowing comma-separated
/// paragraphs (chunked so the wall of words gets breathing room).
struct ThesaurusParagraphsView: View {
    let words: [String]
    var chunkSize = 20

    private var chunks: [[String]] {
        stride(from: 0, to: words.count, by: chunkSize).map {
            Array(words[$0..<min($0 + chunkSize, words.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                SynonymFlowText(words: chunk,
                                terminal: index == chunks.count - 1)
            }
        }
    }
}

// MARK: - Webster / GCIDE entry

/// A GCIDE entry parsed into part-of-speech sections of numbered senses,
/// with the "; as, …" example idiom split out for italic rendering.
struct WebsterEntry {
    struct Sense {
        var number: String?     // "1", "2", … or nil for unnumbered defs
        var definition: String
        var example: String?    // the example following "as," / a colon
    }

    struct Section {
        var partOfSpeech: String?   // expanded: "adjective", "transitive verb"
        var senses: [Sense]
    }

    var sections: [Section]

    /// Abbreviated GCIDE pos tags → the full lowercase words Apple
    /// Dictionary uses.
    private static let posNames: [String: String] = [
        "a.": "adjective",
        "adj.": "adjective",
        "n.": "noun",
        "n. pl.": "plural noun",
        "v.": "verb",
        "v. t.": "transitive verb",
        "v. i.": "intransitive verb",
        "v. t. & i.": "verb",
        "v. i. & t.": "verb",
        "adv.": "adverb",
        "prep.": "preposition",
        "conj.": "conjunction",
        "interj.": "interjection",
        "pron.": "pronoun",
        "p. p.": "past participle",
        "p. pr.": "present participle",
        "p. pr. & vb. n.": "present participle",
        "imp.": "imperfect",
        "imp. & p. p.": "past tense",
        "superl.": "superlative",
        "compar.": "comparative",
    ]

    /// Robust by construction: any paragraph that doesn't match the
    /// numbered/pos structure simply becomes an unnumbered sense, so the
    /// worst case is clean serif paragraphs.
    static func parse(_ paragraphs: [String]) -> WebsterEntry {
        var sections: [Section] = []
        var current = Section(partOfSpeech: nil, senses: [])

        func flush() {
            if current.partOfSpeech != nil || !current.senses.isEmpty {
                sections.append(current)
            }
        }

        for raw in paragraphs {
            var text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            // A leading "(pos)" tag opens a new part-of-speech section.
            if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
                let tag = String(text[text.index(after: text.startIndex)..<close])
                    .trimmingCharacters(in: .whitespaces)
                if let pos = expandPOS(tag) {
                    flush()
                    current = Section(partOfSpeech: pos, senses: [])
                    text = String(text[text.index(after: close)...])
                        .trimmingCharacters(in: .whitespaces)
                    if text.isEmpty { continue }
                }
            }
            current.senses.append(makeSense(from: text))
        }
        flush()
        return WebsterEntry(sections: sections)
    }

    private static func expandPOS(_ tag: String) -> String? {
        let lower = tag.lowercased()
        if let name = posNames[lower] { return name }
        // Accept short abbreviation-shaped tags ("a. superl.", "prep. & adv.")
        // verbatim; anything longer is prose, not a pos tag.
        let posShaped = lower.count <= 16 && !lower.isEmpty
            && lower.allSatisfy { $0.isLetter || $0 == "." || $0 == " " || $0 == "&" }
            && lower.contains(".")
        return posShaped ? lower : nil
    }

    private static func makeSense(from paragraph: String) -> Sense {
        var text = paragraph
        var number: String? = nil

        // Leading "3. " sense marker.
        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2,
           text.dropFirst(digits.count).hasPrefix(". ") {
            number = String(digits)
            text = String(text.dropFirst(digits.count + 2))
                .trimmingCharacters(in: .whitespaces)
        }

        // GCIDE's example idiom is "; as, a serene sky." — split it out so
        // the view can render "definition: example" with the example italic.
        var definition = text
        var example: String? = nil
        if let range = text.range(of: "; as, ") {
            let candidate = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty {
                definition = String(text[..<range.lowerBound])
                example = candidate
            }
        }
        return Sense(number: number, definition: definition, example: example)
    }
}

/// Renders a Webster/GCIDE entry in Apple Dictionary's layout: gray
/// lowercase pos line, then each sense as an indented serif paragraph with
/// a small gray sense number, examples in italic gray after a colon. The
/// headword itself is NOT repeated — it already leads the page.
struct WebsterEntryView: View {
    let paragraphs: [String]

    var body: some View {
        let entry = WebsterEntry.parse(paragraphs)
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    if let pos = section.partOfSpeech {
                        Text(pos)
                            .font(DictionaryType.partOfSpeech)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(section.senses.enumerated()), id: \.offset) { _, sense in
                        senseRow(sense)
                    }
                }
            }
        }
    }

    private func senseRow(_ sense: WebsterEntry.Sense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(sense.number ?? "")
                .font(DictionaryType.senseNumber)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 22, alignment: .leading)
            senseText(sense)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func senseText(_ sense: WebsterEntry.Sense) -> Text {
        var text = Text(sense.definition)
            .font(DictionaryType.body)
            .foregroundStyle(.primary)
        if let example = sense.example {
            text = text
                + Text(": ").font(DictionaryType.body).foregroundStyle(.secondary)
                + Text(example).font(DictionaryType.body.italic()).foregroundStyle(.secondary)
        }
        return text
    }
}
