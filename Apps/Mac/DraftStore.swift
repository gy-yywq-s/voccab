import AppKit
import Combine
import Foundation

/// The workspace's document model: the rows, the editing operations, and the
/// autosave policy.
///
/// Autosave has three independent triggers, on purpose:
///   1. a 1 s debounce after the last edit (the normal case),
///   2. every app lifecycle edge that precedes losing the process — window
///      close, resigning active, termination — flushed **synchronously**,
///   3. ⌘S, for people who do not trust software.
@MainActor
final class DraftStore: ObservableObject {

    @Published var rows: [DraftRow] {
        didSet { markDirty() }
    }

    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var hasUnsavedChanges = false

    /// One-off message about how the draft came back (backup recovery), shown
    /// once in the footer and dismissible.
    @Published var restoreNotice: String?

    /// Set by the store when a row should take keyboard focus; the view moves
    /// focus and clears it.
    @Published var pendingFocus: UUID?

    /// Which row the user is editing. Written by the view, read by ⌘N so a new
    /// row lands below the caret instead of at the bottom of the page.
    /// Published so the Draft menu's row-move items enable and disable with it.
    @Published var focusedRowID: UUID?

    private let persistence: DraftPersistence
    private var saveTask: Task<Void, Never>?

    /// Notification tokens live in a plain, unisolated box that unregisters
    /// them when it goes away, so the store needs no `deinit` reaching back
    /// into main-actor state.
    private final class ObserverBag: @unchecked Sendable {
        var tokens: [NSObjectProtocol] = []

        deinit {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    private nonisolated let observers = ObserverBag()

    private static let debounce: UInt64 = 1_000_000_000  // 1 s

    init(persistence: DraftPersistence = .shared) {
        self.persistence = persistence
        let result = persistence.load()
        // Property observers do not fire during init, so this assignment does
        // not schedule a save — a restore is not an edit.
        self.rows = result.document.rows.isEmpty ? [DraftRow()] : result.document.rows
        self.lastSavedAt = result.isFirstLaunch ? nil : result.document.savedAt

        if result.recoveredFromBackup {
            restoreNotice = "Restored from the backup draft — the main file could not be read."
        } else if result.quarantinedAt != nil {
            restoreNotice = "The draft file could not be read; it was kept aside and a new draft was started."
        }
        installLifecycleHooks()
    }

    // MARK: - Derived state

    var document: DraftDocument {
        DraftDocument(savedAt: lastSavedAt ?? Date(), rows: rows)
    }

    /// Rows that carry a word — the ones import and export care about.
    var substantiveRows: [DraftRow] {
        rows.filter(\.isSubstantive)
    }

    var isEmptyDraft: Bool {
        rows.allSatisfy(\.isBlank)
    }

    // MARK: - Editing

    /// Inserts a row below `id` (or below the focused row, or at the end) and
    /// asks the view to put the caret in it.
    @discardableResult
    func newRow(below id: UUID? = nil) -> UUID {
        let anchor = id ?? focusedRowID
        let row = DraftRow()
        if let anchor, let index = rows.firstIndex(where: { $0.id == anchor }) {
            rows.insert(row, at: index + 1)
        } else {
            rows.append(row)
        }
        pendingFocus = row.id
        return row.id
    }

    func delete(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: index)
        if rows.isEmpty { rows = [DraftRow()] }
        // Keep the caret in the table: fall onto the row that took its place,
        // or the one above if we deleted the last.
        let next = min(index, rows.count - 1)
        pendingFocus = rows[next].id
    }

    func move(id: UUID, by offset: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard rows.indices.contains(destination) else { return }
        rows.swapAt(index, destination)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
    }

    /// Wipes the draft back to a single empty row. Guarded by a confirmation in
    /// the UI — nothing here asks.
    func clear() {
        rows = [DraftRow()]
        pendingFocus = rows[0].id
        saveNow()
    }

    /// Drops rows that hold nothing at all, keeping at least one to type into.
    func removeBlankRows() {
        let kept = rows.filter { !$0.isBlank }
        rows = kept.isEmpty ? [DraftRow()] : kept
    }

    // MARK: - Autosave

    private func markDirty() {
        hasUnsavedChanges = true
        persistence.stage(document)
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: DraftStore.debounce)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes right now (⌘S, and the tail of the debounce).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        persistence.stage(document)
        if persistence.flush() {
            lastSavedAt = Date()
        }
        hasUnsavedChanges = persistence.hasPendingWrite
    }

    /// Flushes on every edge where the process might not come back.
    ///
    /// The observers deliberately capture only `persistence` — never `self` —
    /// and pass `queue: nil` so the block runs synchronously on the posting
    /// thread. Hopping to the main actor here would mean scheduling work that
    /// termination never gets around to running. Because `markDirty` stages the
    /// document on every keystroke, the staged copy is always current.
    private func installLifecycleHooks() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.willTerminateNotification,
            NSApplication.willResignActiveNotification,
            NSApplication.willHideNotification,
            NSWindow.willCloseNotification,
        ]
        let persistence = self.persistence
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                persistence.flush()
            }
            observers.tokens.append(token)
        }
    }
}
