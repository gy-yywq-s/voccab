import SwiftUI
import VocabKit

struct NeoWordDetailPager: View {
    @EnvironmentObject private var env: AppEnvironment
    let word: String
    let context: [String]
    @State private var selection: String

    init(word: String, context: [String]) {
        self.word = word
        self.context = context
        _selection = State(initialValue: word)
    }

    /// TabView's page style builds children eagerly, so cap the pager to a
    /// window around the opened word instead of the whole list.
    private var pages: [String] {
        guard !context.isEmpty, let index = context.firstIndex(of: word) else { return [word] }
        let lower = max(0, index - 15)
        let upper = min(context.count, index + 16)
        return Array(context[lower..<upper])
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(pages, id: \.self) { pageWord in
                NeoWordDetailView(model: WordDetailModel(word: pageWord, env: env))
                    .tag(pageWord)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(selection)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
    }
}

/// Word page — same zones as classic (headword, definitions, note, tags,
/// study info, dictionary tabs). Serif is reserved for the headword itself;
/// everything else is SF. Tags collapse into one quiet metadata line; the
/// dictionary switch is a native segmented control.
struct NeoWordDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: WordDetailModel
    @State private var tab: DictionarySource = .chinese
    @State private var showNoteEditor = false
    @State private var noteText = ""
    @State private var showNewListPrompt = false
    @State private var newListName = ""
    @State private var showResetConfirm = false

