import Foundation

/// One line of the workspace: a word and whatever the user wants to remember
/// alongside it.
struct DraftRow: Identifiable, Codable, Hashable {
    var id: UUID
    var word: String
    var note: String

    init(id: UUID = UUID(), word: String = "", note: String = "") {
        self.id = id
        self.word = word
        self.note = note
    }

    var trimmedWord: String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmedWord.isEmpty && trimmedNote.isEmpty
    }

    /// A row worth importing or exporting: it has a word.
    var isSubstantive: Bool {
        !trimmedWord.isEmpty
    }
}

/// The on-disk shape of the draft.
///
/// `formatVersion` exists so a future change can migrate rather than discard;
/// a decoder that does not recognise the version still gets the rows, because
/// rows are the only thing that must never be lost.
struct DraftDocument: Codable {
    var formatVersion: Int
    var savedAt: Date
    var rows: [DraftRow]

    init(formatVersion: Int = DraftDocument.currentFormatVersion,
         savedAt: Date = Date(),
         rows: [DraftRow] = []) {
        self.formatVersion = formatVersion
        self.savedAt = savedAt
        self.rows = rows
    }

    static let currentFormatVersion = 1

    /// A draft that always has somewhere to type.
    static var starter: DraftDocument {
        DraftDocument(rows: [DraftRow()])
    }
}
