import Foundation

/// Read-write store for everything the user creates: lists, word states,
/// notes, study log, search history, and paused study sessions.
public final class UserStore {
    private let db: Database

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
                created_at REAL NOT NULL,
                position INTEGER NOT NULL DEFAULT 0
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
        for column in ["interval_days REAL", "ease_factor REAL", "stability REAL", "difficulty REAL",
                       "ebisu_alpha REAL", "ebisu_beta REAL", "ebisu_halflife REAL"] {
            _ = try? db.execute("ALTER TABLE word_state ADD COLUMN \(column)")
        }
        // Word-lists restructure: user-ordered lists, and the old builtin
        // "My Words" becomes an ordinary list (the aggregate view replaced it).
        _ = try? db.execute("ALTER TABLE lists ADD COLUMN position INTEGER NOT NULL DEFAULT 0")
        // Extended per-review data (nullable; recorded when the user allows
        // it) — the raw material for future per-user tuning.
        for column in ["grade INTEGER", "response_ms INTEGER",
                       "elapsed_days REAL", "scheduled_days REAL"] {
            _ = try? db.execute("ALTER TABLE study_log ADD COLUMN \(column)")
        }
        try db.execute("UPDATE lists SET is_builtin = 0 WHERE is_builtin = 1")
    }

    /// Groups many writes into one SQLite transaction (one fsync instead of
    /// hundreds — first-launch seeding depends on this).
    public func withTransaction(_ body: () -> Void) {
        _ = try? db.execute("BEGIN IMMEDIATE")
        body()
        _ = try? db.execute("COMMIT")
    }

    // MARK: - Lists

    public func lists() -> [WordList] {
        let rows = (try? db.execute("""
            SELECT l.id, l.name, l.is_builtin,
                   (SELECT COUNT(*) FROM list_words w WHERE w.list_id = l.id AND w.archived = 0) AS word_count
            FROM lists l
            ORDER BY l.position, l.created_at
        """)) ?? []
        return rows.map { row in
            WordList(id: row.int("id"), name: row.text("name"),
                     isBuiltin: row.int("is_builtin") == 1, wordCount: row.int("word_count"))
        }
    }

    @discardableResult
    public func createList(name: String) -> WordList? {
        var candidate = name
        var counter = 2
        while (try? db.execute("SELECT id FROM lists WHERE name = ?", [.text(candidate)]))?.isEmpty == false {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        let position = ((try? db.execute(
            "SELECT COALESCE(MAX(position), 0) AS p FROM lists"
        ))?.first?.int("p") ?? 0) + 1
        try? db.execute(
            "INSERT INTO lists (name, is_builtin, created_at, position) VALUES (?, 0, ?, ?)",
            [.text(candidate), .real(Date().timeIntervalSince1970), .int(Int64(position))]
        )
        return lists().first(where: { $0.name == candidate })
    }

    /// Swaps a list's position with its neighbor in display order. Rows
    /// predating the position column all carry 0, so the current display
    /// order is materialized into distinct positions before the first swap.
    public func moveList(id: Int, up: Bool) {
        var rows = orderedListRows()
        if Set(rows.map { $0.int("position") }).count != rows.count {
            for (index, row) in rows.enumerated() {
                try? db.execute("UPDATE lists SET position = ? WHERE id = ?",
                                [.int(Int64(index + 1)), .int(Int64(row.int("id")))])
            }
            rows = orderedListRows()
        }
        guard let index = rows.firstIndex(where: { $0.int("id") == id }) else { return }
        let neighborIndex = up ? index - 1 : index + 1
        guard rows.indices.contains(neighborIndex) else { return }
        let row = rows[index], neighbor = rows[neighborIndex]
        try? db.execute("UPDATE lists SET position = ? WHERE id = ?",
                        [.int(Int64(neighbor.int("position"))), .int(Int64(row.int("id")))])
        try? db.execute("UPDATE lists SET position = ? WHERE id = ?",
                        [.int(Int64(row.int("position"))), .int(Int64(neighbor.int("id")))])
    }

    private func orderedListRows() -> [Database.Row] {
        (try? db.execute("SELECT id, position FROM lists ORDER BY position, created_at")) ?? []
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
        if listID == WordList.aggregateID {
            // Distinct union across all lists, in list display order then
            // first-added order.
            let sql = """
                SELECT w.word FROM list_words w
                JOIN lists l ON l.id = w.list_id
                \(includeArchived ? "" : "WHERE w.archived = 0")
                GROUP BY w.word
                ORDER BY MIN(l.position), MIN(w.added_at)
            """
            let rows = (try? db.execute(sql)) ?? []
            return rows.map { $0.text("word") }
        }
        let sql = includeArchived
            ? "SELECT word FROM list_words WHERE list_id = ? ORDER BY position, added_at"
            : "SELECT word FROM list_words WHERE list_id = ? AND archived = 0 ORDER BY position, added_at"
        let rows = (try? db.execute(sql, [.int(Int64(listID))])) ?? []
        return rows.map { $0.text("word") }
    }

    public func archivedWords(in listID: Int) -> Set<String> {
        if listID == WordList.aggregateID {
            // A word only reads as archived in the aggregate when it is
            // archived in every list containing it.
            let rows = (try? db.execute(
                "SELECT word FROM list_words GROUP BY word HAVING MIN(archived) = 1"
            )) ?? []
            return Set(rows.map { $0.text("word").lowercased() })
        }
        let rows = (try? db.execute(
            "SELECT word FROM list_words WHERE list_id = ? AND archived = 1", [.int(Int64(listID))]
        )) ?? []
        return Set(rows.map { $0.text("word").lowercased() })
    }

    /// Distinct non-archived words across every list (the aggregate count).
    public func allWordsCount() -> Int {
        let rows = (try? db.execute(
            "SELECT COUNT(DISTINCT word) AS c FROM list_words WHERE archived = 0"
        )) ?? []
        return rows.first?.int("c") ?? 0
    }

    public func add(word: String, to listID: Int) {
        guard listID != WordList.aggregateID else { return }
        let position = ((try? db.execute(
            "SELECT COALESCE(MAX(position), 0) AS p FROM list_words WHERE list_id = ?", [.int(Int64(listID))]
        ))?.first?.int("p") ?? 0) + 1
        try? db.execute(
            "INSERT OR IGNORE INTO list_words (list_id, word, position, archived, added_at) VALUES (?,?,?,0,?)",
            [.int(Int64(listID)), .text(word), .int(Int64(position)), .real(Date().timeIntervalSince1970)]
        )
    }

    public func remove(word: String, from listID: Int) {
        guard listID != WordList.aggregateID else { return }
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
            note: row.text("note"),
            timesStudied: row.int("times_studied"),
            lastStudiedAt: row.optionalDouble("last_studied_at").map { Date(timeIntervalSince1970: $0) },
            nextPlannedAt: row.optionalDouble("next_planned_at").map { Date(timeIntervalSince1970: $0) },
            memoryCircle: row.int("memory_circle"),
            intervalDays: row.optionalDouble("interval_days"),
            easeFactor: row.optionalDouble("ease_factor"),
            stability: row.optionalDouble("stability"),
            difficulty: row.optionalDouble("difficulty"),
            ebisuAlpha: row.optionalDouble("ebisu_alpha"),
            ebisuBeta: row.optionalDouble("ebisu_beta"),
            ebisuHalflifeHours: row.optionalDouble("ebisu_halflife")
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
            INSERT INTO word_state (word, note, times_studied, last_studied_at, next_planned_at,
                                    memory_circle, interval_days, ease_factor, stability, difficulty,
                                    ebisu_alpha, ebisu_beta, ebisu_halflife)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(word) DO UPDATE SET
                note = excluded.note,
                times_studied = excluded.times_studied,
                last_studied_at = excluded.last_studied_at,
                next_planned_at = excluded.next_planned_at,
                memory_circle = excluded.memory_circle,
                interval_days = excluded.interval_days,
                ease_factor = excluded.ease_factor,
                stability = excluded.stability,
                difficulty = excluded.difficulty,
                ebisu_alpha = excluded.ebisu_alpha,
                ebisu_beta = excluded.ebisu_beta,
                ebisu_halflife = excluded.ebisu_halflife
        """, [
            .text(state.word),
            .text(state.note),
            .int(Int64(state.timesStudied)),
            state.lastStudiedAt.map { Database.Value.real($0.timeIntervalSince1970) } ?? .null,
            state.nextPlannedAt.map { Database.Value.real($0.timeIntervalSince1970) } ?? .null,
            .int(Int64(state.memoryCircle)),
            state.intervalDays.map { Database.Value.real($0) } ?? .null,
            state.easeFactor.map { Database.Value.real($0) } ?? .null,
            state.stability.map { Database.Value.real($0) } ?? .null,
            state.difficulty.map { Database.Value.real($0) } ?? .null,
            state.ebisuAlpha.map { Database.Value.real($0) } ?? .null,
            state.ebisuBeta.map { Database.Value.real($0) } ?? .null,
            state.ebisuHalflifeHours.map { Database.Value.real($0) } ?? .null,
        ])
    }

    /// Seeds scheduling state for "I already know this word" (the manual
    /// entry point that used to set a familiarity percentage): the rung maps
    /// to the circles ladder and the Ebisu observer starts believing the
    /// matching half-life. Information FOR the scheduler, never an override.
    public func seedKnownWord(_ word: String, rung: Int) {
        var s = state(of: word)
        let clamped = max(1, min(5, rung))
        if s.timesStudied == 0 { s.timesStudied = 1 }
        s.memoryCircle = max(s.memoryCircle, clamped)
        let seededInterval = Double(SRS.intervalDays(circle: clamped))
        if (s.intervalDays ?? 0) < seededInterval {
            s.intervalDays = seededInterval
            s.stability = max(s.stability ?? 0, seededInterval)
            s.lastStudiedAt = s.lastStudiedAt ?? Date()
            s.nextPlannedAt = Calendar.current.date(
                byAdding: .day, value: Int(seededInterval),
                to: Calendar.current.startOfDay(for: Date()))
        }
        if s.ebisuModel == nil {
            s.ebisuModel = EbisuModel.initial(intervalDays: seededInterval)
        }
        save(state: s)
    }

    /// Clears a word's learning state — schedule, ladder position, model
    /// fields, and the Ebisu observer — so it studies as brand new again.
    /// The note, list memberships, and the study log (history) are kept.
    public func resetProgress(for word: String) {
        var s = state(of: word)
        s.timesStudied = 0
        s.lastStudiedAt = nil
        s.nextPlannedAt = nil
        s.memoryCircle = 0
        s.intervalDays = nil
        s.easeFactor = nil
        s.stability = nil
        s.difficulty = nil
        s.ebisuModel = nil
        save(state: s)
    }

    public func setNote(_ note: String, for word: String) {
        var s = state(of: word)
        s.note = note
        save(state: s)
    }

    /// Import-time note handling: a word that already carries a different
    /// note keeps BOTH — the new note is appended on its own line. Returns
    /// true when a merge (append) happened, so imports can report it.
    @discardableResult
    public func mergeNote(_ note: String, for word: String) -> Bool {
        let incoming = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return false }
        var s = state(of: word)
        let existing = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            s.note = incoming
            save(state: s)
            return false
        }
        // Identical or already contained: nothing to merge.
        guard !existing.contains(incoming) else { return false }
        s.note = existing + "\n" + incoming
        save(state: s)
        return true
    }

    // MARK: - Study log / stats

    public func logStudy(word: String, knew: Bool, wasNew: Bool, at date: Date = Date(),
                         grade: Int? = nil, responseMs: Int? = nil,
                         elapsedDays: Double? = nil, scheduledDays: Double? = nil) {
        try? db.execute(
            """
            INSERT INTO study_log (word, studied_at, knew, was_new,
                                   grade, response_ms, elapsed_days, scheduled_days)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            [.text(word), .real(date.timeIntervalSince1970), .int(knew ? 1 : 0), .int(wasNew ? 1 : 0),
             grade.map { .int(Int64($0)) } ?? .null,
             responseMs.map { .int(Int64($0)) } ?? .null,
             elapsedDays.map { .real($0) } ?? .null,
             scheduledDays.map { .real($0) } ?? .null]
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

// MARK: - Data transfer (export / import / wipe)

extension UserStore {
    /// Tables included in a full data export, in restore order.
    public static let exportableTables = [
        "lists", "list_words", "word_state", "study_log",
        "search_history", "session_state",
    ]

    /// Full table dump as (column names, rows of stringified values).
    public func exportTable(_ table: String) -> (columns: [String], rows: [[String?]]) {
        guard Self.exportableTables.contains(table) else { return ([], []) }
        let info = (try? db.execute("PRAGMA table_info(\(table))")) ?? []
        let columns = info.map { $0.text("name") }
        let rows = (try? db.execute("SELECT * FROM \(table)")) ?? []
        return (columns, rows.map { row in columns.map { row.stringValue($0) } })
    }

    /// Replaces a table's contents from an export. Unknown columns are
    /// dropped so newer exports restore into older schemas and vice versa.
    public func importTable(_ table: String, columns: [String], rows: [[String?]]) {
        guard Self.exportableTables.contains(table), !columns.isEmpty else { return }
        let info = (try? db.execute("PRAGMA table_info(\(table))")) ?? []
        let known = Set(info.map { $0.text("name") })
        let kept = columns.enumerated().filter { known.contains($0.element) }
        guard !kept.isEmpty else { return }
        try? db.execute("DELETE FROM \(table)")
        let names = kept.map(\.element).joined(separator: ",")
        let placeholders = Array(repeating: "?", count: kept.count).joined(separator: ",")
        withTransaction {
            for row in rows {
                let values: [Database.Value] = kept.map { index, _ in
                    index < row.count ? (row[index].map { .text($0) } ?? .null) : .null
                }
                try? db.execute("INSERT OR REPLACE INTO \(table) (\(names)) VALUES (\(placeholders))", values)
            }
        }
    }

    /// Words with a scheduled interval but no FSRS stability — candidates
    /// for seeding when switching to FSRS.
    public func stabilitySeedCandidates() -> Int {
        let rows = (try? db.execute("""
            SELECT COUNT(*) AS c FROM word_state
            WHERE interval_days > 0 AND (stability IS NULL OR stability <= 0)
        """)) ?? []
        return rows.first?.int("c") ?? 0
    }

    /// Seeds FSRS stability from each word's current interval so the model
    /// starts from the schedule the previous algorithm had earned.
    @discardableResult
    public func seedStabilityFromIntervals() -> Int {
        let count = stabilitySeedCandidates()
        try? db.execute("""
            UPDATE word_state SET stability = interval_days
            WHERE interval_days > 0 AND (stability IS NULL OR stability <= 0)
        """)
        return count
    }

    public func wordsAboveLeitnerBoxes() -> Int {
        wordsWithCircleAbove(6)
    }

    /// Words whose ladder marker exceeds `circle` — used by the switch flow
    /// to describe how progress maps onto a shorter ladder.
    public func wordsWithCircleAbove(_ circle: Int) -> Int {
        let rows = (try? db.execute(
            "SELECT COUNT(*) AS c FROM word_state WHERE memory_circle > ?",
            [.int(Int64(circle))])) ?? []
        return rows.first?.int("c") ?? 0
    }

    public func hasPausedSessions() -> Bool {
        let rows = (try? db.execute("SELECT COUNT(*) AS c FROM session_state")) ?? []
        return (rows.first?.int("c") ?? 0) > 0
    }

    /// Removes the most recent study_log row for a word — the flashcard
    /// Undo affordance rolls back the log entry alongside the state snapshot.
    public func deleteLastLog(word: String) {
        try? db.execute("""
            DELETE FROM study_log WHERE rowid = (
                SELECT rowid FROM study_log WHERE word = ? ORDER BY studied_at DESC LIMIT 1
            )
        """, [.text(word)])
    }

    /// Recent correct-answer response times (ms) for the timed-input
    /// calibration, newest first.
    public func passResponseTimes(limit: Int = 500) -> [Int] {
        let rows = (try? db.execute("""
            SELECT response_ms FROM study_log
            WHERE knew = 1 AND response_ms IS NOT NULL
            ORDER BY studied_at DESC LIMIT ?
        """, [.int(Int64(limit))])) ?? []
        return rows.compactMap { $0.optionalDouble("response_ms").map { Int($0) } }
    }

    /// Nudges a word's memory strength up or down by whole tiers — the word
    /// page's "adjust" control, distinct from Reset. One step doubles (or
    /// halves) the interval and stability and moves the ladder rung one
    /// place, then reschedules from today, so every algorithm sees the
    /// adjustment in its own terms.
    public func adjustStrength(word: String, steps: Int) {
        guard steps != 0 else { return }
        var s = state(of: word)
        guard s.timesStudied > 0 else { return }
        let factor = pow(2.0, Double(steps))
        let interval = max(1.0 / 24, min(730, (s.intervalDays ?? 1) * factor))
        s.intervalDays = interval
        if let stability = s.stability {
            s.stability = max(0.01, min(36_500, stability * factor))
        }
        s.memoryCircle = max(1, min(12, s.memoryCircle + steps))
        if var model = s.ebisuModel {
            model.halflifeHours = max(1, min(24_000, model.halflifeHours * factor))
            s.ebisuModel = model
        }
        let calendar = Calendar.current
        if interval < 1 {
            s.nextPlannedAt = Date().addingTimeInterval(interval * 86_400)
        } else {
            s.nextPlannedAt = calendar.date(byAdding: .day, value: Int(interval.rounded()),
                                            to: calendar.startOfDay(for: Date()))
        }
        save(state: s)
    }

    /// Total logged reviews — gates the on-device optimizer.
    public func totalReviewCount() -> Int {
        let rows = (try? db.execute("SELECT COUNT(*) AS c FROM study_log")) ?? []
        return rows.first?.int("c") ?? 0
    }

    /// Per-word review sequences for optimizer training, ordered by time.
    /// Legacy binary rows map to Good/Again — the same mapping the schedulers
    /// have always applied.
    public func reviewSequences() -> [[FSRSOptimizer.Review]] {
        let rows = (try? db.execute(
            "SELECT word, studied_at, knew, grade FROM study_log ORDER BY word, studied_at"
        )) ?? []
        var sequences: [[FSRSOptimizer.Review]] = []
        var currentWord = ""
        var current: [FSRSOptimizer.Review] = []
        var lastAt: Double?
        for row in rows {
            let word = row.text("word")
            if word != currentWord {
                if current.count >= 2 { sequences.append(current) }
                currentWord = word
                current = []
                lastAt = nil
            }
            let at = row.optionalDouble("studied_at") ?? 0
            let grade = row.optionalDouble("grade").map { Int($0) } ?? (row.int("knew") == 1 ? 3 : 1)
            let elapsedDays = lastAt.map { max(0, (at - $0) / 86_400) } ?? 0
            current.append(FSRSOptimizer.Review(rating: min(4, max(1, grade)), elapsedDays: elapsedDays))
            lastAt = at
        }
        if current.count >= 2 { sequences.append(current) }
        return sequences
    }

    /// Erases every user table. The bundled dictionary is untouched.
    public func clearAllData() {
        for table in Self.exportableTables {
            try? db.execute("DELETE FROM \(table)")
        }
    }
}
