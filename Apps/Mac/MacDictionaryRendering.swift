import SwiftUI
import VocabKit

// Dictionary-entry formatting for the Mac inspector.
//
// The formatting *ideas* come from the iOS `Apps/Shared/DictionaryRendering`:
// serif body prose, gray lowercase part-of-speech lines, small gray sense
// numbers, italic examples, small-caps field labels over a hairline, and
// synonyms as running text rather than a wall of buttons. The implementation is
// its own, because `Apps/Shared` is UIKit-bound and never reaches this target —
// and because a Mac inspector is a narrow column, not a phone page, so
// everything here is a size or two tighter.

// MARK: - ECDICT translation lines

/// One `n. 花束, 胸花` line: the part-of-speech tag pulled into a gutter so the
/// definitions line up down the column.
struct MacTranslationLine: View {
    let line: String

    private static let knownPOS = [
        "n.", "v.", "vt.", "vi.", "a.", "adj.", "adv.", "pron.",
        "prep.", "conj.", "interj.", "num.", "art.", "aux.",
    ]

    private var parts: (pos: String?, body: String) {
        for prefix in Self.knownPOS where line.hasPrefix(prefix) {
            return (prefix, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, line)
    }

    var body: some View {
        let parts = parts
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let pos = parts.pos {
                Text(pos)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
            }
            Text(parts.body)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Synonyms as running text

/// A wrapping comma-separated run where every word is clickable — it retargets
/// the inspector — yet styled as plain prose: primary ink, no underline, no
/// blue. The interactivity stays invisible so the block reads like a printed
/// thesaurus paragraph.
struct MacSynonymFlow: View {
    let words: [String]
    /// Render the first word as the bold lead, the way a thesaurus group opens.
    var boldLead = false
    /// Suppress the last comma (off when a following chunk continues the run).
    var terminal = true
    var onSelect: (String) -> Void

    var body: some View {
        MacFlowLayout(spacing: 5, lineSpacing: 7) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button {
                    onSelect(word)
                } label: {
                    label(for: word,
                          lead: boldLead && index == 0,
                          comma: !(terminal && index == words.count - 1))
                }
                .buttonStyle(.plain)
                .help("Look up “\(word)”")
            }
        }
    }

    private func label(for word: String, lead: Bool, comma: Bool) -> Text {
        var text = Text(word)
            .font(lead ? Mac.dictionaryLead : Mac.dictionaryBody)
            .foregroundStyle(.primary)
        if comma {
            text = text + Text(",")
                .font(Mac.dictionaryBody)
                .foregroundStyle(.secondary)
        }
        return text
    }
}

/// WordNet synonym groups, one small-caps part-of-speech label per group.
struct MacSynonymSections: View {
    let sections: [(pos: String, synonyms: [String])]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if sections.isEmpty {
                Text("No synonyms found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    MacFieldLabel(text: section.pos)
                    MacSynonymFlow(words: section.synonyms, boldLead: true, onSelect: onSelect)
                }
            }
        }
    }
}

/// Moby's very long lists, broken into a few flowing paragraphs so the wall of
/// words gets air.
struct MacThesaurusParagraphs: View {
    let words: [String]
    var chunkSize = 18
    var onSelect: (String) -> Void

