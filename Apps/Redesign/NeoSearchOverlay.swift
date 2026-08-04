import SwiftUI
import VocabKit

/// Lookup overlay — same zones (history / live preview + similar chips /
/// bottom field) on a paper sheet with native search geometry.
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
                    .font(Neo.serif(17, weight: .semibold))
                    .foregroundStyle(Neo.ink)
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
            .padding(.horizontal, 24)
            .padding(.top, 8)
            NeoHairline()
                .padding(.horizontal, 24)

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
                                    .font(Neo.sans(15))
                                    .foregroundStyle(Neo.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(Neo.paleBlue)
                                    )
                            }
                            .buttonStyle(NeoPressStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 10)
                .accessibilityIdentifier("search.similar")
            }

            searchField
        }
        .background(Neo.paper)
        .onAppear { focused = true }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            NeoSectionHeader(title: "Last 7 Days")
                .padding(.top, 26)
                .padding(.bottom, 4)
            ForEach(model.history, id: \.term) { item in
                Button {
                    open(item.term)
                } label: {
                    HStack {
                        Text(item.term)
                            .font(Neo.serif(19))
                            .foregroundStyle(Neo.ink)
                        Spacer()
                        Text(Formatting.relative(item.searchedAt))
                            .font(.footnote)
                            .foregroundStyle(Neo.faint)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Neo.hairline).frame(height: 0.5)
                    }
                }
                .buttonStyle(NeoPressStyle())
            }
        }
        .padding(.horizontal, 24)
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
                    .font(Neo.sans(15))
                    .foregroundStyle(Neo.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private func previewBlock(_ word: DictWord) -> some View {
        let state = env.userStore.state(of: word.word)
        let lists = env.userStore.listNames(containing: word.word)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.word)
                    .font(Neo.serif(30, weight: .semibold))
                    .foregroundStyle(Neo.ink)
                    .minimumScaleFactor(0.5)
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(Neo.sans(15))
                        .foregroundStyle(Neo.graphite)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.subheadline)
                    .foregroundStyle(Neo.faint)
            }
            ForEach(word.translationLines.prefix(3), id: \.self) { line in
                Text(line)
                    .font(Neo.sans(16))
                    .foregroundStyle(Neo.ink)
                    .lineLimit(2)
            }
            FlowLayout(spacing: 8) {
                NeoTag(
                    text: Formatting.familiarityChip(state.familiarity),
                    color: state.familiarity == nil ? Neo.faint : Neo.warm
                )
                NeoTag(text: Formatting.frequencyChip(word.frequencyBand), color: Neo.graphite)
                if lists.isEmpty {
                    NeoTag(text: "+ Word lists", color: Neo.blue)
                } else {
                    NeoTag(text: lists[0], color: Neo.graphite)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Neo.faint)
            TextField("Lookup words or sentences", text: $model.query)
                .font(Neo.sans(15))
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
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func open(_ term: String) {
        model.commit(term: term)
        dismiss()
        onOpenWord(term, [])
    }
}
