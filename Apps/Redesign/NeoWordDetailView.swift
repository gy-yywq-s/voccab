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
        .navigationBarTitleDisplayMode(.inline)
        .background(Neo.paper)
    }
}

/// Word page — same zones as classic (word header, note, tags, study info,
/// dictionary tabs) with the word treated as editorial content on paper:
/// no gray card, serif headword, hairline rules, quiet outlined tags,
/// underlined text tabs.
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
                tagRow
                if model.showStudyInfo {
                    studyInfo
                }
                tabBar
                    .padding(.top, 26)
                tabContent
                    .padding(.top, 18)
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .background(Neo.paper)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(model.displayWord)
                    .font(Neo.serif(38, weight: .semibold))
                    .foregroundStyle(Neo.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                Spacer()
                myWordsControl
            }
            HStack(spacing: 10) {
                if let phonetic = model.data.dictWord?.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(Neo.sans(16))
                        .foregroundStyle(Neo.graphite)
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
        .padding(.top, 8)
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
                        .foregroundStyle(Neo.graphite)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                }
                .buttonStyle(NeoPressStyle())
            }
        }
        .accessibilityIdentifier("word.addToMyWords")
    }

    private var chineseDefinitions: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let lines = model.data.dictWord?.translationLines, !lines.isEmpty {
                ForEach(lines, id: \.self) { line in
                    definitionLine(line)
                }
            } else {
                Text("No dictionary entry")
                    .font(Neo.sans(16))
                    .foregroundStyle(Neo.faint)
            }
        }
        .padding(.top, 16)
    }

    /// Splits "pron. 一些, 一部分" into a small italic POS and the body text.
    private func definitionLine(_ line: String) -> some View {
        let parts = splitPOS(line)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let pos = parts.pos {
                Text(pos)
                    .font(Neo.serif(14).italic())
                    .foregroundStyle(Neo.faint)
                    .frame(minWidth: 34, alignment: .leading)
            }
            Text(parts.body)
                .font(Neo.sans(17))
                .foregroundStyle(Neo.ink)
                .lineSpacing(2)
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
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Neo.warm)
                    .frame(width: 2)
                (Text("Note  ").font(Neo.sans(13, weight: .semibold)).foregroundColor(Neo.warm)
                    + Text(model.data.state.note).font(Neo.sans(15)).foregroundColor(Neo.graphite))
                    .lineSpacing(2)
            }
            .padding(.top, 14)
        }
    }

    private var tagRow: some View {
        let dictWord = model.data.dictWord
        let familiarity = model.data.state.familiarity
        return HStack(spacing: 8) {
            FlowLayout(spacing: 8) {
                NeoTag(
                    text: Formatting.familiarityChip(familiarity),
                    color: familiarity == nil ? Neo.faint : (familiarity! >= 80 ? Neo.green : Neo.warm)
                )
                NeoTag(text: Formatting.frequencyChip(dictWord?.frequencyBand ?? .unknown), color: Neo.graphite)
                if let tags = dictWord?.examTags, let label = examTagChipLabel(tags) {
                    NeoTag(text: label, color: Neo.blue)
                }
                if model.data.listNames.isEmpty {
                    Button {
                        model.toggleMyWords()
                    } label: {
                        NeoTag(text: "+ Word lists", color: Neo.blue)
                    }
                    .buttonStyle(NeoPressStyle())
                } else {
                    let first = model.data.listNames[0]
                    let extra = model.data.listNames.count - 1
                    NeoTag(text: extra > 0 ? "\(first) & \(extra) more" : first, color: Neo.graphite)
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { model.showStudyInfo.toggle() }
            } label: {
                Image(systemName: model.showStudyInfo ? "chevron.up.circle" : "info.circle")
                    .font(.body)
                    .foregroundStyle(Neo.faint)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("word.studyInfoToggle")
        }
        .padding(.top, 16)
    }

    private var studyInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            NeoHairline()
                .padding(.bottom, 4)
            HStack(spacing: 12) {
                Text("Familiarity")
                    .font(Neo.sans(14, weight: .medium))
                    .foregroundStyle(Neo.graphite)
                NeoFamiliaritySlider(value: model.data.state.familiarity ?? 0) { newValue in
                    model.setFamiliarity(newValue)
                }
                Text("\(model.data.state.familiarity ?? 0)%")
                    .font(Neo.sans(14).monospacedDigit())
                    .foregroundStyle(Neo.ink)
                    .frame(width: 44, alignment: .trailing)
            }
            let state = model.data.state
            VStack(alignment: .leading, spacing: 4) {
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
            .foregroundStyle(Neo.faint)
            NeoHairline()
                .padding(.top, 4)
        }
        .padding(.top, 14)
        .accessibilityIdentifier("word.studyInfo")
    }

    // MARK: Dictionary tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                tabButton("Related", source: .chinese)
                ForEach(dictionaryTabs, id: \.self) { source in
                    tabButton(source.label, source: source)
                }
            }
        }
        .overlay(alignment: .bottom) {
            NeoHairline()
        }
        .accessibilityIdentifier("word.tabs")
    }

    private func tabButton(_ label: String, source: DictionarySource) -> some View {
        let isActive = tab == source
        return Button {
            tab = source
        } label: {
            Text(label)
                .font(Neo.sans(15, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Neo.ink : Neo.faint)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if isActive {
                        Rectangle().fill(Neo.ink).frame(height: 1.6)
                    }
                }
        }
        .buttonStyle(NeoPressStyle())
        .accessibilityIdentifier("word.tab.\(label)")
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
        VStack(alignment: .leading, spacing: 20) {
            if model.data.related.isEmpty {
                Text("No related forms.")
                    .font(.subheadline)
                    .foregroundStyle(Neo.faint)
            }
            ForEach(model.data.related, id: \.label) { section in
                VStack(alignment: .leading, spacing: 8) {
                    NeoSectionHeader(title: section.label)
                    FlowLayout(spacing: 10) {
                        ForEach(section.words, id: \.self) { related in
                            NavigationLink(value: Route.wordDetail(word: related, context: [])) {
                                Text(related)
                                    .font(Neo.serif(18))
                                    .foregroundStyle(Neo.blue)
                                    .underline(true, color: Neo.blue.opacity(0.35))
                                    .padding(.vertical, 4)
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
            Text("Oxford data not installed")
                .font(Neo.serif(19, weight: .semibold))
                .foregroundStyle(Neo.ink)
            Text("Licensed dictionary content can't ship with this build. Import an Oxford data package from Settings to enable this tab.")
                .font(.subheadline)
                .foregroundStyle(Neo.graphite)
                .lineSpacing(3)
        }
        .accessibilityIdentifier("word.oxford")
    }

    private var englishContent: some View {
        let senses = model.data.senses
        let byPos = Dictionary(grouping: senses, by: \.pos)
        let posOrder = ["noun", "verb", "adjective", "adverb"]
        return VStack(alignment: .leading, spacing: 18) {
            if senses.isEmpty {
                if let lines = model.data.dictWord?.definitionLines, !lines.isEmpty {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(Neo.sans(16))
                            .foregroundStyle(Neo.ink)
                    }
                } else {
                    Text("No English definition available.")
                        .font(.subheadline)
                        .foregroundStyle(Neo.faint)
                }
            }
            ForEach(posOrder.filter { byPos[$0] != nil }, id: \.self) { pos in
                VStack(alignment: .leading, spacing: 10) {
                    Text(pos)
                        .font(Neo.serif(15).italic())
                        .foregroundStyle(Neo.graphite)
                    ForEach(Array((byPos[pos] ?? []).enumerated()), id: \.offset) { index, sense in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1).")
                                .font(Neo.sans(14).monospacedDigit())
                                .foregroundStyle(Neo.faint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sense.gloss.prefix(1).capitalized + String(sense.gloss.dropFirst()) + ".")
                                    .font(Neo.sans(16))
                                    .foregroundStyle(Neo.ink)
                                    .lineSpacing(2)
                                ForEach(sense.examples.prefix(2), id: \.self) { example in
                                    Text("“\(example)”")
                                        .font(Neo.serif(15).italic())
                                        .foregroundStyle(Neo.graphite)
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
        return VStack(alignment: .leading, spacing: 18) {
            if sections.isEmpty {
                Text("No synonyms found.")
                    .font(.subheadline)
                    .foregroundStyle(Neo.faint)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.pos)
                        .font(Neo.serif(15).italic())
                        .foregroundStyle(Neo.graphite)
                    FlowLayout(spacing: 10) {
                        ForEach(section.synonyms, id: \.self) { synonym in
                            NavigationLink(value: Route.wordDetail(word: synonym, context: [])) {
                                Text(synonym)
                                    .font(Neo.sans(16))
                                    .foregroundStyle(Neo.blue)
                                    .padding(.vertical, 3)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("System dictionary")
                .font(Neo.serif(19, weight: .semibold))
                .foregroundStyle(Neo.ink)
            Text("Open “\(model.displayWord)” in Apple's built-in dictionaries.")
                .font(.subheadline)
                .foregroundStyle(Neo.graphite)
            NeoQuietButton(title: "Open Dictionary", systemImage: "character.book.closed") {
                showAppleDictionary = true
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.displayWord)
                .font(Neo.serif(17, weight: .semibold))
                .foregroundStyle(Neo.ink)
        }
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
                    .foregroundStyle(Neo.graphite)
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
