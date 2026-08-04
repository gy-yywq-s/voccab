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

    private var dictionaryTabs: [DictionarySource] {
        env.settings.enabledDictionaries.filter { $0 != .chinese }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headword
                chineseDefinitions
                noteBlock
                NeoSectionHeader(title: "Study") {
                    Text(model.data.state.familiarity.map { "\($0)%" } ?? "Not set")
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
        .alert("Edit note", isPresented: $showNoteEditor) {
            TextField("Note", text: $noteText, axis: .vertical)
            Button("Save") { model.setNote(noteText) }
            Button("Cancel", role: .cancel) {}
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
                    Button {
                        model.toggleMyWords()
                    } label: {
                        Text("+ Word lists")
                            .font(Neo.caption.weight(.medium))
                            .foregroundStyle(Neo.blue)
                    }
                    .buttonStyle(NeoPressStyle())
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
            VStack(alignment: .leading, spacing: 3) {
                Text("note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Formatting.tidy(model.data.state.note))
                    .font(.body)
                    .foregroundStyle(Neo.warm)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
        }
    }

    /// Tags as one quiet metadata line (Curio temperament): plain text
    /// separated by dots, color only where it carries state.
    private var metadataLine: some View {
        let dictWord = model.data.dictWord
        return HStack(alignment: .top, spacing: 8) {
            FlowLayout(spacing: 6) {
                Group {
                    Text((dictWord?.frequencyBand ?? .unknown).label)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(Color(uiColor: .tertiaryLabel))
                    if model.data.listNames.isEmpty {
                        Button {
                            model.toggleMyWords()
                        } label: {
                            Text("+ Word lists")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Neo.blue)
                        }
                        .buttonStyle(NeoPressStyle())
                    } else {
                        ForEach(model.data.listNames, id: \.self) { name in
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.footnote)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    /// The Study section: a six-step segmented drag control (the reference
    /// "reasoning effort" pattern) for familiarity, then the schedule facts
    /// as scannable label/value rows.
    private var studyBlock: some View {
        let state = model.data.state
        return VStack(alignment: .leading, spacing: 14) {
            NeoFamiliaritySegments(value: state.familiarity) { newValue in
                model.setFamiliarity(newValue)
            }
            .padding(.top, 12)

            VStack(spacing: 0) {
                factRow("Studied", state.timesStudied == 0 ? "never" : "\(state.timesStudied) time\(state.timesStudied == 1 ? "" : "s")")
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
    // subordinate to (and distinct from) the blue familiarity segments.

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
        AppleDictionaryInline(term: model.displayWord)
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

/// Familiarity as a six-step segmented drag control, styled after the
/// reference "reasoning effort" segments: neutral gray track, thin dividers,
/// selected white segment with a light shadow. Drag slides the selection;
/// it snaps and commits on release. Tapping a segment commits directly.
struct NeoFamiliaritySegments: View {
    let value: Int?
    let onCommit: (Int) -> Void

    private static let steps = [0, 20, 40, 60, 80, 100]
    @State private var dragIndex: Int? = nil

    private var selectedIndex: Int? {
        if let dragIndex { return dragIndex }
        guard let value else { return nil }
        return Self.steps.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset
    }

    var body: some View {
        GeometryReader { proxy in
            let segmentWidth = proxy.size.width / CGFloat(Self.steps.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Neo.paleBlue)
                HStack(spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, _ in
                        if index > 0 {
                            Rectangle()
                                .fill(Neo.blue.opacity(0.22))
                                .frame(width: 0.7, height: 14)
                        }
                        Color.clear
                            .frame(width: segmentWidth - (index > 0 ? 0.7 : 0))
                    }
                }
                if let selected = selectedIndex {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: Neo.blue.opacity(0.25), radius: 2.5, y: 1)
                        .frame(width: segmentWidth - 6, height: 34)
                        .offset(x: CGFloat(selected) * segmentWidth + 3)
                        .animation(.easeOut(duration: 0.15), value: selected)
                }
                HStack(spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(step)")
                            .font(.system(size: 14, weight: index == selectedIndex ? .semibold : .regular))
                            .foregroundStyle(index == selectedIndex ? Neo.blue : Neo.blue.opacity(0.55))
                            .frame(width: segmentWidth, height: 40)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let index = min(Self.steps.count - 1, max(0, Int(gesture.location.x / segmentWidth)))
                        dragIndex = index
                    }
                    .onEnded { _ in
                        if let index = dragIndex {
                            onCommit(Self.steps[index])
                        }
                        dragIndex = nil
                    }
            )
        }
        .frame(height: 40)
        .accessibilityIdentifier("word.familiaritySlider")
    }
}
