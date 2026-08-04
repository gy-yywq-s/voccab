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

    /// Parses RFC-4180-ish CSV (quoted fields, escaped quotes, CRLF).
    public static func parse(_ text: String) throws -> [ImportedRow] {
        let rows = parseRaw(text)
        guard let header = rows.first, !header.isEmpty else { throw ImportError.empty }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let wordIndex = normalized.firstIndex(of: "word") else {
            // Headerless single-column files: treat every line as a word.
            if normalized.count == 1 {
                return rows.compactMap { row in
                    let word = row.first?.trimmingCharacters(in: .whitespaces) ?? ""
                    return word.isEmpty ? nil : ImportedRow(word: word, note: "")
                }
            }
            throw ImportError.missingWordColumn
        }
        let noteIndex = normalized.firstIndex(of: "note")
        var result: [ImportedRow] = []
        var seen: Set<String> = []
        for row in rows.dropFirst() {
            guard wordIndex < row.count else { continue }
            let word = row[wordIndex].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            var note = ""
            if let noteIndex, noteIndex < row.count {
                note = row[noteIndex].trimmingCharacters(in: .whitespaces)
            }
            result.append(ImportedRow(word: word, note: note))
        }
        guard !result.isEmpty else { throw ImportError.empty }
        return result
    }

    private static func parseRaw(_ text: String) -> [[String]] {
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
                case ",":
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

    /// Imports rows into a new list; notes land on the word state.
    @discardableResult
    public static func importRows(
        _ rows: [ImportedRow],
        listName: String,
        userStore: UserStore
    ) -> WordList? {
        guard let list = userStore.createList(name: listName) else { return nil }
        for row in rows {
            userStore.add(word: row.word, to: list.id)
            if !row.note.isEmpty {
                userStore.setNote(row.note, for: row.word)
            }
        }
        return userStore.lists().first(where: { $0.id == list.id })
    }
}
