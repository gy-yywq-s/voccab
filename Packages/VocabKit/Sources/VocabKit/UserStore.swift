import Foundation

/// Read-write store for everything the user creates: lists, word states,
/// notes, study log, search history, and paused study sessions.
public final class UserStore {
    private let db: Database
    public static let myWordsName = "My Words"

    public init(databasePath: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: databasePath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        db = try Database(path: databasePath, mode: .readWrite)
        try migrate()
    }

    private func migrate() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS lists (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                is_builtin INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS list_words (
                list_id INTEGER NOT NULL,
                word TEXT NOT NULL COLLATE NOCASE,
                position INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0,
                added_at REAL NOT NULL,
                PRIMARY KEY (list_id, word)
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS word_state (
                word TEXT PRIMARY KEY COLLATE NOCASE,
                familiarity INTEGER,
                note TEXT NOT NULL DEFAULT '',
                times_studied INTEGER NOT NULL DEFAULT 0,
                last_studied_at REAL,
                next_planned_at REAL,
                memory_circle INTEGER NOT NULL DEFAULT 0
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS study_log (
                id INTEGER PRIMARY KEY,
                word TEXT NOT NULL COLLATE NOCASE,
                studied_at REAL NOT NULL,
                knew INTEGER NOT NULL,
                was_new INTEGER NOT NULL
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS search_history (
                term TEXT PRIMARY KEY COLLATE NOCASE,
                searched_at REAL NOT NULL
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS session_state (
                list_id INTEGER PRIMARY KEY,
                payload TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        // Scheduler columns added for the selectable-algorithms upgrade;
        // ALTER TABLE fails harmlessly when the column already exists.
        for column in ["interval_days REAL", "ease_factor REAL", "stability REAL", "difficulty REAL"] {
            _ = try? db.execute("ALTER TABLE word_state ADD COLUMN \(column)")
        }
        // Built-in favorites list.
        try db.execute(
            "INSERT OR IGNORE INTO lists (name, is_builtin, created_at) VALUES (?, 1, ?)",
            [.text(Self.myWordsName), .real(Date().timeIntervalSince1970)]
        )
    }

    /// Groups many writes into one SQLite transaction (one fsync instead of
    /// hundreds — first-launch seeding depends on this).
    public func withTransaction(_ body: () -> Void) {
        _ = try? db.execute("BEGIN IMMEDIATE")
        body()
        _ = try? db.execute("COMMIT")
    }

    // MARK: - Lists

    public func lists(includeBuiltin: Bool = true) -> [WordList] {
        let rows = (try? db.execute("""
            SELECT l.id, l.name, l.is_builtin,
                   (SELECT COUNT(*) FROM list_words w WHERE w.list_id = l.id AND w.archived = 0) AS word_count
            FROM lists l
            ORDER BY l.is_builtin DESC, l.created_at
        """)) ?? []
        return rows.compactMap { row in
            let isBuiltin = row.int("is_builtin") == 1
            if !includeBuiltin && isBuiltin { return nil }
            return WordList(id: row.int("id"), name: row.text("name"),
                            isBuiltin: isBuiltin, wordCount: row.int("word_count"))
        }
    }

    public func myWordsList() -> WordList {
        lists().first(where: { $0.isBuiltin }) ?? WordList(id: 1, name: Self.myWordsName, isBuiltin: true, wordCount: 0)
    }

    @discardableResult
    public func createList(name: String) -> WordList? {
        var candidate = name
        var counter = 2
        while (try? db.execute("SELECT id FROM lists WHERE name = ?", [.text(candidate)]))?.isEmpty == false {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        try? db.execute(
            "INSERT INTO lists (name, is_builtin, created_at) VALUES (?, 0, ?)",
            [.text(candidate), .real(Date().timeIntervalSince1970)]
        )
        return lists().first(where: { $0.name == candidate })
    }

    public func renameList(id: Int, to name: String) {
        try? db.execute("UPDATE lists SET name = ? WHERE id = ? AND is_builtin = 0", [.text(name), .int(Int64(id))])
    }

    public func deleteList(id: Int) {
        try? db.execute("DELETE FROM lists WHERE id = ? AND is_builtin = 0", [.int(Int64(id))])
        try? db.execute("DELETE FROM list_words WHERE list_id = ?", [.int(Int64(id))])
        try? db.execute("DELETE FROM session_state WHERE list_id = ?", [.int(Int64(id))])
    }

    // MARK: - List membership

    public func words(in listID: Int, includeArchived: Bool = false) -> [String] {
        let sql = includeArchived
            ? "SELECT word FROM list_words WHERE list_id = ? ORDER BY position, added_at"
            : "SELECT word FROM list_words WHERE list_id = ? AND archived = 0 ORDER BY position, added_at"
        let rows = (try? db.execute(sql, [.int(Int64(listID))])) ?? []
        return rows.map { $0.text("word") }
    }

    public func archivedWords(in listID: Int) -> Set<String> {
        let rows = (try? db.execute(
            "SELECT word FROM list_words WHERE list_id = ? AND archived = 1", [.int(Int64(listID))]
        )) ?? []
        return Set(rows.map { $0.text("word").lowercased() })
    }

    public func add(word: String, to listID: Int) {
        let position = ((try? db.execute(
            "SELECT COALESCE(MAX(position), 0) AS p FROM list_words WHERE list_id = ?", [.int(Int64(listID))]
        ))?.first?.int("p") ?? 0) + 1
        try? db.execute(
            "INSERT OR IGNORE INTO list_words (list_id, word, position, archived, added_at) VALUES (?,?,?,0,?)",
            [.int(Int64(listID)), .text(word), .int(Int64(position)), .real(Date().timeIntervalSince1970)]
        )
    }

    public func remove(word: String, from listID: Int) {
        try? db.execute("DELETE FROM list_words WHERE list_id = ? AND word = ?", [.int(Int64(listID)), .text(word)])
    }

    public func setArchived(_ archived: Bool, word: String, in listID: Int) {
        try? db.execute(
            "UPDATE list_words SET archived = ? WHERE list_id = ? AND word = ?",
            [.int(archived ? 1 : 0), .int(Int64(listID)), .text(word)]
        )
    }

    /// Names of the lists containing `word` (non-archived membership).
    public func listNames(containing word: String) -> [String] {
        let rows = (try? db.execute("""
            SELECT l.name FROM lists l
            JOIN list_words w ON w.list_id = l.id
            WHERE w.word = ? AND w.archived = 0
            ORDER BY l.is_builtin DESC, l.created_at
        """, [.text(word)])) ?? []
        return rows.map { $0.text("name") }
    }

    public func isWord(_ word: String, in listID: Int) -> Bool {
        let rows = (try? db.execute(
            "SELECT 1 AS x FROM list_words WHERE list_id = ? AND word = ?",
            [.int(Int64(listID)), .text(word)]
        )) ?? []
        return !rows.isEmpty
    }

    // MARK: - Word state

    public func state(of word: String) -> WordState {
        let rows = (try? db.execute(
            "SELECT * FROM word_state WHERE word = ?", [.text(word)]
        )) ?? []
        guard let row = rows.first else { return WordState(word: word) }
        return Self.state(from: row, word: word)
    }

    private static func state(from row: Database.Row, word: String) -> WordState {
        WordState(
            word: word,
            familiarity: row.optionalDouble("familiarity").map { Int($0) },
            note: row.text("note"),
            timesStudied: row.int("times_studied"),
            lastStudiedAt: row.optionalDouble("last_studied_at").map { Date(timeIntervalSince1970: $0) },
            nextPlannedAt: row.optionalDouble("next_planned_at").map { Date(timeIntervalSince1970: $0) },
            memoryCircle: row.int("memory_circle"),
            intervalDays: row.optionalDouble("interval_days"),
            easeFactor: row.optionalDouble("ease_factor"),
            stability: row.optionalDouble("stability"),
            difficulty: row.optionalDouble("difficulty")
        )
    }

    public func states(of words: [String]) -> [String: WordState] {
        var result: [String: WordState] = [:]
        for chunk in stride(from: 0, to: words.count, by: 400).map({ Array(words[$0..<min($0 + 400, words.count)]) }) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let rows = (try? db.execute(
                "SELECT * FROM word_state WHERE word COLLATE NOCASE IN (\(placeholders))",
                chunk.map { .text($0) }
            )) ?? []
            for row in rows {
                let word = row.text("word")
                result[word.lowercased()] = Self.state(from: row, word: word)
            }
        }
        return result
    }

    public func save(state: WordState) {
        try? db.execute("""
            INSERT INTO word_state (word, familiarity, note, times_studied, last_studied_at, next_planned_at,
                                    memory_circle, interval_days, ease_factor, stability, difficulty)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(word) DO UPDATE SET
                familiarity = excluded.familiarity,
                note = excluded.note,
                times_studied = excluded.times_studied,
                last_studied_at = excluded.last_studied_at,
                next_planned_at = excluded.next_planned_at,
                memory_circle = excluded.memory_circle,
                interval_days = excluded.interval_days,
                ease_factor = excluded.ease_factor,
                stability = excluded.stability,
                difficulty = excluded.difficulty
        """, [
            .text(state.word),
            state.familiarity.map { Database.Value.int(Int64($0)) } ?? .null,
            .text(state.note),
            .int(Int64(state.timesStudied)),
            state.lastStudiedAt.map { Database.Value.real($0.timeIntervalSince1970) } ?? .null,
            state.nextPlannedAt.map { Database.Value.real($0.timeIntervalSince1970) } ?? .null,
            .int(Int64(state.memoryCircle)),
            state.intervalDays.map { Database.Value.real($0) } ?? .null,
            state.easeFactor.map { Database.Value.real($0) } ?? .null,
            state.stability.map { Database.Value.real($0) } ?? .null,
            state.difficulty.map { Database.Value.real($0) } ?? .null,
        ])
    }

    public func setFamiliarity(_ value: Int?, for word: String) {
        var s = state(of: word)
        s.familiarity = value.map { min(100, max(0, $0)) }
        save(state: s)
    }

    public func setNote(_ note: String, for word: String) {
        var s = state(of: word)
        s.note = note
        save(state: s)
    }

    // MARK: - Study log / stats

    public func logStudy(word: String, knew: Bool, wasNew: Bool, at date: Date = Date()) {
        try? db.execute(
            "INSERT INTO study_log (word, studied_at, knew, was_new) VALUES (?,?,?,?)",
            [.text(word), .real(date.timeIntervalSince1970), .int(knew ? 1 : 0), .int(wasNew ? 1 : 0)]
        )
    }

    /// (new words studied, review words studied) since local midnight.
    public func todayCounts(calendar: Calendar = .current, now: Date = Date()) -> (newWords: Int, reviewed: Int) {
        let start = calendar.startOfDay(for: now).timeIntervalSince1970
        let rows = (try? db.execute("""
            SELECT
                COUNT(DISTINCT CASE WHEN was_new = 1 THEN word END) AS n,
                COUNT(DISTINCT CASE WHEN was_new = 0 THEN word END) AS r
            FROM study_log WHERE studied_at >= ?
        """, [.real(start)])) ?? []
        let row = rows.first
        return (row?.int("n") ?? 0, row?.int("r") ?? 0)
    }

    // MARK: - Search history

    public func recordSearch(term: String, at date: Date = Date()) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? db.execute("""
            INSERT INTO search_history (term, searched_at) VALUES (?,?)
            ON CONFLICT(term) DO UPDATE SET searched_at = excluded.searched_at
        """, [.text(trimmed), .real(date.timeIntervalSince1970)])
    }

    /// Searches within the last 7 days, newest first.
    public func recentSearches(now: Date = Date()) -> [SearchHistoryItem] {
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        try? db.execute("DELETE FROM search_history WHERE searched_at < ?", [.real(cutoff)])
        let rows = (try? db.execute(
            "SELECT term, searched_at FROM search_history WHERE searched_at >= ? ORDER BY searched_at DESC LIMIT 50",
            [.real(cutoff)]
        )) ?? []
        return rows.map {
            SearchHistoryItem(term: $0.text("term"), searchedAt: Date(timeIntervalSince1970: $0.double("searched_at")))
        }
    }

    // MARK: - Paused sessions

    public func savePausedSession(listID: Int, payload: String) {
        try? db.execute("""
            INSERT INTO session_state (list_id, payload, updated_at) VALUES (?,?,?)
            ON CONFLICT(list_id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
        """, [.int(Int64(listID)), .text(payload), .real(Date().timeIntervalSince1970)])
    }

    public func pausedSession(listID: Int) -> String? {
        let rows = (try? db.execute(
            "SELECT payload FROM session_state WHERE list_id = ?", [.int(Int64(listID))]
        )) ?? []
        return rows.first?.text("payload")
    }

    public func clearPausedSession(listID: Int) {
        try? db.execute("DELETE FROM session_state WHERE list_id = ?", [.int(Int64(listID))])
    }
}
