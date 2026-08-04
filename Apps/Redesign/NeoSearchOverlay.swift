import SwiftUI
import VocabKit

/// Lookup overlay — same zones (history / live preview + similar chips /
/// bottom field): white sheet, capsule field with shadow, plain rows.
struct NeoSearchOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SearchModel
    @FocusState private var focused: Bool
    let onOpenWord: (String, [String]) -> Void

    init(env: AppEnvironment, onOpenWord: @escaping (String, [String]) -> Void) {
        self.onOpenWord = onOpenWord
        _model = StateObject(wrappedValue: SearchModel(env: env))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lookup")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
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
        .background(Color(uiColor: .systemBackground))
        .onAppear { focused = true }
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
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Formatting.relative(item.searchedAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                .accessibilityIdentifier("search.preview")
            } else {
                Text("No results")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func previewBlock(_ word: DictWord) -> some View {
        let state = env.userStore.state(of: word.word)
        let lists = env.userStore.listNames(containing: word.word)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.word)
                    .font(Neo.headword(30))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            ForEach(word.translationLines.prefix(3), id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Group {
                    if let familiarity = state.familiarity {
                        Text("Familiarity \(familiarity)%")
                            .foregroundStyle(Neo.warm)
                    } else {
                        Text("Familiarity ?")
                            .foregroundStyle(.secondary)
                    }
                    Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Text(word.frequencyBand.label)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Text(lists.isEmpty ? "Not in any list" : lists.joined(separator: ", "))
                        .foregroundStyle(.secondary)
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
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Lookup words or sentences", text: $model.query)
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
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
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
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
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
