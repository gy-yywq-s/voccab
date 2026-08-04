import Foundation

/// Read-only access to the bundled dictionary database, plus an optional
/// extras database (Webster 1913 / Moby Thesaurus).
public final class DictionaryStore {
    private let db: Database
    private let extras: Database?

    public init(databasePath: String, extrasPath: String? = nil) throws {
        db = try Database(path: databasePath, mode: .readOnly)
        extras = extrasPath.flatMap { try? Database(path: $0, mode: .readOnly) }
    }

    private static let columns =
        "id, word, phonetic, translation, definition, pos, collins, oxford, tag, bnc, frq, exchange"

    private func word(from row: Database.Row) -> DictWord {
        DictWord(
            id: row.int("id"),
            word: row.text("word"),
            phonetic: row.text("phonetic"),
            translation: row.text("translation"),
            definition: row.text("definition"),
            pos: row.text("pos"),
            collins: row.int("collins"),
            oxford: row.int("oxford"),
            tag: row.text("tag"),
            bnc: row.int("bnc"),
            frq: row.int("frq"),
            exchange: row.text("exchange")
        )
    }

    public func lookup(_ term: String) -> DictWord? {
        let rows = (try? db.execute(
            "SELECT \(Self.columns) FROM words WHERE word = ? COLLATE NOCASE LIMIT 1",
            [.text(term)]
        )) ?? []
        return rows.first.map(word(from:))
    }

