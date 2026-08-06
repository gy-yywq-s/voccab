import Foundation
import VocabKit

/// Export / import / wipe of everything the user owns. Exports are plain
/// CSVs, optionally bundled into a stored (uncompressed) ZIP together with
/// a settings snapshot and README-DATA.md documenting every file — the same
/// ZIP can be imported back to restore the account.
enum DataTransfer {

    // MARK: CSV

    static func csv(columns: [String], rows: [[String?]]) -> String {
        func field(_ value: String?) -> String {
            guard let value else { return "" }
            if value.contains(where: { ",\"\n\r".contains($0) }) {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
        var lines = [columns.map { field($0) }.joined(separator: ",")]
        for row in rows {
            lines.append(row.map { field($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseCSV(_ text: String) -> (columns: [String], rows: [[String?]])? {
        guard let parsed = try? SimpleCSV.parse(text), let header = parsed.first else { return nil }
        return (header, parsed.dropFirst().map { $0.map { $0.isEmpty ? nil : $0 } })
    }

    // MARK: Single-file exports

    static func exportCSV(table: String, from store: UserStore, name: String) -> URL? {
        let (columns, rows) = store.exportTable(table)
        guard !columns.isEmpty else { return nil }
        return writeTemp(name: name, data: Data(csv(columns: columns, rows: rows).utf8))
    }

    // MARK: Full ZIP

    static func exportAll(store: UserStore, settings: AppSettings) -> URL? {
        var entries: [(String, Data)] = []
        for table in UserStore.exportableTables {
            let (columns, rows) = store.exportTable(table)
            guard !columns.isEmpty else { continue }
            entries.append(("\(table).csv", Data(csv(columns: columns, rows: rows).utf8)))
        }
        entries.append(("settings.json", settingsJSON(settings)))
        entries.append(("README-DATA.md", Data(readme.utf8)))
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return writeTemp(name: "voccab-export-\(stamp).zip", data: Zip.archive(entries))
    }

    /// Restores tables + settings from a Voccab export ZIP.
    /// Returns a human-readable summary, or nil if nothing was recognized.
    static func importAll(from url: URL, store: UserStore, settings: AppSettings) -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let entries = Zip.extract(data)
        guard !entries.isEmpty else { return nil }
        var restored: [String] = []
        for table in UserStore.exportableTables {
            guard let entry = entries["\(table).csv"],
                  let text = String(data: entry, encoding: .utf8),
                  let (columns, rows) = parseCSV(text) else { continue }
            store.importTable(table, columns: columns, rows: rows)
            restored.append("\(table) (\(rows.count))")
        }
        if let entry = entries["settings.json"],
           let json = try? JSONSerialization.jsonObject(with: entry) as? [String: String] {
            applySettings(json, to: settings)
            restored.append("settings")
        }
        return restored.isEmpty ? nil : restored.joined(separator: ", ")
    }

    static func clearAll(store: UserStore) {
        store.clearAllData()
    }

    // MARK: Settings snapshot

    static func settingsJSON(_ settings: AppSettings) -> Data {
        let snapshot: [String: String] = [
            "scheduler": settings.scheduler.rawValue,
            "studyOrder": settings.studyOrder.rawValue,
            "answerStyle": settings.answerStyle.rawValue,
            "graduationPolicy": settings.graduationPolicy.rawValue,
            "pronunciationAccent": settings.pronunciationAccent.rawValue,
            "pronunciationSource": settings.pronunciationSource.rawValue,
            "dailyGoalNew": String(settings.dailyGoalNew),
            "dailyGoalReview": String(settings.dailyGoalReview),
            "recordExtendedData": String(settings.recordExtendedData),
            "enabledDictionaries": settings.enabledDictionaries.map(\.rawValue).joined(separator: ","),
        ]
        return (try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])) ?? Data()
    }

    static func applySettings(_ json: [String: String], to settings: AppSettings) {
        if let v = json["scheduler"].flatMap(SchedulerKind.init) { settings.scheduler = v }
        if let v = json["studyOrder"].flatMap(StudyOrder.init) { settings.studyOrder = v }
        if let v = json["answerStyle"].flatMap(AnswerStyle.init) { settings.answerStyle = v }
        if let v = json["graduationPolicy"].flatMap(GraduationPolicy.init) { settings.graduationPolicy = v }
        if let v = json["pronunciationAccent"].flatMap(PronunciationAccent.init) { settings.pronunciationAccent = v }
        if let v = json["pronunciationSource"].flatMap(PronunciationSource.init) { settings.pronunciationSource = v }
        if let v = json["dailyGoalNew"].flatMap({ Int($0) }) { settings.dailyGoalNew = v }
        if let v = json["dailyGoalReview"].flatMap({ Int($0) }) { settings.dailyGoalReview = v }
        if let v = json["recordExtendedData"].flatMap({ Bool($0) }) { settings.recordExtendedData = v }
        if let v = json["enabledDictionaries"] {
            settings.enabledDictionaries = v.split(separator: ",").compactMap { DictionarySource(rawValue: String($0)) }
        }
    }

    private static func writeTemp(name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static let readme = """
    # Voccab data export

    Everything in this archive is plain text; the ZIP itself is stored
    (uncompressed) so any tool can open it, and Voccab can import this exact
    file back via Settings → Data → Import from ZIP.

    ## Files

    - `lists.csv` — your word lists. Columns: id, name, is_builtin (legacy,
      always 0), created_at (Unix seconds), position (display order).
    - `list_words.csv` — list membership. Columns: list_id (→ lists.id),
      word, position, archived (0/1), added_at (Unix seconds).
    - `word_state.csv` — one row per word you've touched. Columns: word,
      familiarity (legacy, unused — kept only so old exports round-trip),
      note, times_studied, last_studied_at, next_planned_at (Unix seconds),
      memory_circle, interval_days, ease_factor (SM-2), stability +
      difficulty (FSRS), ebisu_alpha + ebisu_beta + ebisu_halflife (the
      Ebisu recall observer: Beta(α, β) belief anchored at the halflife
      in hours; drives the predicted-recall percentages).
    - `study_log.csv` — every review. Columns: id, word, studied_at (Unix
      seconds), knew (0/1), was_new (0/1), grade (1 Again / 2 Hard /
      3 Good / 4 Easy; empty for old binary rows), response_ms,
      elapsed_days (actual gap before this review), scheduled_days
      (the gap the scheduler had planned). The last four are recorded only
      while “Record detailed review data” is on.
    - `search_history.csv` — recent lookups. Columns: term, searched_at.
    - `session_state.csv` — paused practice sessions. Columns: list_id
      (-1 = All Words), payload (JSON), updated_at.
    - `settings.json` — app settings snapshot (algorithm, order, answer
      style, graduation policy, goals, dictionaries, voice).

    Words are keyed case-insensitively. Timestamps are Unix seconds UTC.
    """
}

/// Minimal quoted-CSV reader for our own exports.
enum SimpleCSV {
    static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?
        func endField() { row.append(field); field = "" }
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
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else {
                switch ch {
                case "\"" where field.isEmpty: inQuotes = true
                case ",": endField()
                case "\r": break
                case "\n": endRow()
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
