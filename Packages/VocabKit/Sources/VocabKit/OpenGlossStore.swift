import Foundation

/// One sense from an OpenGloss entry: a definition with its examples and
/// per-sense semantic neighbours, grouped under a part of speech.
public struct OpenGlossSense: Codable, Hashable, Sendable {
    public var pos: String
    public var definition: String
    public var synonyms: [String]
    public var antonyms: [String]
    public var examples: [String]

    public init(pos: String, definition: String, synonyms: [String] = [],
                antonyms: [String] = [], examples: [String] = []) {
        self.pos = pos
        self.definition = definition
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.examples = examples
    }
}

/// A full OpenGloss record for one lexeme, feeding all three OpenGloss
/// dictionaries: senses (OpenGloss), collocations/forms (Usage), and
/// etymology/encyclopedia (Story).
public struct OpenGlossEntry: Sendable {
    public var word: String
    public var senses: [OpenGlossSense]
    public var collocations: [String]
    public var inflections: [String]
    public var derivations: [String]
    public var etymology: String?
    public var encyclopedia: String?

    /// Senses grouped by part of speech, preserving sense order.
    public var sensesByPOS: [(pos: String, senses: [OpenGlossSense])] {
        var order: [String] = []
        var grouped: [String: [OpenGlossSense]] = [:]
        for sense in senses {
            if grouped[sense.pos] == nil { order.append(sense.pos) }
            grouped[sense.pos, default: []].append(sense)
        }
        return order.map { ($0, grouped[$0]!) }
    }
}

/// Read-only access to the downloadable OpenGloss database. The data is a
/// synthetic (LLM-generated) dictionary — 150k lexemes with senses,
/// collocations, forms, etymology and encyclopedic notes — converted from
/// the published parquet release by `Data/tools/build_opengloss.py`.
public final class OpenGlossStore {
    private let db: Database

    /// Where the downloaded database lives once the resource is installed.
    public static var databaseURL: URL {
        ResourceManager.downloadsDirectory
            .appendingPathComponent("dict.opengloss", isDirectory: true)
            .appendingPathComponent("opengloss.sqlite")
    }

    /// True when the OpenGloss resource is on this device.
    public static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    public init?() {
        guard Self.isAvailable,
              let database = try? Database(path: Self.databaseURL.path, mode: .readOnly) else {
            return nil
        }
        db = database
    }

    public func entry(for term: String) -> OpenGlossEntry? {
        let rows = (try? db.execute(
            """
            SELECT word, senses, collocations, inflections, derivations,
                   etymology, encyclopedia
            FROM entries WHERE word = ? COLLATE NOCASE LIMIT 1
            """,
            [.text(term)]
        )) ?? []
        guard let row = rows.first else { return nil }

        func list(_ column: String) -> [String] {
            row.text(column).split(separator: "\t").map(String.init)
        }
        let senses = (try? JSONDecoder().decode(
            [OpenGlossSense].self,
            from: Data(row.text("senses").utf8))) ?? []
        let etymology = row.text("etymology")
        let encyclopedia = row.text("encyclopedia")
        return OpenGlossEntry(
            word: row.text("word"),
            senses: senses,
            collocations: list("collocations"),
            inflections: list("inflections"),
            derivations: list("derivations"),
            etymology: etymology.isEmpty ? nil : etymology,
            encyclopedia: encyclopedia.isEmpty ? nil : encyclopedia)
    }
}