    public func lookup(words terms: [String]) -> [String: DictWord] {
        var result: [String: DictWord] = [:]
        for chunk in stride(from: 0, to: terms.count, by: 400).map({ Array(terms[$0..<min($0 + 400, terms.count)]) }) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let rows = (try? db.execute(
                "SELECT \(Self.columns) FROM words WHERE word COLLATE NOCASE IN (\(placeholders))",
                chunk.map { .text($0) }
            )) ?? []
            for row in rows {
                let w = word(from: row)
                result[w.word.lowercased()] = w
            }
        }
        return result
    }

    /// Prefix suggestions ordered by frequency, used while typing.
    public func suggestions(prefix: String, limit: Int = 12) -> [DictWord] {
        let escaped = prefix
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let rows = (try? db.execute(
            """
            SELECT \(Self.columns) FROM words
            WHERE word LIKE ? ESCAPE '\\' COLLATE NOCASE
            ORDER BY CASE WHEN frq > 0 THEN frq WHEN bnc > 0 THEN bnc ELSE 9999999 END
            LIMIT ?
            """,
            [.text(escaped + "%"), .int(Int64(limit))]
        )) ?? []
        return rows.map(word(from:))
    }

    /// Similar words for the chip row (edit-distance-1 style candidates like
    /// the original's corsage/corkage/wordage suggestions).
    public func similarWords(to term: String, limit: Int = 6) -> [DictWord] {
        let lower = term.lowercased()
        guard lower.count >= 3 else { return [] }
        var patterns: Set<String> = []
        let chars = Array(lower)
        // one substitution
        for i in 0..<chars.count {
            var c = chars
            c[i] = "_"
            patterns.insert(String(c))
        }
        // one deletion of the input (word is input minus one char)
        for i in 0..<chars.count {
            var c = chars
            c.remove(at: i)
            patterns.insert(String(c))
        }
        // one insertion (word is input plus one char)
        for i in 0...chars.count {
            var c = chars.map(String.init)
            c.insert("_", at: i)
            patterns.insert(c.joined())
        }
        var results: [DictWord] = []
        var seen: Set<String> = [lower]
        for pattern in patterns.sorted() {
            let rows = (try? db.execute(
                """
                SELECT \(Self.columns) FROM words
                WHERE word LIKE ? COLLATE NOCASE AND length(word) = ?
                ORDER BY CASE WHEN frq > 0 THEN frq WHEN bnc > 0 THEN bnc ELSE 9999999 END
                LIMIT 3
                """,
                [.text(pattern), .int(Int64(pattern.count))]
            )) ?? []
            for row in rows {
                let w = word(from: row)
                let key = w.word.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(w)
                }
            }
            if results.count >= limit { break }
        }
        return Array(results.prefix(limit))
    }

    /// True when the bundled database carries the user-installed Oxford table.
    public lazy var hasOxfordData: Bool = {
        let rows = (try? db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='oxford'"
        )) ?? []
        return !rows.isEmpty
    }()

    /// The Oxford entry for a word, split into paragraphs for display.
    /// The source data separates senses with em-dash part-of-speech markers.
    public func oxfordEntry(for term: String) -> [String]? {
        guard hasOxfordData else { return nil }
        let rows = (try? db.execute(
            "SELECT meaning FROM oxford WHERE word = ? COLLATE NOCASE LIMIT 1",
            [.text(term)]
        )) ?? []
        guard let meaning = rows.first?.text("meaning"), !meaning.isEmpty else { return nil }
        let paragraphs = meaning
            .replacingOccurrences(of: "—", with: "\n—")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [meaning] : paragraphs
    }

    /// Webster's 1913 / GCIDE entry, split into display paragraphs.
    public func websterEntry(for term: String) -> [String]? {
        guard let extras else { return nil }
        let rows = (try? extras.execute(
            "SELECT definition FROM webster WHERE word = ? COLLATE NOCASE LIMIT 1",
            [.text(term)]
        )) ?? []
        guard let definition = rows.first?.text("definition"), !definition.isEmpty else { return nil }
        let paragraphs = definition
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? nil : paragraphs
    }

    /// Moby Thesaurus synonyms.
    public func mobySynonyms(for term: String) -> [String]? {
        guard let extras else { return nil }
        let rows = (try? extras.execute(
            "SELECT synonyms FROM moby WHERE word = ? COLLATE NOCASE LIMIT 1",
            [.text(term)]
        )) ?? []
        guard let synonyms = rows.first?.text("synonyms"), !synonyms.isEmpty else { return nil }
        let list = synonyms.split(separator: ",").map(String.init)
        return list.isEmpty ? nil : list
    }

    public func senses(for term: String) -> [WordNetSense] {
        let rows = (try? db.execute(
            """
            SELECT pos, sense_num, gloss, examples, synonyms FROM wordnet
            WHERE word = ? COLLATE NOCASE
            ORDER BY pos, sense_num
            """,
            [.text(term)]
        )) ?? []
        return rows.map { row in
            WordNetSense(
                pos: row.text("pos"),
                senseNum: row.int("sense_num"),
                gloss: row.text("gloss"),
                examples: row.text("examples").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                synonyms: row.text("synonyms").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
        }
    }

    /// Derived forms of `term` found via the exchange column, plus (when the
    /// term itself is derived) its base form. Powers the "Related" tab.
    public func relatedForms(of dictWord: DictWord) -> [(label: String, words: [String])] {
        var sections: [(String, [String])] = []
        if let base = dictWord.baseForm {
            sections.append(("Base Form", [base]))
        }
        var grouped: [ExchangeForm.Kind: [String]] = [:]
        for form in dictWord.exchangeForms where form.kind != .lemma && form.kind != .lemmaVariant {
            grouped[form.kind, default: []].append(form.word)
        }
        let order: [ExchangeForm.Kind] = [.plural, .past, .pastParticiple, .presentParticiple, .thirdPerson, .comparative, .superlative]
        for kind in order {
            if let words = grouped[kind], !words.isEmpty {
                var deduped: [String] = []
                for w in words where !deduped.contains(w) && w.lowercased() != dictWord.word.lowercased() {
                    deduped.append(w)
                }
                if !deduped.isEmpty {
                    sections.append((kind.label, deduped))
                }
            }
        }
        return sections
    }
}
