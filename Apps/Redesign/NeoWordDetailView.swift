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
    @State private var showAppleDictionary = false

    private var dictionaryTabs: [DictionarySource] {
        env.settings.enabledDictionaries.filter { $0 != .chinese }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headword
                chineseDefinitions
                noteBlock
                metadataLine
                if model.showStudyInfo {
                    studyInfo
                }
                tabBar
                    .padding(.top, 24)
                tabContent
                    .padding(.top, 16)
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
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

    // MARK: Header zone

    private var headword: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(model.displayWord)
                    .font(Neo.headword(36))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                Spacer()
                myWordsControl
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
            }
        }
        .padding(.top, 6)
        .accessibilityIdentifier("word.headerCard")
    }

    private var myWordsControl: some View {
        Group {
            if model.data.isInMyWords {
                Menu {
                    Button(role: .destructive) {
                        model.toggleMyWords()
                    } label: {
                        Label("Delete from My Words", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(Neo.blue)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                }
            } else {
                Button {
                    model.toggleMyWords()
                } label: {
                    Image(systemName: "bookmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                }
                .buttonStyle(NeoPressStyle())
            }
        }
        .accessibilityIdentifier("word.addToMyWords")
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
            (Text("Note  ").font(.subheadline.weight(.semibold)).foregroundColor(Neo.warm)
                + Text(model.data.state.note).font(.subheadline).foregroundColor(.secondary))
                .padding(.top, 12)
        }
    }

    /// Tags as one quiet metadata line (Curio temperament): plain text
    /// separated by dots, color only where it carries state.
    private var metadataLine: some View {
        let dictWord = model.data.dictWord
        let familiarity = model.data.state.familiarity
        return HStack(spacing: 6) {
            Group {
                if let familiarity {
                    Text("Familiarity \(familiarity)%")
                        .foregroundStyle(familiarity >= 80 ? Neo.green : Neo.warm)
                } else {
                    Text("Familiarity ?")
                        .foregroundStyle(.secondary)
                }
                Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel))
                Text((dictWord?.frequencyBand ?? .unknown).label)
                    .foregroundStyle(.secondary)
                if let tags = dictWord?.examTags, let label = examTagChipLabel(tags) {
                    Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Text(label)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)

            if model.data.listNames.isEmpty {
                Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel)).font(.footnote)
                Button {
                    model.toggleMyWords()
                } label: {
                    Text("+ Word lists")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Neo.blue)
                }
                .buttonStyle(NeoPressStyle())
            } else {
                Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel)).font(.footnote)
                Text(model.data.listNames.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation { model.showStudyInfo.toggle() }
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(model.showStudyInfo ? Neo.blue : Color.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("word.studyInfoToggle")
        }
        .padding(.top, 12)
    }

    private var studyInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Set familiarity")
                    .font(.subheadline)
                NeoFamiliaritySlider(value: model.data.state.familiarity ?? 0) { newValue in
                    model.setFamiliarity(newValue)
                }
                Text("\(model.data.state.familiarity ?? 0)%")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            let state = model.data.state
            VStack(alignment: .leading, spacing: 3) {
                if state.timesStudied == 0 {
                    Text("Never studied.")
                } else {
                    Text("Studied \(state.timesStudied) time\(state.timesStudied == 1 ? "" : "s")")
                    if let last = state.lastStudiedAt {
                        Text("Last studied \(Formatting.relative(last))")
                    }
                    if let next = state.nextPlannedAt {
                        Text("Next planned \(Formatting.relative(next))")
                    }
                    if state.memoryCircle > 0 {
                        Text("Memory circle \(state.memoryCircle)")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.top, 10)
        .accessibilityIdentifier("word.studyInfo")
    }

    // MARK: Dictionary tabs (native segmented)

    private var tabBar: some View {
        Picker("Dictionary", selection: $tab) {
            Text("Related").tag(DictionarySource.chinese)
            ForEach(dictionaryTabs, id: \.self) { source in
                Text(shortLabel(source)).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("word.tabs")
    }

    private func shortLabel(_ source: DictionarySource) -> String {
        switch source {
        case .english: return "English"
        case .synonyms: return "Synonyms"
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
        case .apple:
            appleContent
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Oxford data not installed")
                .font(.headline)
            Text("Licensed dictionary content can't ship with this build. Import an Oxford data package from Settings to enable this tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("System dictionary")
                .font(.headline)
            Text("Open “\(model.displayWord)” in Apple's built-in dictionaries.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NeoQuietButton(title: "Open Dictionary", systemImage: "character.book.closed") {
                showAppleDictionary = true
            }
        }
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

struct NeoFamiliaritySlider: View {
    @State private var sliderValue: Double
    private let onCommit: (Int) -> Void

    init(value: Int, onCommit: @escaping (Int) -> Void) {
        _sliderValue = State(initialValue: Double(value))
        self.onCommit = onCommit
    }

    var body: some View {
        Slider(value: $sliderValue, in: 0...100, step: 20) { editing in
            if !editing { onCommit(Int(sliderValue)) }
        }
        .tint(Neo.blue)
        .accessibilityIdentifier("word.familiaritySlider")
    }
}
