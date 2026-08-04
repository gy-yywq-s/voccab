import SwiftUI
import VocabKit

/// Settings — same sections (Word List / Word / Study / About) styled after
/// the Passage "Reading settings" reference: bold sans sub-headings, plain
/// rows with hairlines, inline trailing values, native toggles, wheel sheet
/// for the daily goal. Autosave everywhere.
struct NeoSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accent: PronunciationAccent = .american
    @State private var pronunciationSource: PronunciationSource = .system
    @State private var goalNew = 15
    @State private var goalReview = 30
    @State private var target = 90
    @State private var order: StudyOrder = .listOrder
    @State private var scheduler: SchedulerKind = .circles
    @State private var enabledDictionaries: Set<DictionarySource> = []
    @State private var showGoalSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NeoSectionHeader(title: "Word list")
                    .padding(.top, 20)
                NavigationLink(value: Route.importWords) {
                    valueRow("Import Words", value: "CSV", chevron: true)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.import")
                NeoHairline()

                NeoSectionHeader(title: "Word")
                    .padding(.top, 28)
                menuRow("Pronunciation", value: accent.label) {
                    ForEach(PronunciationAccent.allCases, id: \.self) { option in
                        Button(option.label) {
                            accent = option
                            env.settings.pronunciationAccent = option
                        }
                    }
                }
                .accessibilityIdentifier("settings.pronunciation")
                NeoHairline()
                menuRow("Voice", value: pronunciationSource.label) {
                    ForEach(PronunciationSource.allCases, id: \.self) { option in
                        Button(option.label) {
                            pronunciationSource = option
                            env.settings.pronunciationSource = option
                        }
                    }
                }
                .accessibilityIdentifier("settings.voice")
                NeoHairline()
                NavigationLink {
                    DictionaryPreviewPage()
                } label: {
                    valueRow("Dictionary Preview", value: "", chevron: true)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.dictPreview")
                NeoHairline()
                ForEach([DictionarySource.oxford, .english, .synonyms, .webster, .moby, .apple], id: \.self) { source in
                    toggleRow(source)
                    NeoHairline()
                }

                NeoSectionHeader(title: "Study")
                    .padding(.top, 28)
                Button {
                    showGoalSheet = true
                } label: {
                    valueRow("Daily Goal", value: "New \(goalNew) · Review \(goalReview)", chevron: true)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.dailyGoal")
                NeoHairline()
                menuRow("Target Familiarity", value: ">=\(target)%") {
                    ForEach([70, 80, 90, 100], id: \.self) { value in
                        Button(">=\(value)%") {
                            target = value
                            env.settings.targetFamiliarity = value
                        }
                    }
                }
                .accessibilityIdentifier("settings.targetFamiliarity")
                NeoHairline()
                menuRow("Study Order", value: order.shortLabel) {
                    ForEach(StudyOrder.allCases, id: \.self) { option in
                        Button {
                            order = option
                            env.settings.studyOrder = option
                        } label: {
                            if order == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("settings.studyOrder")
                NeoHairline()
                menuRow("Algorithm", value: scheduler.label) {
                    ForEach(SchedulerKind.allCases, id: \.self) { kind in
                        Button {
                            scheduler = kind
                            env.settings.scheduler = kind
                        } label: {
                            if scheduler == kind {
                                Label(kind.label, systemImage: "checkmark")
                            } else {
                                Text(kind.label)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("settings.scheduler")
                Text(scheduler.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                NeoHairline()

                NeoSectionHeader(title: "About")
                    .padding(.top, 28)
                valueRow("Version",
                         value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                         chevron: false)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGoalSheet) {
            goalSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: load)
    }

    // MARK: Rows

    private func valueRow(_ title: String, value: String, chevron: Bool) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func menuRow<MenuContent: View>(_ title: String, value: String, @ViewBuilder menu: () -> MenuContent) -> some View {
        Menu {
            menu()
        } label: {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 5) {
                    Text(value)
                        .font(.body)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.7)
                )
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
    }

    private func toggleRow(_ source: DictionarySource) -> some View {
        Toggle(isOn: binding(for: source)) {
            HStack(spacing: 6) {
                Text(source.label)
                    .font(.body)
                if !source.hasBundledData {
                    Text("no data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Neo.navy)
        .padding(.vertical, 11)
        .accessibilityIdentifier("settings.dictionary.\(source.rawValue)")
    }

    private var goalSheet: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Daily Goal")
                    .font(.headline)
                Spacer()
                Button("Done") { showGoalSheet = false }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Neo.blue)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            NeoHairline()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("New")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("New", selection: $goalNew) {
                        ForEach(Array(stride(from: 0, through: 60, by: 5)), id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                VStack(spacing: 0) {
                    Text("Review")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("Review", selection: $goalReview) {
                        ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .frame(height: 190)
            .onChange(of: goalNew) { env.settings.dailyGoalNew = goalNew }
            .onChange(of: goalReview) { env.settings.dailyGoalReview = goalReview }
        }
    }

    private func binding(for source: DictionarySource) -> Binding<Bool> {
        Binding(
            get: { enabledDictionaries.contains(source) },
            set: { enabled in
                if enabled { enabledDictionaries.insert(source) } else { enabledDictionaries.remove(source) }
                env.settings.setDictionary(source, enabled: enabled)
            }
        )
    }

    private func load() {
        accent = env.settings.pronunciationAccent
        pronunciationSource = env.settings.pronunciationSource
        goalNew = env.settings.dailyGoalNew
        goalReview = env.settings.dailyGoalReview
        target = env.settings.targetFamiliarity
        order = env.settings.studyOrder
        scheduler = env.settings.scheduler
        enabledDictionaries = Set(env.settings.enabledDictionaries)
    }
}

/// CSV import — same zone structure (explainer, example table, import action)
/// with a trailing pale-blue commit.
struct NeoImportWordsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var importedList: WordList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Import Words")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 8)
                (Text("Import a word table from a file or the clipboard. CSV, TSV (Excel / Numbers / Sheets copy-paste), semicolon tables and plain lists like ")
                    + Text("1. word - meaning").bold()
                    + Text(" all work — headers are optional. Each import creates a new list."))
                    .font(.body)
                    .foregroundStyle(.secondary)

                exampleTable

                HStack {
                    Spacer()
                    NeoQuietButton(title: "Paste", systemImage: "doc.on.clipboard") {
                        importFromClipboard()
                    }
                    .accessibilityIdentifier("import.paste")
                    NeoQuietButton(title: "Choose File", systemImage: "square.and.arrow.down") {
                        showPicker = true
                    }
                    .accessibilityIdentifier("import.button")
                }
                .padding(.top, 6)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
        ) { result in
            handle(result)
        }
        .alert("Import failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Imported", isPresented: .constant(importedList != nil)) {
            Button("OK") {
                importedList = nil
                dismiss()
            }
        } message: {
            Text("Created list “\(importedList?.name ?? "")” with \(importedList?.wordCount ?? 0) words.")
        }
    }

    private var exampleTable: some View {
        let rows: [(String, String)] = [
            ("Aim At", "To point a weapon at someone or something."),
            ("Back Down", "To withdraw your position in a fight or argument."),
            ("Beef Up", "To make changes or an improvement."),
            ("Blow Up", "To make something explode."),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("word").frame(width: 90, alignment: .leading)
                Text("note").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            NeoHairline()
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.footnote.weight(.medium))
                        .frame(width: 90, alignment: .leading)
                    Text(row.1)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
                if index < rows.count - 1 {
                    NeoHairline()
                }
            }
        }
        .accessibilityIdentifier("import.example")
    }

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = CSVImport.decode(data) else {
                errorMessage = "Could not read the file."
                return
            }
            importText(text, listName: url.deletingPathExtension().lastPathComponent)
        }
    }

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "The clipboard is empty."
            return
        }
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        importText(text, listName: "Pasted \(stamp)")
    }

    private func importText(_ text: String, listName: String) {
        do {
            let rows = try CSVImport.parse(text)
            importedList = CSVImport.importRows(rows, listName: listName, userStore: env.userStore)
            env.touch()
        } catch {
            errorMessage = "No words found — check the table or list format."
        }
    }
}
