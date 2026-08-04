import SwiftUI
import VocabKit

/// Full-screen lookup overlay: history when idle, live preview + similar-word
/// chips while typing.
struct SearchOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SearchModel
    @FocusState private var focused: Bool
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
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("search.close")
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            if model.query.isEmpty {
                history
            } else {
                results
            }

            Spacer(minLength: 0)

            if !model.similar.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.similar) { word in
                            Button {
                                open(word.word)
                            } label: {
                                Text(word.word)
                                    .font(.body)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)
                .accessibilityIdentifier("search.similar")
            }

            searchField
        }
        .background(.thinMaterial)
        .onAppear { focused = true }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Searchs" [sic] — matching the original app's label.
            Text("Searchs in last 7 days")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 8)
            ForEach(model.history, id: \.term) { item in
                Button {
                    open(item.term)
                } label: {
                    HStack {
                        Text(item.term)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Formatting.relative(item.searchedAt))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Divider().padding(.leading, 24)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("search.history")
    }

    private var results: some View {
        VStack(spacing: 14) {
            if let preview = model.preview {
                Button {
                    open(preview.word)
                } label: {
                    previewCard(preview)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.preview")
            } else {
                Text("No results")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private func previewCard(_ word: DictWord) -> some View {
        let state = env.userStore.state(of: word.word)
        let lists = env.userStore.listNames(containing: word.word)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(word.word)
                    .font(ClassicTheme.serifWord(size: 36))
                    .minimumScaleFactor(0.5)
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            HStack(spacing: 10) {
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.title3)
                }
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .onTapGesture {
                        env.speech.speak(word.word, accent: env.settings.pronunciationAccent, source: env.settings.pronunciationSource)
                    }
            }
            ForEach(word.translationLines.prefix(3), id: \.self) { line in
                Text(line)
                    .font(.title3)
                    .lineLimit(2)
            }
            FlowLayout(spacing: 8) {
                TagChip(
                    text: Formatting.familiarityChip(state.familiarity),
                    background: state.familiarity == nil ? ClassicTheme.familiarityUnknownChip : ClassicTheme.familiarityChip
                )
                TagChip(
                    text: Formatting.frequencyChip(word.frequencyBand),
                    background: ClassicTheme.frequencyChip
                )
                if lists.isEmpty {
                    TagChip(text: "+ Word lists", background: ClassicTheme.listChip)
                } else {
                    TagChip(text: lists[0], background: ClassicTheme.listChip)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ClassicTheme.cardBackground)
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Lookup words or sentences", text: $model.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit {
                    if let preview = model.preview { open(preview.word) }
                }
                .padding(.leading, 18)
                .accessibilityIdentifier("search.field")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 6)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.tint)
                    .padding(8)
                    .background(Circle().fill(ClassicTheme.wordChipBackground))
                    .padding(.trailing, 6)
                    .onTapGesture {
                        if let clip = UIPasteboard.general.string {
                            model.query = clip
                        }
                    }
            }
        }
        .frame(height: 52)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func open(_ term: String) {
        model.commit(term: term)
        dismiss()
        onOpenWord(term, [])
    }
}