    private var dictionaryTabs: [DictionarySource] {
        env.settings.enabledDictionaries.filter { $0 != .chinese }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headword
                chineseDefinitions
                noteBlock
                NeoSectionHeader(title: "Progress") {
                    Text(Formatting.recallChip(model.recall))
                        .font(Neo.bodyFont)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 30)
                studyBlock
                NeoSectionHeader(title: "Dictionary")
                    .padding(.top, 26)
                tabBar
                    .padding(.top, 12)
                tabContent
                    .padding(.top, 16)
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .toolbar { toolbarItems }
        .onAppear {
            // Open on the user's top-ranked dictionary (Settings order).
            tab = env.settings.enabledDictionaries.first ?? .chinese
        }
        .alert("Edit note", isPresented: $showNoteEditor) {
            TextField("Note", text: $noteText, axis: .vertical)
            Button("Save") { model.setNote(noteText) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New List", isPresented: $showNewListPrompt) {
            TextField("List name", text: $newListName)
            Button("Add") { model.addToNewList(named: newListName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Reset progress?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { model.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The schedule, recall estimate, and algorithm state for this word start over as brand new. Your note, lists, and history stay.")
        }
    }

    // MARK: Header zone

    private var headword: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(model.displayWord)
                    .font(.system(size: 32, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                Spacer()
                addToListControl
            }
            HStack(spacing: 8) {
                if let phonetic = model.data.dictWord?.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Button {
                    model.speak()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(Neo.blue)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("word.speak")

                // Inflected form: link straight to the base word.
                if let base = model.data.dictWord?.baseForm {
                    NavigationLink(value: Route.wordDetail(word: base, context: [])) {
                        HStack(spacing: 4) {
                            Text("form of")
                                .foregroundStyle(.secondary)
                            Text(base)
                                .foregroundStyle(Neo.blue)
                                .underline()
                        }
                        .font(Neo.caption)
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("word.baseForm")
                }
            }
            classificationCaption
                .padding(.top, 2)
        }
        .padding(.top, 6)
        .accessibilityIdentifier("word.headerCard")
    }

    /// Quiet classification line in the identity cluster: frequency band,
    /// exam tags, list memberships.
    private var classificationCaption: some View {
        let dictWord = model.data.dictWord
        return FlowLayout(spacing: 6) {
            Group {
                Text((dictWord?.frequencyBand ?? .unknown).label)
                if model.data.listNames.isEmpty {
                    Text("·")
                    Menu {
                        listMenuItems
                    } label: {
                        Text("+ Word lists")
                            .font(Neo.caption.weight(.medium))
                            .foregroundStyle(Neo.blue)
                    }
                } else {
                    ForEach(model.data.listNames, id: \.self) { name in
                        Text("·")
                        Text(name)
                    }
                }
            }
            .font(Neo.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var addToListControl: some View {
        Menu {
            listMenuItems
        } label: {
            Image(systemName: model.isInAnyList ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(model.isInAnyList ? Neo.blue : Color.secondary)
                .frame(width: 44, height: 44, alignment: .topTrailing)
        }
        .accessibilityIdentifier("word.addToMyWords")
    }

    /// Menu entries shared by the bookmark control and the "+ Word lists"
    /// chip: one toggle per list, then a new-list prompt.
    @ViewBuilder
    private var listMenuItems: some View {
        ForEach(model.data.allLists) { list in
            Button {
                model.toggleMembership(of: list)
            } label: {
                if model.isMember(of: list) {
                    Label(list.name, systemImage: "checkmark")
                } else {
                    Text(list.name)
                }
            }
        }
        Divider()
        Button {
            newListName = ""
            showNewListPrompt = true
        } label: {
            Label("New List…", systemImage: "plus")
        }
    }

    private var chineseDefinitions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lines = model.data.dictWord?.translationLines, !lines.isEmpty {
                ForEach(lines, id: \.self) { line in
                    definitionLine(line)
                }
            } else {
                Text("No dictionary entry")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 14)
    }

    private func definitionLine(_ line: String) -> some View {
        let parts = splitPOS(line)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let pos = parts.pos {
                Text(pos)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .leading)
            }
            Text(parts.body)
                .font(.body)
        }
    }

    private func splitPOS(_ line: String) -> (pos: String?, body: String) {
        let known = ["n.", "v.", "vt.", "vi.", "a.", "adj.", "adv.", "pron.", "prep.", "conj.", "interj.", "num.", "art.", "aux."]
        for prefix in known where line.hasPrefix(prefix) {
            return (prefix, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, line)
    }

    @ViewBuilder
    private var noteBlock: some View {
        if !model.data.state.note.isEmpty {
            // Reading-first: primary-color text on a quiet warm block; the
            // small tracked label sits close so it reads as one unit.
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Neo.warm)
                Text(Formatting.tidy(model.data.state.note))
                    .font(Neo.bodyFont)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Neo.warm.opacity(0.09))
            )
            .padding(.top, 14)
        }
    }

    /// The Study section: a compact "I know this word" seeding control, then
    /// the schedule facts as scannable label/value rows.
    private var studyBlock: some View {
        let state = model.data.state
        return VStack(alignment: .leading, spacing: 14) {
            knownWordRow
                .padding(.top, 12)

            VStack(spacing: 0) {
                factRow("Practiced", state.timesStudied == 0 ? "never" : "\(state.timesStudied) time\(state.timesStudied == 1 ? "" : "s")")
                if let last = state.lastStudiedAt {
                    factRow("Last review", Formatting.relative(last))
                }
                if let next = state.nextPlannedAt {
                    factRow("Next review", Formatting.relative(next))
                }
                if state.memoryCircle > 0 {
                    factRow("Memory circle", "\(state.memoryCircle)", last: true)
                }
            }
        }
        .accessibilityIdentifier("word.studyInfo")
    }

    /// "I know this word": a quiet hairline menu row seeding the scheduler
    /// at rung 1-5 (5 = strongest).
    private var knownWordRow: some View {
        HStack {
            Text("I know this word")
                .font(Neo.bodyFont)
            Spacer()
            Menu {
                ForEach(WordDetailModel.knownWordMenu, id: \.rung) { item in
                    Button {
                        model.setKnownLevel(rung: item.rung)
                    } label: {
                        Label(item.label, systemImage: item.symbol)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("How well?")
                        .font(Neo.caption)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Neo.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.7)
                )
            }
        }
        // Identifier kept from the old familiarity control for UITests.
        .accessibilityIdentifier("word.familiaritySlider")
    }

    private func factRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(Neo.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(Neo.caption)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            if !last {
                NeoHairline()
            }
        }
    }

    // MARK: Dictionary tabs — a low, thin custom switcher, visually
    // subordinate to the study block above it.

    private var allTabs: [(DictionarySource, String)] {
        [(DictionarySource.chinese, "Related")] + dictionaryTabs.map { ($0, shortLabel($0)) }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(allTabs, id: \.0) { source, label in
                Button {
                    tab = source
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: tab == source ? .medium : .regular))
                        .foregroundStyle(tab == source ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if tab == source {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                            }
                        }
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("word.tab.\(label)")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(uiColor: .systemGray6))
        )
        .accessibilityIdentifier("word.tabs")
    }

    private func shortLabel(_ source: DictionarySource) -> String {
        switch source {
        case .english: return "English"
        case .synonyms: return "Synonyms"
        case .webster: return "Webster"
        case .moby: return "Moby"
        case .apple: return "Apple"
        default: return source.label
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .chinese:
            relatedContent
        case .oxford:
            oxfordContent
        case .english:
            englishContent
        case .synonyms:
            synonymsContent
        case .webster:
            websterContent
        case .moby:
            mobyContent
        case .apple:
            appleContent
        }
    }

    private var websterContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let paragraphs = model.data.webster {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(Neo.bodyFont)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No Webster 1913 entry for this word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("word.webster")
    }

    private var mobyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let synonyms = model.data.mobySynonyms {
                FlowLayout(spacing: 8) {
                    ForEach(synonyms, id: \.self) { synonym in
                        NavigationLink(value: Route.wordDetail(word: synonym, context: [])) {
                            Text(synonym)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Neo.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Neo.paleBlue)
                                )
                        }
                        .buttonStyle(NeoPressStyle())
                    }
                }
            } else {
                Text("No Moby Thesaurus entry for this word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("word.moby")
    }

    private var relatedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.data.related.isEmpty {
                Text("No related forms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.data.related, id: \.label) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.label)
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(section.words, id: \.self) { related in
                            NavigationLink(value: Route.wordDetail(word: related, context: [])) {
                                Text(related)
                                    .font(.body.weight(.medium))
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
                }
            }
        }
        .accessibilityIdentifier("word.related")
    }

    private var oxfordContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let paragraphs = model.data.oxford {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(Neo.bodyFont)
                        .lineSpacing(3)
                }
            } else {
                Text("No Oxford entry for this word")
                    .font(.headline)
                Text("This word isn't in the installed Oxford data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("word.oxford")
    }

    private var englishContent: some View {
        let senses = model.data.senses
        let byPos = Dictionary(grouping: senses, by: \.pos)
        let posOrder = ["noun", "verb", "adjective", "adverb"]
        return VStack(alignment: .leading, spacing: 16) {
            if senses.isEmpty {
                if let lines = model.data.dictWord?.definitionLines, !lines.isEmpty {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.body)
                    }
                } else {
                    Text("No English definition available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(posOrder.filter { byPos[$0] != nil }, id: \.self) { pos in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pos)
                        .font(.headline)
                    ForEach(Array((byPos[pos] ?? []).enumerated()), id: \.offset) { index, sense in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sense.gloss.prefix(1).capitalized + String(sense.gloss.dropFirst()) + ".")
                                    .font(.body)
                                ForEach(sense.examples.prefix(2), id: \.self) { example in
                                    Text("“\(example)”")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("word.english")
    }

    private var synonymsContent: some View {
        let sections = model.data.synonymSections
        return VStack(alignment: .leading, spacing: 16) {
            if sections.isEmpty {
                Text("No synonyms found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.pos)
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(section.synonyms, id: \.self) { synonym in
                            NavigationLink(value: Route.wordDetail(word: synonym, context: [])) {
                                Text(synonym)
                                    .font(.body)
                                    .foregroundStyle(Neo.blue)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(NeoPressStyle())
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("word.synonyms")
    }

    private var appleContent: some View {
        // Full-bleed: cancel the page's horizontal padding.
        AppleDictionaryInline(term: model.displayWord)
            .padding(.horizontal, -20)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    noteText = model.data.state.note
                    showNoteEditor = true
                } label: {
                    Label("Edit note", systemImage: "square.and.pencil")
                }
                Menu {
                    ForEach(WordDetailModel.knownWordMenu, id: \.rung) { item in
                        Button {
                            model.setKnownLevel(rung: item.rung)
                        } label: {
                            Label(item.label, systemImage: item.symbol)
                        }
                    }
                } label: {
                    Label("I Know This Word", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset Progress", systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("word.resetProgress")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("word.menu")
        }
    }
}

