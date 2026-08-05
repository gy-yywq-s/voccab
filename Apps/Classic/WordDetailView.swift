import SwiftUI
import VocabKit

/// Horizontal pager so swiping left/right moves between neighboring words in
/// the list context (matches the original's paging behavior).
struct WordDetailPager: View {
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
                WordDetailView(model: WordDetailModel(word: pageWord, env: env))
                    .tag(pageWord)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(selection)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
    }
}

struct WordDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject var model: WordDetailModel
    @State private var tab: DictionarySource = .chinese
    @State private var showNoteEditor = false
    @State private var noteText = ""
    @State private var showNewListPrompt = false
    @State private var newListName = ""

    private var visibleTabs: [DictionarySource] {
        var tabs: [DictionarySource] = [.chinese]  // header card is Chinese; "Related" is always first tab
        tabs = env.settings.enabledDictionaries.filter { $0 != .chinese }
        return tabs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                if model.showStudyInfo {
                    studyInfoPanel
                }
                tabPicker
                tabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
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
    }

    // MARK: Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(model.displayWord)
                        .font(ClassicTheme.serifWord(size: 40))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                    Spacer()
                    addButton
                }
                HStack(spacing: 10) {
                    if let phonetic = model.data.dictWord?.phonetic, !phonetic.isEmpty {
                        Text("/\(phonetic)/")
                            .font(.title3)
                    }
                    Button {
                        model.speak()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                    }
                    .accessibilityIdentifier("word.speak")

                    // Inflected form: link straight to the base word.
                    if let base = model.data.dictWord?.baseForm {
                        NavigationLink(value: Route.wordDetail(word: base, context: [])) {
                            (Text("form of ").foregroundStyle(.secondary)
                                + Text(base).foregroundStyle(.blue).underline())
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("word.baseForm")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let lines = model.data.dictWord?.translationLines, !lines.isEmpty {
                        ForEach(lines, id: \.self) { line in
                            Text(line)
                                .font(.title3)
                        }
                    } else {
                        Text("No dictionary entry")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)

            if !model.data.state.note.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOTE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(Formatting.tidy(model.data.state.note))
                        .font(.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(ClassicTheme.noteBackground)
            }

            tagRow
                .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClassicTheme.cardBackground)
        )
        .accessibilityIdentifier("word.headerCard")
    }

    private var addButton: some View {
        Menu {
            listMenuItems
        } label: {
            if model.isInAnyList {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ClassicTheme.studyButtonText)
            } else {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityIdentifier("word.addToMyWords")
    }

    /// Menu entries shared by the add button and the "+ Word lists" chip:
    /// one toggle per list, then a new-list prompt.
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

    private var tagRow: some View {
        let dictWord = model.data.dictWord
        let recall = model.recall
        return FlowLayout(spacing: 8) {
            TagChip(
                text: Formatting.recallChip(recall),
                background: recall == nil ? ClassicTheme.recallUnknownChip : ClassicTheme.recallChip
            )
            TagChip(
                text: Formatting.frequencyChip(dictWord?.frequencyBand ?? .unknown),
                background: ClassicTheme.frequencyChip
            )
            if model.data.listNames.isEmpty {
                Menu {
                    listMenuItems
                } label: {
                    TagChip(text: "+ Word lists", background: ClassicTheme.listChip)
                }
            } else {
                let first = model.data.listNames[0]
                let extra = model.data.listNames.count - 1
                TagChip(
                    text: extra > 0 ? "\(first)&\(extra)+" : first,
                    background: ClassicTheme.listChip
                )
            }
            Spacer(minLength: 20)
            Button {
                withAnimation { model.showStudyInfo.toggle() }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("word.studyInfoToggle")
        }
    }

    private var studyInfoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                (Text("Recall: ").bold()
                    + Text(model.recall.map { "\(Int(($0 * 100).rounded()))%" } ?? "?"))
                    .font(.body)
                Spacer()
                // "I know this word": seeds the scheduler at rung 1-5.
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
                        Text("I know this word")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .font(.body.weight(.medium))
                }
                .accessibilityIdentifier("word.familiaritySlider")
            }
            let state = model.data.state
            Group {
                Text("You have practiced this word \(state.timesStudied) time\(state.timesStudied == 1 ? "" : "s").")
                if let last = state.lastStudiedAt {
                    (Text("Last practiced: ").bold() + Text(Formatting.relative(last)))
                }
                if let next = state.nextPlannedAt {
                    (Text("Next review: ").bold() + Text(Formatting.relative(next)))
                }
                if state.memoryCircle > 0 {
                    (Text("Memory: ").bold() + Text("Circle \(state.memoryCircle)"))
                }
                if state.timesStudied == 0 {
                    Text("You haven't practiced this word yet.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ClassicTheme.cardBackground.opacity(0.7))
        )
        .accessibilityIdentifier("word.studyInfo")
    }

    // MARK: Tabs

    private var tabPicker: some View {
        Picker("Dictionary", selection: $tab) {
            Text("Related").tag(DictionarySource.chinese)
            ForEach(visibleTabs, id: \.self) { source in
                Text(shortTabLabel(source)).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("word.tabs")
    }

    private func shortTabLabel(_ source: DictionarySource) -> String {
        switch source {
        case .english: return "English"
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
            relatedTab
        case .oxford:
            oxfordTab
        case .english:
            englishTab
        case .synonyms:
            synonymsTab
        case .webster:
            websterTab
        case .moby:
            mobyTab
        case .apple:
            appleTab
        }
    }

    private var websterTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let paragraphs = model.data.webster {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .lineSpacing(3)
                }
            } else {
                Text("No Webster 1913 entry for this word.")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityIdentifier("word.websterTab")
    }

    private var mobyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let synonyms = model.data.mobySynonyms {
                FlowLayout(spacing: 8) {
                    ForEach(synonyms, id: \.self) { synonym in
                        NavigationLink(value: Route.wordDetail(word: synonym, context: [])) {
                            Text(synonym)
                                .font(.body)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(ClassicTheme.wordChipBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No Moby Thesaurus entry for this word.")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityIdentifier("word.mobyTab")
    }

    private var relatedTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.data.related.isEmpty {
                Text("No related forms.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            ForEach(model.data.related, id: \.label) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.label)
                        .font(.title3.weight(.bold))
                    FlowLayout(spacing: 8) {
                        ForEach(section.words, id: \.self) { related in
                            NavigationLink(value: Route.wordDetail(word: related, context: [])) {
                                Text(related)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(ClassicTheme.wordChipBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
        .accessibilityIdentifier("word.related")
    }

    private var oxfordTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let paragraphs = model.data.oxford {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.displayWord)
                        .font(ClassicTheme.serifWord(size: 30))
                    if let phonetic = model.data.dictWord?.phonetic, !phonetic.isEmpty {
                        Text("| \(phonetic) |")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .lineSpacing(3)
                }
            } else {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No Oxford entry for this word.")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityIdentifier("word.oxford")
    }

    private var englishTab: some View {
        let senses = model.data.senses
        let byPos = Dictionary(grouping: senses, by: \.pos)
        let posOrder = ["noun", "verb", "adjective", "adverb"]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.displayWord)
                    .font(ClassicTheme.serifWord(size: 30))
                if let phonetic = model.data.dictWord?.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .foregroundStyle(.secondary)
                }
            }
            if senses.isEmpty {
                if let lines = model.data.dictWord?.definitionLines, !lines.isEmpty {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                    }
                } else {
                    Text("No English definition available.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(posOrder.filter { byPos[$0] != nil }, id: \.self) { pos in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pos)
                        .font(.title3.weight(.bold))
                    ForEach(Array((byPos[pos] ?? []).enumerated()), id: \.offset) { index, sense in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sense.gloss.prefix(1).capitalized + String(sense.gloss.dropFirst()) + ".")
                                ForEach(sense.examples.prefix(2), id: \.self) { example in
                                    Text("“\(example)”")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
        .accessibilityIdentifier("word.english")
    }

    private var synonymsTab: some View {
        let sections = model.data.synonymSections
        return VStack(alignment: .leading, spacing: 18) {
            if sections.isEmpty {
                Text("No synonyms found.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.pos)
                        .font(.title3.weight(.bold))
                    FlowLayout(spacing: 8) {
                        ForEach(section.synonyms, id: \.self) { synonym in
                            NavigationLink(value: Route.wordDetail(word: synonym, context: [])) {
                                Text(synonym)
                                    .font(.body)
                                    .foregroundStyle(.tint)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(ClassicTheme.wordChipBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
        .accessibilityIdentifier("word.synonyms")
    }

    private var appleTab: some View {
        AppleDictionaryInline(term: model.displayWord)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, -20)
            .padding(.top, 8)
    }

    // MARK: Toolbar

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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("word.menu")
        }
    }
}

