import Foundation

/// CSV import matching the original app: columns `word` and optional `note`.
public enum CSVImport {

    public struct ImportedRow: Hashable, Sendable {
        public var word: String
        public var note: String
    }

    public enum ImportError: Error, Equatable {
        case empty
        case missingWordColumn
    }

    /// Decodes an imported file: UTF-8 first, then UTF-16 (BOM), then
    /// GB18030 (Excel on Chinese systems), then Latin-1 as a last resort.
    public static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .unicode) { return text }
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gbEncoding) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Recognized header spellings for the word / note columns.
    private static let wordHeaders: Set<String> = [
        "word", "words", "term", "vocab", "vocabulary", "单词", "词", "词汇",
    ]
    private static let noteHeaders: Set<String> = [
        "note", "notes", "meaning", "definition", "translation", "gloss",
        "释义", "笔记", "备注", "解释", "意思", "翻译",
    ]

    /// Parses a pasted or uploaded word table. Accepts:
    /// - CSV / TSV / semicolon-separated (quoted fields, escaped quotes,
    ///   CRLF), so a direct copy-paste from Excel / Numbers / Sheets works
    /// - an optional header row naming the word/note columns (several
    ///   spellings, English and Chinese); headerless tables use the first
    ///   column as the word and the rest as the note
    /// - plain lines: one word per line, optionally "word - note",
    ///   "word — note" or "word: note", with leading "1." / "2)" numbering
    ///   stripped
    public static func parse(_ text: String) throws -> [ImportedRow] {
        var content = text
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }

        let rows: [[String]]
        if let delimiter = detectDelimiter(content) {
            rows = parseRaw(content, delimiter: delimiter)
        } else {
            rows = plainLines(content)
        }
        guard let first = rows.first, !first.isEmpty else { throw ImportError.empty }

        let headerCells = first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let headerWordIndex = headerCells.firstIndex(where: { wordHeaders.contains($0) })
        let wordIndex = headerWordIndex ?? 0
        let noteIndex = headerWordIndex == nil
            ? nil
            : headerCells.firstIndex(where: { noteHeaders.contains($0) })
        let dataRows = headerWordIndex == nil ? rows : Array(rows.dropFirst())

        var result: [ImportedRow] = []
        var seen: Set<String> = []
        for row in dataRows {
            guard wordIndex < row.count else { continue }
            let word = row[wordIndex].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty, word.rangeOfCharacter(from: .letters) != nil else { continue }
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let note: String
            if let noteIndex, noteIndex < row.count {
                note = row[noteIndex].trimmingCharacters(in: .whitespaces)
            } else {
                // No named note column: everything after the word column.
                note = row.enumerated()
                    .filter { $0.offset != wordIndex }
                    .map { $0.element.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
            }
            result.append(ImportedRow(word: word, note: note))
        }
        // A header-looking first row with no data rows usually means a paste
        // lost its line breaks; surface diagnostics instead of guessing.
        guard !result.isEmpty else { throw ImportError.empty }
        return result
    }

    /// One-line description of how the text parsed, for import error alerts.
    public static func diagnose(_ text: String) -> String {
        var content = text
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        let delimiter = detectDelimiter(content)
        let rows = delimiter.map { parseRaw(content, delimiter: $0) } ?? plainLines(content)
        let delimiterName = delimiter.map {
            $0 == "\t" ? "tab" : ($0 == ";" ? "semicolon" : "comma")
        } ?? "none (plain lines)"
        let maxColumns = rows.map(\.count).max() ?? 0
        var hints: [String] = []
        if rows.count <= 1 && maxColumns > 3 {
            hints.append("looks like line breaks were lost in a paste — try importing the file instead")
        }
        return "Parsed \(rows.count) row(s), up to \(maxColumns) column(s), delimiter: \(delimiterName)."
            + (hints.isEmpty ? "" : " Hint: \(hints.joined(separator: "; "))")
    }

    /// Tab wins (Excel paste), then semicolon vs comma by count; nil means
    /// no table delimiter at all — fall back to plain-line parsing.
    private static func detectDelimiter(_ text: String) -> Character? {
        if text.contains("\t") { return "\t" }
        let commas = text.filter { $0 == "," }.count
        let semicolons = text.filter { $0 == ";" }.count
        if semicolons > commas { return ";" }
        if commas > 0 { return "," }
        return nil
    }

    /// One entry per line; supports "word - note" style separators and
    /// strips leading list numbering.
    private static func plainLines(_ text: String) -> [[String]] {
        let separators = [" - ", " — ", " – ", "：", ": "]
        return text
            .components(separatedBy: .newlines)
            .map { line -> [String] in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                // Strip "1." / "23)" / "4、" list numbering.
                if let match = trimmed.range(of: "^\\d+[.)、]\\s*", options: .regularExpression) {
                    trimmed = String(trimmed[match.upperBound...])
                }
                guard !trimmed.isEmpty else { return [] }
                for separator in separators {
                    if let range = trimmed.range(of: separator) {
                        return [
                            String(trimmed[..<range.lowerBound]),
                            String(trimmed[range.upperBound...]),
                        ]
                    }
                }
                return [trimmed]
            }
            .filter { !$0.isEmpty }
    }

    private static func parseRaw(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case delimiter:
                    endField()
                case "\r":
                    if let next = iterator.next() {
                        if next == "\n" { endRow() } else {
                            endRow()
                            pending = next
                        }
                    } else {
                        endRow()
                    }
                case "\n":
                    endRow()
                default:
                    field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// Imports rows into a new list — or, when `mergeInto` is given, into an
    /// existing list. Notes land on the word state either way.
    @discardableResult
    /// Words whose existing notes were merged (not overwritten) during the
    /// last `importRows` call — read right after importing to report it.
    public private(set) static var lastMergedNoteCount = 0

    public static func importRows(
        _ rows: [ImportedRow],
        listName: String,
        userStore: UserStore,
        mergeInto existingListID: Int? = nil
    ) -> WordList? {
        let targetID: Int
        if let existingListID {
            targetID = existingListID
        } else {
            // Auto-suffix instead of failing when the name is taken.
            var name = listName
            var attempt = 2
            var created = userStore.createList(name: name)
            while created == nil && attempt <= 20 {
                name = "\(listName) (\(attempt))"
                created = userStore.createList(name: name)
                attempt += 1
            }
            guard let list = created else { return nil }
            targetID = list.id
        }
        var merged = 0
        userStore.withTransaction {
            for row in rows {
                userStore.add(word: row.word, to: targetID)
                if !row.note.isEmpty {
                    if userStore.mergeNote(row.note, for: row.word) { merged += 1 }
                }
            }
        }
        lastMergedNoteCount = merged
        return userStore.lists().first(where: { $0.id == targetID })
    }
}
