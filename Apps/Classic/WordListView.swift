import SwiftUI
import VocabKit

struct WordListView: View {
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
            list
            bottomBar
        }
        .navigationTitle("\(model.list.name) (\(model.totalCount))")
        .navigationBarTitleDisplayMode(.large)
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
            StudyStartView(model: StudyModel(list: model.list, candidateWords: model.visibleWords, env: env))
        }
        .onReceive(env.$dataVersion) { _ in model.reloadIfLoaded() }
        .task { model.loadIfNeeded() }
    }

    private var list: some View {
        List {
            if model.sections.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                sortChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            rowView(row)
                        }
                    } header: {
                        Text(section.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
                Color.clear
                    .frame(height: 90)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .onChange(of: model.searchText) { model.reload() }
        .accessibilityIdentifier("wordList.table")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("This word list is empty.\nSearch words or pick words from a picture!")
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 190)
        .accessibilityIdentifier("wordList.empty")
    }

    private func rowView(_ row: WordRowInfo) -> some View {
        Group {
            if batchMarkMode {
                Menu {
                    familiarityMenuButtons(for: row.word)
                } label: {
                    rowLabel(row)
                }
            } else {
                NavigationLink(value: Route.wordDetail(word: row.word, context: model.visibleWords)) {
                    rowLabel(row)
                }
            }
        }
        .listRowBackground(Color(uiColor: .systemBackground))
        .swipeActions(edge: .trailing) {
            // Membership edits target one concrete list, so they are hidden
            // on the aggregate view.
            if model.list.id != WordList.aggregateID {
                Button {
                    env.userStore.setArchived(!row.archived, word: row.word, in: model.list.id)
                    env.touch()
                } label: {
                    Label(row.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                .tint(.orange)
                Button(role: .destructive) {
                    env.userStore.remove(word: row.word, from: model.list.id)
                    env.touch()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func rowLabel(_ row: WordRowInfo) -> some View {
        HStack {
            Text(row.word)
                .font(.body)
                .foregroundStyle(row.archived ? .secondary : .primary)
            if row.archived {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if batchMarkMode {
                Spacer()
                Text(row.familiarity.map { "\($0)%" } ?? "?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func familiarityMenuButtons(for word: String) -> some View {
        ForEach(WordDetailModel.familiarityMenu, id: \.value) { item in
            Button {
                env.userStore.setFamiliarity(item.value, for: word)
                env.touch()
            } label: {
                Label(item.label, systemImage: item.symbol)
            }
        }
    }

    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                sortChip(.frequency) {
                    ForEach(FrequencyFilter.allCases, id: \.self) { filter in
                        Button(filter.label) {
                            model.frequencyFilter = filter
                            model.reload()
                        }
                    }
                }
                sortChip(.familiarity) {
                    ForEach(FamiliarityFilter.allCases, id: \.self) { filter in
                        Button(filter.label) {
                            model.familiarityFilter = filter
                            model.reload()
                        }
                    }
                }
                sortChip(.plannedReview) { EmptyView() }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("wordList.sortChips")
    }

    @ViewBuilder
    private func sortChip<MenuContent: View>(_ key: WordListSortKey, @ViewBuilder menu: () -> MenuContent) -> some View {
        let isActive = model.sortKey == key
        HStack(spacing: 0) {
            Button {
                if isActive {
                    model.ascending.toggle()
                } else {
                    model.sortKey = key
                    model.ascending = true
                }
                model.reload()
            } label: {
                HStack(spacing: 5) {
                    if isActive {
                        Image(systemName: model.ascending ? "arrow.up" : "arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(key.rawValue)
                        .lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.trailing, isActive ? 8 : 14)
                .padding(.vertical, 9)
            }
            if isActive, key != .plannedReview {
                Divider().frame(height: 20)
                Menu {
                    menu()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 9)
                }
            }
        }
        .font(.body.weight(isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? ClassicTheme.wordChipBackground : Color(uiColor: .secondarySystemFill))
        )
        .accessibilityIdentifier("wordList.sort.\(key.rawValue)")
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
                if model.list.id != WordList.aggregateID {
                    Button {
                        env.userStore.moveList(id: model.list.id, up: true)
                        env.touch()
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    Button {
                        env.userStore.moveList(id: model.list.id, up: false)
                        env.touch()
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
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
        HStack(spacing: 12) {
            Button {
                navigateToStudy = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy")
                    Text(model.pausedSession == nil ? "Practice These Words" : "Keep Going")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(model.pausedSession == nil ? ClassicTheme.studyButtonText : Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule().fill(model.pausedSession == nil
                        ? ClassicTheme.studyButtonBackground
                        : ClassicTheme.continueButtonBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(model.visibleWords.isEmpty && model.pausedSession == nil)
            .accessibilityIdentifier("wordList.study")

            if model.pausedSession != nil {
                Menu {
                    Button(role: .destructive) {
                        env.userStore.clearPausedSession(listID: model.list.id)
                        model.reload()
                    } label: {
                        Label("End Session", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color(uiColor: .secondarySystemFill)))
                }
                .accessibilityIdentifier("wordList.sessionMenu")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}
