import SwiftUI
import UIKit
import VocabKit

/// Settings subpage: manage which dictionaries appear on word pages.
/// Modeled on the World Clock management pattern: enabled dictionaries on
/// top (drag to reorder, minus to remove — always, no Edit toggle), the
/// remaining ones below with a "+" to add and tap-to-expand canned
/// previews. Previews load lazily on expand and are cached, so first
/// render does no dictionary lookups at all. Shared by both frontends.
struct DictionaryPreviewPage: View {
    @EnvironmentObject private var env: AppEnvironment

    /// Fixed demo word for the canned previews. "serene" was this page's
    /// long-standing default and exists in the bundled database.
    private static let previewWord = "serene"

    /// Mirrors env.settings.enabledDictionaries (the source of truth).
    @State private var ordered: [DictionarySource] = []
    @State private var searchText = ""
    @State private var expanded: Set<DictionarySource> = []
    @State private var previewCache: [DictionarySource: PreviewResult] = [:]

    private enum PreviewResult {
        case text(String)
        case missing
    }

    // MARK: - Filtering

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func filter(_ sources: [DictionarySource]) -> [DictionarySource] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sources }
        return sources.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    private var filteredEnabled: [DictionarySource] {
        filter(ordered)
    }

    private var filteredAvailable: [DictionarySource] {
        filter(DictionarySource.allCases.filter { !ordered.contains($0) })
    }

    // MARK: - Body

    var body: some View {
        List {
            if !filteredEnabled.isEmpty {
                Section {
                    ForEach(filteredEnabled, id: \.self) { source in
                        enabledRow(source)
                            .moveDisabled(isFiltering)
                            .accessibilityIdentifier("dictPreview.row.\(source.rawValue)")
                    }
                    .onMove(perform: moveEnabled)
                    .onDelete(perform: deleteEnabled)
                } header: {
                    Text("Word Pages Show")
                } footer: {
                    Text("Drag to reorder — the first dictionary is the tab a word page opens on. Remove one to move it back to the list below.")
                }
            }
            if !filteredAvailable.isEmpty {
                Section {
                    ForEach(filteredAvailable, id: \.self) { source in
                        addRow(source)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                            .accessibilityIdentifier("dictPreview.row.\(source.rawValue)")
                    }
                } header: {
                    Text("Add Dictionary")
                } footer: {
                    Text("Tap a dictionary to preview how it renders “\(Self.previewWord)”.")
                }
            }
            if filteredEnabled.isEmpty && filteredAvailable.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        // Permanent edit affordances (reorder grip + minus circle) without
        // an Edit button, scoped to this List only.
        .environment(\.editMode, .constant(.active))
        .searchable(text: $searchText, prompt: "Search dictionaries")
        .navigationTitle("Dictionaries")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Cheap: a UserDefaults read. No dictionary lookups happen
            // until an "Add Dictionary" row is expanded.
            ordered = env.settings.enabledDictionaries
        }
    }

    // MARK: - Rows

    private func enabledRow(_ source: DictionarySource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            serifName(source.label)
            Text(source.sourceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func addRow(_ source: DictionarySource) -> some View {
        let isExpanded = expanded.contains(source)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expanded.remove(source)
                        } else {
                            expanded.insert(source)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            serifName(source.label)
                            Text(source.sourceNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    add(source)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(source.label)")
                .accessibilityIdentifier("dictPreview.add.\(source.rawValue)")
            }
            .padding(.vertical, 2)

            if isExpanded {
                previewContent(source)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
    }

    private func serifName(_ label: String) -> some View {
        Text(label)
            .font(.custom("Iowan Old Style", size: 17, relativeTo: .body))
    }

    // MARK: - Mutations (env.settings.enabledDictionaries is the source of truth)

    private func moveEnabled(from offsets: IndexSet, to destination: Int) {
        // Only reachable when the filter is empty (rows are moveDisabled
        // while filtering), so offsets map 1:1 onto `ordered`.
        ordered.move(fromOffsets: offsets, toOffset: destination)
        env.settings.enabledDictionaries = ordered
        env.touch()
    }

    private func deleteEnabled(at offsets: IndexSet) {
        let removed = offsets.map { filteredEnabled[$0] }
        withAnimation {
            ordered.removeAll { removed.contains($0) }
        }
        env.settings.enabledDictionaries = ordered
        env.touch()
    }

    private func add(_ source: DictionarySource) {
        guard !ordered.contains(source) else { return }
        withAnimation {
            expanded.remove(source)
            env.settings.setDictionary(source, enabled: true)
            ordered = env.settings.enabledDictionaries
        }
        env.touch()
    }

    // MARK: - Lazy canned preview

    @ViewBuilder
    private func previewContent(_ source: DictionarySource) -> some View {
        switch source {
        case .apple:
            // Created only while this row is expanded; first-time creation
            // cost is absorbed by AppleDictionaryInline.warmUp() after launch.
            AppleDictionarySheet(term: Self.previewWord)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                )
        default:
            switch previewCache[source] {
            case .text(let text):
                previewText(text)
            case .missing:
                missing
            case nil:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .task {
                    await loadPreview(source)
                }
            }
        }
    }

    /// Looks up the canned preview for one source, off the first render
    /// path, and caches the result for the rest of the page's lifetime.
    private func loadPreview(_ source: DictionarySource) async {
        guard previewCache[source] == nil else { return }
        // Let the expansion animation start before touching the database.
        await Task.yield()
        let term = Self.previewWord
        let text: String?
        switch source {
        case .chinese:
            let lines = env.dictionary?.lookup(term)?.translationLines ?? []
            text = lines.isEmpty ? nil : lines.prefix(3).joined(separator: "\n")
        case .oxford:
            if let paragraphs = env.dictionary?.oxfordEntry(for: term) {
                text = paragraphs.prefix(2).joined(separator: "\n")
            } else {
                text = nil
            }
        case .english:
            let senses = env.dictionary?.senses(for: term) ?? []
            text = senses.isEmpty ? nil : senses.prefix(2)
                .map { "(\($0.pos)) \($0.gloss)" }
                .joined(separator: "\n")
        case .synonyms:
            let synonyms = (env.dictionary?.senses(for: term) ?? []).flatMap(\.synonyms)
            text = synonyms.isEmpty ? nil
                : Array(Set(synonyms)).sorted().prefix(10).joined(separator: ", ")
        case .webster:
            if let paragraphs = env.dictionary?.websterEntry(for: term) {
                text = paragraphs.prefix(2).joined(separator: "\n")
            } else {
                text = nil
            }
        case .moby:
            if let synonyms = env.dictionary?.mobySynonyms(for: term) {
                text = synonyms.prefix(14).joined(separator: ", ")
            } else {
                text = nil
            }
        case .apple:
            return  // Rendered as an embedded view, never cached as text.
        }
        if let text, !text.isEmpty {
            previewCache[source] = .text(text)
        } else {
            previewCache[source] = .missing
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
