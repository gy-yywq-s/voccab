import SwiftUI
import VocabKit

/// Lookup overlay — same zones (history / live preview + similar chips /
/// bottom field): white sheet, capsule field with shadow, plain rows.
struct NeoSearchOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SearchModel
    @FocusState private var focused: Bool
    @State private var showNewListPrompt = false
    @State private var newListName = ""
    @State private var newListWord: String?
    let onOpenWord: (String, [String]) -> Void

    init(env: AppEnvironment, initialQuery: String = "", onOpenWord: @escaping (String, [String]) -> Void) {
        self.onOpenWord = onOpenWord
        _model = StateObject(wrappedValue: {
            let model = SearchModel(env: env)
            model.query = initialQuery
            return model
        }())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lookup")
                    .font(Neo.rowTitle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Neo.graphite)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("search.close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            NeoHairline()

            if model.query.isEmpty {
                history
            } else {
                results
            }

            Spacer(minLength: 0)

            if !model.similar.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.similar) { word in
                            Button {
                                open(word.word)
                            } label: {
                                Text(word.word)
                                    .font(.body)
                                    .foregroundStyle(Neo.blue)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Neo.paleBlue)
                                    )
                            }
                            .buttonStyle(NeoPressStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)
                .accessibilityIdentifier("search.similar")
            }

            searchField
        }
        .background(Neo.page)
        .onAppear { focused = true }
        .alert("New List", isPresented: $showNewListPrompt) {
            TextField("List name", text: $newListName)
            Button("Add") {
                let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let word = newListWord, !trimmed.isEmpty,
                   let list = env.userStore.createList(name: trimmed) {
                    env.userStore.add(word: word, to: list.id)
                    env.touch()
                }
                newListWord = nil
            }
            Button("Cancel", role: .cancel) { newListWord = nil }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            NeoSectionHeader(title: "Last 7 days")
                .padding(.top, 22)
                .padding(.bottom, 2)
            ForEach(model.history, id: \.term) { item in
                Button {
                    open(item.term)
                } label: {
                    HStack {
                        Text(item.term)
                            .font(Neo.rowTitle)
                            .foregroundStyle(Neo.ink)
                        Spacer()
                        Text(Formatting.relative(item.searchedAt))
                            .font(Neo.caption)
                            .foregroundStyle(Neo.graphite)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        NeoHairline()
                    }
                }
                .buttonStyle(NeoPressStyle())
            }
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("search.history")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview = model.preview {
                Button {
                    open(preview.word)
                } label: {
                    previewBlock(preview)
                }
                .buttonStyle(NeoPressStyle())
                .overlay(alignment: .topTrailing) {
                    addToListMenu(for: preview.word)
                        .padding(6)
                }
                .accessibilityIdentifier("search.preview")
            } else {
                Text("No results")
                    .font(.body)
                    .foregroundStyle(Neo.graphite)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func previewBlock(_ word: DictWord) -> some View {
        let recall = env.userStore.state(of: word.word).predictedRecall()
        let lists = env.userStore.listNames(containing: word.word)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.word)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Neo.ink)
                    .minimumScaleFactor(0.5)
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.subheadline)
                        .foregroundStyle(Neo.graphite)
                }
                Spacer()
                // Space held for the add-to-list menu overlaid on the card.
                Color.clear.frame(width: 32, height: 26)
            }
            ForEach(word.translationLines.prefix(3), id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(Neo.ink)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Group {
                    if let recall {
                        Text("Recall \(Int((recall * 100).rounded()))%")
                            .foregroundStyle(Neo.warm)
                    } else {
                        Text("Recall ?")
                            .foregroundStyle(Neo.graphite)
                    }
                    Text("·").foregroundStyle(Neo.faint)
                    Text(word.frequencyBand.label)
                        .foregroundStyle(Neo.graphite)
                    Text("·").foregroundStyle(Neo.faint)
                    Text(lists.isEmpty ? "Not in any list" : lists.joined(separator: ", "))
                        .foregroundStyle(Neo.graphite)
                        .lineLimit(1)
                }
                .font(.footnote)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Neo.page)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        )
    }

    private func addToListMenu(for word: String) -> some View {
        Menu {
            addToListItems(for: word)
        } label: {
            Image(systemName: env.userStore.listNames(containing: word).isEmpty
                  ? "plus.circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Neo.blue)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("search.addToList")
    }

    @ViewBuilder
    private func addToListItems(for word: String) -> some View {
        ForEach(env.userStore.lists()) { list in
            Button {
                if env.userStore.isWord(word, in: list.id) {
                    env.userStore.remove(word: word, from: list.id)
                } else {
                    env.userStore.add(word: word, to: list.id)
                }
                env.touch()
            } label: {
                if env.userStore.isWord(word, in: list.id) {
                    Label(list.name, systemImage: "checkmark")
                } else {
                    Text(list.name)
                }
            }
        }
        Divider()
        Button {
            newListWord = word
            newListName = ""
            showNewListPrompt = true
        } label: {
            Label("New List…", systemImage: "plus")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Neo.graphite)
            TextField("Lookup", text: $model.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit {
                    if let preview = model.preview { open(preview.word) }
                }
                .accessibilityIdentifier("search.field")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Neo.faint)
                }
            } else {
                Button {
                    if let clip = UIPasteboard.general.string {
                        model.query = clip
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline)
                        .foregroundStyle(Neo.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(
            Capsule().fill(Neo.cardFill)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func open(_ term: String) {
        model.commit(term: term)
        dismiss()
        onOpenWord(term, [])
    }
}
