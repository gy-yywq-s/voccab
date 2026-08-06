import Foundation

/// Where everything this app owns lives: the draft, its backup, and the user's
/// library database. Deliberately free of actor isolation, because the
/// termination handler reaches for it from whatever thread it is on.
enum VoccabMacPaths {
    static let supportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoccabMac", isDirectory: true)
}

/// Atomic, backed-up, thread-safe storage for the draft.
///
/// Design notes, because losing typed words is the one unacceptable failure:
///
/// * **Staged, not pushed.** The store hands the latest document to `stage(_:)`
///   on every keystroke. Writing is decoupled from staging, so a flush from any
///   thread at any moment always writes the newest text.
/// * **Synchronous flush.** `flush()` does its file I/O inline under a lock, so
///   `applicationWillTerminate` — which does not wait for tasks — can call it
///   and be certain the bytes landed. An async save would be racing the process.
/// * **Rotate then write.** The previous good `draft.json` is copied to
///   `draft.backup.json` before the new one is written, and the new one goes
///   down with `.atomic` (temp file + rename), so there is never a moment where
///   both files are half-written.
/// * **Quarantine on corruption.** If `draft.json` fails to decode, it is moved
///   aside to `draft.corrupt-<timestamp>.json` rather than left in place: if it
///   stayed, the next rotation would copy the corrupt file over the good backup.
final class DraftPersistence: @unchecked Sendable {

    static let shared = DraftPersistence(directory: VoccabMacPaths.supportDirectory)

    struct LoadResult {
        var document: DraftDocument
        /// The main file was unreadable and the backup stood in.
        var recoveredFromBackup = false
        /// Where the unreadable file was parked, if it was.
        var quarantinedAt: URL?
        /// No draft existed yet — a first launch.
        var isFirstLaunch = false
    }

    let directory: URL
    let mainURL: URL
    let backupURL: URL

    private let lock = NSLock()
    private var pending: DraftDocument?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Readable on purpose: if every other recovery path fails, the user can
        // still open the file in TextEdit and see their words.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL) {
        self.directory = directory
        self.mainURL = directory.appendingPathComponent("draft.json")
        self.backupURL = directory.appendingPathComponent("draft.backup.json")
    }

    // MARK: - Loading

    func load() -> LoadResult {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let mainExists = fileManager.fileExists(atPath: mainURL.path)
        let backupExists = fileManager.fileExists(atPath: backupURL.path)

        if let document = decodeFile(at: mainURL) {
            return LoadResult(document: document)
        }
        if mainExists {
            // Park the unreadable file so the next rotation cannot overwrite a
            // good backup with it.
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory.appendingPathComponent("draft.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: mainURL, to: quarantine)
            if let document = decodeFile(at: backupURL) {
                return LoadResult(document: document, recoveredFromBackup: true, quarantinedAt: quarantine)
            }
            return LoadResult(document: .starter, quarantinedAt: quarantine)
        }
        if backupExists, let document = decodeFile(at: backupURL) {
            return LoadResult(document: document, recoveredFromBackup: true)
        }
        return LoadResult(document: .starter, isFirstLaunch: true)
    }

    private func decodeFile(at url: URL) -> DraftDocument? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? decoder.decode(DraftDocument.self, from: data)
    }

    // MARK: - Saving

    /// Records the newest state. Cheap: no file I/O.
    func stage(_ document: DraftDocument) {
        lock.lock()
        pending = document
        lock.unlock()
    }

    /// Writes the staged document, if any. Returns true when bytes were
    /// written. Safe to call from any thread, including during termination.
    @discardableResult
    func flush() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var document = pending else { return false }
        document.savedAt = Date()
        do {
            try write(document)
            pending = nil
            return true
        } catch {
            // Keep the document staged so the next attempt retries it.
            return false
        }
    }

    /// True when there is unwritten text waiting.
    var hasPendingWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }

    private func write(_ document: DraftDocument) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)

        if fileManager.fileExists(atPath: mainURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: mainURL, to: backupURL)
        }
        try data.write(to: mainURL, options: [.atomic])
    }
}
