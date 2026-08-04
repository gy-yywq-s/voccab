import SwiftUI
import VocabKit

/// Word list — same zoning as classic (title+count, search, sort/filter,
/// grouped rows, bottom study action) in the Passage language: native
/// segmented sort control, capsule search with shadow, bold group headings,
/// plain hairline rows, compact trailing navy Study commit.
struct NeoWordListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: WordListModel
    @State private var batchMarkMode = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var navigateToStudy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                // Lazy so pushing a large list doesn't build every row up front.
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    sortRow
                        .padding(.top, 14)
                    content
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemBackground))

            bottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Edit name", isPresented: $showRename) {
            TextField("List name", text: $renameText)
            Button("Save") {
                env.userStore.renameList(id: model.list.id, to: renameText)
                env.touch()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this word list?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                env.userStore.deleteList(id: model.list.id)
                env.touch()
                dismiss()
            }
        }
        .navigationDestination(isPresented: $navigateToStudy) {
            NeoStudyStartView(model: StudyModel(list: model.list, candidateWords: model.visibleWords, env: env))
        }
        .onReceive(env.$dataVersion) { _ in model.reloadIfLoaded() }
        .task { model.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.list.name)
                    .font(Neo.pageTitle)
                    .lineLimit(2)
                Text("\(model.totalCount)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            NeoSearchField(placeholder: "Search", text: $model.searchText) {
                model.reload()
            }
            .accessibilityIdentifier("wordList.search")
        }
        .padding(.top, 8)
    }

    /// Native segmented sort keys plus compact direction/filter controls.
    private var sortRow: some View {
        HStack(spacing: 10) {
            Picker("Sort", selection: sortBinding) {
                Text("Frequency").tag(WordListSortKey.frequency)
                Text("Familiarity").tag(WordListSortKey.familiarity)
                Text("Review").tag(WordListSortKey.plannedReview)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("wordList.sortChips")

            Button {
                model.ascending.toggle()
                model.reload()
            } label: {
                Image(systemName: model.ascending ? "arrow.up" : "arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Neo.blue)
                    .frame(width: 34, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Neo.paleBlue))
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("wordList.sortDirection")

            if model.sortKey != .plannedReview {
                Menu {
                    if model.sortKey == .frequency {
                        ForEach(FrequencyFilter.allCases, id: \.self) { filter in
                            Button(filter.label) {
                                model.frequencyFilter = filter
                                model.reload()
                            }
                        }
                    } else {
                        ForEach(FamiliarityFilter.allCases, id: \.self) { filter in
                            Button(filter.label) {
                                model.familiarityFilter = filter
                                model.reload()
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Neo.blue)
                        .frame(width: 34, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Neo.paleBlue))
                }
                .accessibilityIdentifier("wordList.filter")
            }
        }
    }

    private var sortBinding: Binding<WordListSortKey> {
        Binding(
            get: { model.sortKey },
            set: { newKey in
                model.sortKey = newKey
                model.ascending = true
                model.reload()
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if !model.loaded {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 110)
        } else if model.sections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text("This word list is empty.")
                    .font(.headline)
                Text("Search words or pick words from a picture.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 110)
            .accessibilityIdentifier("wordList.empty")
        } else {
            // Section inside the LazyVStack keeps rows individually lazy.
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        rowView(row)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.title)
                                .font(Neo.rowTitle)
                            Spacer()
                            Text("\(section.rows.count)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 6)
                        NeoHairline()
                    }
                }
            }
        }
    }

    private func rowView(_ row: WordRowInfo) -> some View {
        Group {
            if batchMarkMode {
                Menu {
                    ForEach(WordDetailModel.familiarityMenu, id: \.value) { item in
                        Button {
                            env.userStore.setFamiliarity(item.value, for: row.word)
                            env.touch()
                        } label: {
                            Label(item.label, systemImage: item.symbol)
                        }
                    }
                } label: {
                    rowLabel(row)
                }
            } else {
                NavigationLink(value: Route.wordDetail(word: row.word, context: model.visibleWords)) {
                    rowLabel(row)
                }
                .buttonStyle(NeoPressStyle())
            }
        }
        .contextMenu {
            Button {
                env.userStore.setArchived(!row.archived, word: row.word, in: model.list.id)
                env.touch()
            } label: {
                Label(row.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                env.userStore.remove(word: row.word, from: model.list.id)
                env.touch()
            } label: {
                Label("Remove from list", systemImage: "trash")
            }
        }
    }

    private func rowLabel(_ row: WordRowInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.word)
                        .font(Neo.rowTitle)
                        .foregroundStyle(row.archived ? Color.secondary : Color.primary)
                    if row.archived {
                        Image(systemName: "archivebox")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let familiarity = row.familiarity {
                    Text("Familiarity \(familiarity)%")
                        .font(Neo.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(rightMeta(row))
                .font(Neo.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(uiColor: .quaternaryLabel))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            NeoHairline().padding(.leading, 16)
        }
    }

    private func rightMeta(_ row: WordRowInfo) -> String {
        switch model.sortKey {
        case .frequency:
            return row.rank > 0 ? "#\(row.rank)" : ""
        case .familiarity:
            return row.familiarity.map { "\($0)%" } ?? "?"
        case .plannedReview:
            return row.nextPlannedAt.map { Formatting.relative($0) } ?? ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                batchMarkMode.toggle()
            } label: {
                Image(systemName: batchMarkMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .accessibilityIdentifier("wordList.batchMark")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    model.showArchived.toggle()
                    model.reload()
                } label: {
                    Label(model.showArchived ? "Hide Archived" : "Show Archived",
                          systemImage: model.showArchived ? "archivebox.fill" : "archivebox")
                }
                if model.pausedSession != nil {
                    Button(role: .destructive) {
                        env.userStore.clearPausedSession(listID: model.list.id)
                        model.reload()
                    } label: {
                        Label("End Session", systemImage: "xmark.circle")
                    }
                }
                if !model.list.isBuiltin {
                    Button {
                        renameText = model.list.name
                        showRename = true
                    } label: {
                        Label("Edit name", systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("wordList.menu")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            NeoBeginBar(
                title: model.pausedSession.map { "Continue studying · \($0.totalCount - $0.position) left" }
                    ?? "Study \(studyCountLabel)",
                systemImage: model.pausedSession == nil ? "arrow.right" : "play.fill"
            ) {
                navigateToStudy = true
            }
            .disabled(model.visibleWords.isEmpty && model.pausedSession == nil)
            .opacity(model.visibleWords.isEmpty && model.pausedSession == nil ? 0.4 : 1)
            .accessibilityIdentifier("wordList.study")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(.regularMaterial)
    }

    private var studyCountLabel: String {
        let count = model.visibleWords.count
        return count == model.totalCount
            ? "\(count) words"
            : "\(count) words in view"
    }
}
