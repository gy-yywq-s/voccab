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

    private var pages: [String] {
        context.isEmpty ? [word] : context
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
    @State private var showAppleDictionary = false

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
        .alert("Edit note", isPresented: $showNoteEditor) {
            TextField("Note", text: $noteText, axis: .vertical)
            Button("Save") { model.setNote(noteText) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAppleDictionary) {
            AppleDictionarySheet(term: model.displayWord)
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
                (Text("Note: ").bold() + Text(model.data.state.note))
                    .font(.title3)
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
        Group {
            if model.data.isInMyWords {
                Menu {
                    Button(role: .destructive) {
                        model.toggleMyWords()
                    } label: {
                        Label("Delete from My Words", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ClassicTheme.studyButtonText)
                }
            } else {
                Button {
                    model.toggleMyWords()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityIdentifier("word.addToMyWords")
    }

    private var tagRow: some View {
        let dictWord = model.data.dictWord
        let familiarity = model.data.state.familiarity
        return FlowLayout(spacing: 8) {
            TagChip(
                text: Formatting.familiarityChip(familiarity),
                background: familiarity == nil ? ClassicTheme.familiarityUnknownChip : ClassicTheme.familiarityChip
            )
            TagChip(
                text: Formatting.frequencyChip(dictWord?.frequencyBand ?? .unknown),
                background: ClassicTheme.frequencyChip
            )
            if let tags = dictWord?.examTags, let label = examTagChipLabel(tags) {
                TagChip(text: label, background: ClassicTheme.examChip)
            }
            if model.data.listNames.isEmpty {
                TagChip(text: "+ Word lists", background: ClassicTheme.listChip)
                    .onTapGesture { model.toggleMyWords() }
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
                Text("Set Familiarity:")
                    .font(.body)
                FamiliaritySlider(value: model.data.state.familiarity ?? 0) { newValue in
                    model.setFamiliarity(newValue)
                }
                Text("\(model.data.state.familiarity ?? 0)%")
                    .font(.body)
                    .frame(width: 52, alignment: .trailing)
            }
            let state = model.data.state
            Group {
                Text("You have studied this word \(state.timesStudied) time\(state.timesStudied == 1 ? "" : "s").")
                if let last = state.lastStudiedAt {
                    (Text("Last studied: ").bold() + Text(Formatting.relative(last)))
                }
                if let next = state.nextPlannedAt {
                    (Text("Next planned study: ").bold() + Text(Formatting.relative(next)))
                }
                if state.memoryCircle > 0 {
                    (Text("Memory: ").bold() + Text("Circle \(state.memoryCircle)"))
                }
                if state.timesStudied == 0 {
                    Text("You have never studied this word.")
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
                Text(source.label).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("word.tabs")
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
        case .apple:
            appleTab
        }
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
            Image(systemName: "text.book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Oxford dictionary data is not installed.")
                .font(.headline)
            Text("Licensed dictionary content can't be bundled with this build. Import your own Oxford data package in Settings to enable this tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Look up “\(model.displayWord)” in the system dictionary.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                showAppleDictionary = true
            } label: {
                Label("Open Apple Dictionary", systemImage: "character.book.closed")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
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
                    ForEach(WordDetailModel.familiarityMenu, id: \.value) { item in
                        Button {
                            model.setFamiliarity(item.value)
                        } label: {
                            Label(item.label, systemImage: item.symbol)
                        }
                    }
                } label: {
                    Label("Feel Familiar?", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("word.menu")
        }
    }
}

/// Discrete 20%-step slider matching the original "Set Familiarity" control.
struct FamiliaritySlider: View {
    @State private var sliderValue: Double
    private let onCommit: (Int) -> Void

    init(value: Int, onCommit: @escaping (Int) -> Void) {
        _sliderValue = State(initialValue: Double(value))
        self.onCommit = onCommit
    }

    var body: some View {
        Slider(value: $sliderValue, in: 0...100, step: 20) { editing in
            if !editing {
                onCommit(Int(sliderValue))
            }
        }
        .accessibilityIdentifier("word.familiaritySlider")
    }
}

