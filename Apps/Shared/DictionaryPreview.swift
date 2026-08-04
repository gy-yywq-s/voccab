import SwiftUI
import UIKit
import VocabKit

/// Settings subpage: previews how every available dictionary renders a
/// sample word, with an enable toggle per source. Shared by both frontends.
struct DictionaryPreviewPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var word = "serene"
    @State private var enabled: Set<DictionarySource> = []

    private let sources: [DictionarySource] = [
        .chinese, .oxford, .english, .synonyms, .webster, .moby, .apple,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Type any word to see how each dictionary renders it, and choose which ones appear on word pages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                TextField("Preview word", text: $word)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .padding(.top, 12)
                    .accessibilityIdentifier("preview.field")

                ForEach(sources, id: \.self) { source in
                    sourceSection(source)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Dictionary Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { enabled = Set(env.settings.enabledDictionaries) }
    }

    private func sourceSection(_ source: DictionarySource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 12)
            HStack(alignment: .firstTextBaseline) {
                Text(source.label)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: binding(source))
                    .labelsHidden()
            }
            Text(source.sourceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            previewContent(source)
                .padding(.top, 4)
        }
        .padding(.vertical, 12)
    }

    private func binding(_ source: DictionarySource) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(source) },
            set: { on in
                if on { enabled.insert(source) } else { enabled.remove(source) }
                env.settings.setDictionary(source, enabled: on)
                env.touch()
            }
        )
    }

    @ViewBuilder
    private func previewContent(_ source: DictionarySource) -> some View {
        let term = word.trimmingCharacters(in: .whitespaces)
        switch source {
        case .chinese:
            if let lines = env.dictionary?.lookup(term)?.translationLines, !lines.isEmpty {
                previewText(lines.prefix(3).joined(separator: "\n"))
            } else {
                missing
            }
        case .oxford:
            if let paragraphs = env.dictionary?.oxfordEntry(for: term) {
                previewText(paragraphs.prefix(2).joined(separator: "\n"))
            } else {
                missing
            }
        case .english:
            let senses = env.dictionary?.senses(for: term) ?? []
            if senses.isEmpty {
                missing
            } else {
                previewText(senses.prefix(2)
                    .map { "(\($0.pos)) \($0.gloss)" }
                    .joined(separator: "\n"))
            }
        case .synonyms:
            let synonyms = (env.dictionary?.senses(for: term) ?? []).flatMap(\.synonyms)
            if synonyms.isEmpty {
                missing
            } else {
                previewText(Array(Set(synonyms)).sorted().prefix(10).joined(separator: ", "))
            }
        case .webster:
            if let paragraphs = env.dictionary?.websterEntry(for: term) {
                previewText(paragraphs.prefix(2).joined(separator: "\n"))
            } else {
                missing
            }
        case .moby:
            if let synonyms = env.dictionary?.mobySynonyms(for: term) {
                previewText(synonyms.prefix(14).joined(separator: ", "))
            } else {
                missing
            }
        case .apple:
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
                previewText("Definition available — shown embedded on the word page.")
            } else {
                previewText("Rendered by iOS. Add dictionaries in Settings › General › Dictionary.")
            }
        }
    }

    private func previewText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var missing: some View {
        Text("No entry for this word.")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
    }
}
