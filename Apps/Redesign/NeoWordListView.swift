import SwiftUI
import VocabKit

/// Word list — same zoning as classic (title+count, search, sort/filter row,
/// grouped rows, bottom study action) with editorial treatment: serif title,
/// underlined text-tab sort control, small-caps group headers, quiet rows,
/// and a compact trailing study commitment instead of a giant pill.
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
                VStack(alignment: .leading, spacing: 0) {
                    header
                    sortRow
                        .padding(.top, 18)
                    content
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .background(Neo.paper)

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
        .onReceive(env.$dataVersion) { _ in model.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.list.name)
                    .font(Neo.pageTitle)
                    .foregroundStyle(Neo.ink)
                    .lineLimit(2)
                Text("\(model.totalCount)")
                    .font(Neo.sans(17, weight: .medium).monospacedDigit())
                    .foregroundStyle(Neo.faint)
            }
            searchField
        }
        .padding(.top, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Neo.faint)
            TextField("Search", text: $model.searchText)
                .font(Neo.sans(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: model.searchText) { model.reload() }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
        .accessibilityIdentifier("wordList.search")
    }

    /// Sort keys as quiet text tabs with an underline marker; filters hang off
    /// the active tab as a compact menu.
    private var sortRow: some View {
        HStack(spacing: 22) {
            ForEach(WordListSortKey.allCases, id: \.self) { key in
                sortTab(key)
            }
            Spacer()
        }
        .accessibilityIdentifier("wordList.sortChips")
    }

    private func sortTab(_ key: WordListSortKey) -> some View {
        let isActive = model.sortKey == key
        return HStack(spacing: 4) {
            Button {
                if isActive {
                    model.ascending.toggle()
                } else {
                    model.sortKey = key
                    model.ascending = true
                }
                model.reload()
            } label: {
                HStack(spacing: 4) {
                    Text(key.rawValue)
                        .font(Neo.sans(15, weight: isActive ? .semibold : .regular))
                    if isActive {
                        Image(systemName: model.ascending ? "arrow.up" : "arrow.down")
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(isActive ? Neo.ink : Neo.faint)
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Rectangle().fill(Neo.ink).frame(height: 1.6)
                    }
                }
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("wordList.sort.\(key.rawValue)")

            if isActive, key != .plannedReview {
                Menu {
                    if key == .frequency {
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Neo.blue)
                        .frame(width: 26, height: 26)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.sections.isEmpty {
            VStack(spacing: 12) {
                Text("🧐")
                    .font(.system(size: 64))
                Text("This word list is empty.")
                    .font(Neo.serif(20, weight: .semibold))
                    .foregroundStyle(Neo.ink)
                Text("Search words or pick words from a picture.")
                    .font(.subheadline)
                    .foregroundStyle(Neo.graphite)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
            .accessibilityIdentifier("wordList.empty")
        } else {
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    NeoSectionHeader(title: section.title)
                        .padding(.top, 26)
                        .padding(.bottom, 6)
                    ForEach(section.rows) { row in
                        rowView(row)
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
        HStack(spacing: 10) {
            familiarityDot(row.familiarity)
            Text(row.word)
                .font(Neo.serif(19))
                .foregroundStyle(row.archived ? Neo.faint : Neo.ink)
            if row.archived {
                Image(systemName: "archivebox")
                    .font(.caption2)
                    .foregroundStyle(Neo.faint)
            }
            Spacer()
            Text(rightMeta(row))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Neo.faint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neo.hairline).frame(height: 0.5)
        }
    }

    /// Tiny familiarity state signal: hollow = unknown, warm = learning,
    /// green = familiar.
    private func familiarityDot(_ familiarity: Int?) -> some View {
        Group {
            if let familiarity {
                Circle()
                    .fill(familiarity >= 80 ? Neo.green : Neo.warm)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .stroke(Neo.hairline, lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
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
                    .foregroundStyle(batchMarkMode ? Neo.blue : Neo.graphite)
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
                    .foregroundStyle(Neo.graphite)
            }
            .accessibilityIdentifier("wordList.menu")
        }
    }

    /// Study commitment: compact, trailing, navy — not a full-width pill.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            NeoHairline()
            HStack(spacing: 10) {
                if let paused = model.pausedSession {
                    Text("Paused session — \(paused.totalCount - paused.position) cards left")
                        .font(.footnote)
                        .foregroundStyle(Neo.graphite)
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            env.userStore.clearPausedSession(listID: model.list.id)
                            model.reload()
                        } label: {
                            Label("End Session", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(Neo.graphite)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityIdentifier("wordList.sessionMenu")
                    NeoPrimaryButton(title: "Continue", systemImage: "play.fill") {
                        navigateToStudy = true
                    }
                    .accessibilityIdentifier("wordList.study")
                } else {
                    Text(studyCountLabel)
                        .font(.footnote)
                        .foregroundStyle(Neo.faint)
                    Spacer()
                    NeoPrimaryButton(title: "Study", systemImage: "book") {
                        navigateToStudy = true
                    }
                    .disabled(model.visibleWords.isEmpty)
                    .opacity(model.visibleWords.isEmpty ? 0.4 : 1)
                    .accessibilityIdentifier("wordList.study")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Neo.paper.opacity(0.97))
        }
    }

    private var studyCountLabel: String {
        let count = model.visibleWords.count
        return count == model.totalCount
            ? "\(count) words"
            : "\(count) of \(model.totalCount) words in view"
    }
}
