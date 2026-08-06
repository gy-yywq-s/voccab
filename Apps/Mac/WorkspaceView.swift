import SwiftUI
import VocabKit

/// The main window: a two-column document you type words into, with the
/// dictionary answering underneath each line as you go.
struct WorkspaceView: View {
    @ObservedObject var store: DraftStore
    @EnvironmentObject private var env: MacEnvironment

    @FocusState private var focus: DraftFocus?

    @State private var inspectorHistory: [String] = []
    @State private var showInspector = false
    @State private var showImport = false
    @State private var confirmClear = false
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        page
            .inspector(isPresented: $showInspector) {
                WordInspectorView(history: $inspectorHistory)
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
            }
            .toolbar { toolbar }
            .frame(minWidth: Mac.minWindowWidth, minHeight: Mac.minWindowHeight)
            .sheet(isPresented: $showImport) {
                ImportSheet(rows: store.rows) {
                    // The import wrote into the library; the draft stays put on
                    // purpose, so offer the clear rather than performing it.
                    show(flash: "Imported. Use Draft ▸ Clear Draft when you are done with these rows.")
                }
                .environmentObject(env)
            }
            .alert("Clear the draft?", isPresented: $confirmClear) {
                Button("Clear Draft", role: .destructive) {
                    store.clear()
                    inspectorHistory = []
                    show(flash: "Draft cleared.")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every drafted word and note is removed. This cannot be undone, and it does not touch anything already imported into your library.")
            }
    }

    // MARK: - Page

    private var page: some View {
        VStack(spacing: 0) {
            columnHeader
            MacHairline()
            rowsScroller
            MacHairline()
            footer
        }
        .background(Mac.paper)
        .onChange(of: focus) { _, newValue in
            store.focusedRowID = Self.rowID(of: newValue)
        }
        .onAppear {
            if focus == nil, let first = store.rows.first {
                focus = DraftFocus.word(first.id)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("WORD")
                .frame(width: Mac.wordColumnWidth, alignment: .leading)
            Text("NOTES")
                .padding(.leading, 14)
            Spacer(minLength: 0)
        }
        .font(Mac.columnHeader)
        .tracking(1.2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Mac.pageInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Mac.chrome)
    }

    private var rowsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                        DraftRowView(
                            row: binding(for: row.id),
                            index: index,
                            isLast: index == store.rows.count - 1,
                            focus: $focus,
                            onReturn: { store.newRow(below: row.id) },
                            onDelete: { store.delete(id: row.id) },
                            onMove: { store.move(id: row.id, by: $0) },
                            onInspect: inspect
                        )
                        .id(row.id)
                    }

                    // Clicking the empty space below the last row starts a new
                    // one — the behaviour every list-shaped editor has.
                    Color.clear
                        .frame(height: 120)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if store.rows.last?.isBlank == true {
                                focus = store.rows.last.map { DraftFocus.word($0.id) }
                            } else {
                                store.newRow(below: store.rows.last?.id)
                            }
                        }
                }
            }
            // Focus and scrolling are driven from one handler so their order is
            // never in question: the row is brought on screen, takes the caret,
            // and the request is consumed.
            .onChange(of: store.pendingFocus) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                focus = DraftFocus.word(id)
                store.pendingFocus = nil
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(countSummary)
            Text("·").foregroundStyle(.tertiary)
            Text(saveSummary)

            if let notice = store.restoreNotice {
                Text("·").foregroundStyle(.tertiary)
                Text(notice)
                    .foregroundStyle(Color.orange)
                Button("Dismiss") { store.restoreNotice = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let flash {
                Text(flash)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(Mac.footer)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Mac.pageInset)
        .padding(.vertical, 7)
        .background(Mac.chrome)
    }

    private var countSummary: String {
        let words = store.substantiveRows.count
        let noted = store.substantiveRows.filter { !$0.trimmedNote.isEmpty }.count
        if words == 0 { return "Empty draft" }
        return "\(words) \(words == 1 ? "word" : "words") · \(noted) with notes"
    }

    private var saveSummary: String {
        if store.hasUnsavedChanges { return "Saving…" }
        guard let savedAt = store.lastSavedAt else { return "Not saved yet" }
        return "Draft saved \(Formatting.relative(savedAt))"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.newRow()
            } label: {
                Label("New Row", systemImage: "plus")
            }
            .help("Add a row below the one you are editing (⌘N)")

            Menu {
                Button("Export CSV…") { export(.csv) }
                Button("Export Markdown…") { export(.markdown) }
                Divider()
                Button("Remove Blank Rows") { store.removeBlankRows() }
                Button("Clear Draft…", role: .destructive) { confirmClear = true }
            } label: {
                Label("Draft", systemImage: "square.and.arrow.up")
            }
            .help("Export the draft, or clear it")

            Button {
                showImport = true
            } label: {
                Label("Import into Library…", systemImage: "tray.and.arrow.down")
            }
            .help("Send the drafted words to a list in your library")

            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the word inspector")
        }
    }

    // MARK: - Actions

    private func inspect(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if inspectorHistory.last?.lowercased() != trimmed.lowercased() {
            inspectorHistory.append(trimmed)
        }
        showInspector = true
    }

    private func export(_ format: DraftExport.Format) {
        guard !store.substantiveRows.isEmpty else {
            show(flash: "Nothing to export yet.")
            return
        }
        if let url = DraftExport.present(format: format, rows: store.rows) {
            show(flash: "Exported to \(url.lastPathComponent).")
        }
    }

    private func show(flash message: String) {
        flash = message
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            flash = nil
        }
    }

    /// A binding into the store's array that survives rows being inserted and
    /// removed around it — index-based bindings do not.
    private func binding(for id: UUID) -> Binding<DraftRow> {
        Binding(
            get: { store.rows.first(where: { $0.id == id }) ?? DraftRow(id: id) },
            set: { newValue in
                guard let index = store.rows.firstIndex(where: { $0.id == id }) else { return }
                store.rows[index] = newValue
            }
        )
    }

    private static func rowID(of focus: DraftFocus?) -> UUID? {
        guard let focus else { return nil }
        switch focus {
        case .word(let id), .note(let id): return id
        }
    }
}