    private var chunks: [[String]] {
        stride(from: 0, to: words.count, by: chunkSize).map {
            Array(words[$0..<min($0 + chunkSize, words.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                MacSynonymFlow(words: chunk,
                               terminal: index == chunks.count - 1,
                               onSelect: onSelect)
            }
        }
    }
}

// MARK: - Webster / GCIDE

/// A GCIDE entry parsed into part-of-speech sections of numbered senses, with
/// the "; as, …" example idiom split out for italic rendering.
///
/// Robust by construction: any paragraph that does not match the expected shape
/// simply becomes an unnumbered sense, so the worst case is clean serif prose.
struct MacWebsterEntry {

    struct Sense {
        var number: String?
        var definition: String
        var example: String?
    }

    struct Section {
        var partOfSpeech: String?
        var senses: [Sense]
    }

    var sections: [Section]

    /// GCIDE's abbreviations expanded into the words Apple Dictionary prints.
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

    static func parse(_ paragraphs: [String]) -> MacWebsterEntry {
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
        return MacWebsterEntry(sections: sections)
    }

    private static func expandPOS(_ tag: String) -> String? {
        let lower = tag.lowercased()
        if let name = posNames[lower] { return name }
        // Accept short abbreviation-shaped tags ("a. superl.", "prep. & adv.")
        // verbatim; anything longer is prose, not a tag.
        let posShaped = !lower.isEmpty && lower.count <= 16
            && lower.contains(".")
            && lower.allSatisfy { $0.isLetter || $0 == "." || $0 == " " || $0 == "&" }
        return posShaped ? lower : nil
    }

    private static func makeSense(from paragraph: String) -> Sense {
        var text = paragraph
        var number: String?

        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2, text.dropFirst(digits.count).hasPrefix(". ") {
            number = String(digits)
            text = String(text.dropFirst(digits.count + 2)).trimmingCharacters(in: .whitespaces)
        }

        var definition = text
        var example: String?
        if let range = text.range(of: "; as, ") {
            let candidate = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty {
                definition = String(text[..<range.lowerBound])
                example = candidate
            }
        }
        return Sense(number: number, definition: definition, example: example)
    }
}

/// Renders a Webster entry: gray lowercase part-of-speech line, then each sense
/// as a serif paragraph with a small gray number in the gutter and the example
/// italicised after a colon. The headword is not repeated — it already leads
/// the inspector.
struct MacWebsterEntryView: View {
    let paragraphs: [String]

    var body: some View {
        let entry = MacWebsterEntry.parse(paragraphs)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    if let pos = section.partOfSpeech {
                        Text(pos)
                            .font(Mac.serif(12).italic())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(section.senses.enumerated()), id: \.offset) { _, sense in
                        senseRow(sense)
                    }
                }
            }
        }
    }

    private func senseRow(_ sense: MacWebsterEntry.Sense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(sense.number ?? "")
                .font(Mac.serif(11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            senseText(sense)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func senseText(_ sense: MacWebsterEntry.Sense) -> Text {
        var text = Text(sense.definition)
            .font(Mac.dictionaryBody)
            .foregroundStyle(.primary)
        if let example = sense.example {
            text = text
                + Text(": ").font(Mac.dictionaryBody).foregroundStyle(.secondary)
                + Text(example).font(Mac.dictionaryBody.italic()).foregroundStyle(.secondary)
        }
        return text
    }
}

// MARK: - WordNet senses

/// WordNet definitions grouped by part of speech, numbered within each group,
/// with up to two examples in quiet italics.
struct MacSenseSections: View {
    let senses: [WordNetSense]
    /// ECDICT's English lines, shown only when WordNet has nothing.
    let fallbackLines: [String]

    private static let posOrder = ["noun", "verb", "adjective", "adverb"]

    private var orderedPOS: [String] {
        let present = senses.map(\.pos)
        var result = Self.posOrder.filter { present.contains($0) }
        for pos in present where !result.contains(pos) { result.append(pos) }
        return result
    }

    var body: some View {
        let grouped = Dictionary(grouping: senses, by: \.pos)
        VStack(alignment: .leading, spacing: 18) {
            if senses.isEmpty {
                if fallbackLines.isEmpty {
                    Text("No English definition available.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fallbackLines, id: \.self) { line in
                        Text(line)
                            .font(Mac.dictionaryBody)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(orderedPOS, id: \.self) { pos in
                VStack(alignment: .leading, spacing: 8) {
                    MacFieldLabel(text: pos)
                    ForEach(Array((grouped[pos] ?? []).enumerated()), id: \.offset) { index, sense in
                        senseRow(index: index, sense: sense)
                    }
                }
            }
        }
    }

    private func senseRow(index: Int, sense: WordNetSense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(index + 1)")
                .font(Mac.serif(11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(capitalizedGloss(sense.gloss))
                    .font(Mac.dictionaryBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(sense.examples.prefix(2), id: \.self) { example in
                    Text("“\(example)”")
                        .font(Mac.dictionaryBody.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func capitalizedGloss(_ gloss: String) -> String {
        guard let first = gloss.first else { return gloss }
        let body = first.uppercased() + gloss.dropFirst()
        return body.hasSuffix(".") ? body : body + "."
    }
}
