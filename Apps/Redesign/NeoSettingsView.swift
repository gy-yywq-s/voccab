import SwiftUI
import VocabKit

/// A second-level separator for the footnote hints that hang under a settings
/// row (voice status, algorithm summary): inset to the row's text indent and
/// lighter than the full-width `NeoHairline`, so the hint reads as subordinate
/// to its row rather than as a row of its own.
struct NeoSubHairline: View {
    var body: some View {
        Rectangle()
            .fill(Neo.hairline.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 40)
    }
}

/// Settings — same sections (Word / Practice / About) styled after
/// the Passage "Reading settings" reference: bold sans sub-headings, plain
/// rows with hairlines, inline trailing values, native toggles, wheel sheet
/// for the daily goal. Autosave everywhere.
struct NeoSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accent: PronunciationAccent = .american
    @State private var pronunciationSource: PronunciationSource = .system
    @State private var voiceStatus = ""

    private var dictionarySummary: String {
        let count = env.settings.enabledDictionaries.count
        return "\(count) enabled"
    }
    @State private var goalNew = 15
    @State private var goalReview = 30
    @State private var order: StudyOrder = .listOrder
    @State private var scheduler: SchedulerKind = .circles
    @State private var enabledDictionaries: Set<DictionarySource> = []
    @State private var defaultDefinitions: DictionarySource = .chinese
    @State private var showGoalSheet = false
    @State private var pendingKind: SchedulerKind?
    @State private var switchPlan: AlgorithmSwitch.Plan?
    @State private var showSwitchConfirm = false
    @State private var showReviewOffer = false
    @State private var goToAlgSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NeoSectionHeader(title: "Word")
                    .padding(.top, 20)
                NavigationLink {
                    VoiceSettingsPage()
                } label: {
                    valueRow("Voice", value: env.settings.pronunciationSource.label,
                             chevron: true, icon: "person.wave.2")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.voice")
                if !voiceStatus.isEmpty {
                    NeoSubHairline()
                    Text(voiceStatus)
                        .font(.footnote)
                        .foregroundStyle(voiceStatus.hasPrefix("Recordings available") ? Color.green : .secondary)
                        .padding(.leading, 40)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                }
                NeoHairline()
                NavigationLink {
                    DictionaryPreviewPage()
                } label: {
                    valueRow("Dictionaries", value: dictionarySummary, chevron: true, icon: "character.book.closed")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.dictPreview")
                NeoHairline()
                menuRow("Definitions", value: defaultDefinitions.label, icon: "text.book.closed") {
                    ForEach(AppSettings.definitionCapableSources, id: \.self) { source in
                        Button {
                            defaultDefinitions = source
                            env.settings.defaultDefinitionSource = source
                        } label: {
                            if defaultDefinitions == source {
                                Label(source.label, systemImage: "checkmark")
                            } else {
                                Text(source.label)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("settings.definitions")
                NeoSubHairline()
                Text("The dictionary behind the default gloss on cards and word pages. Phonetics stay with English-Chinese, and anything it can't answer falls back there too.")
                    .font(.footnote)
                    .foregroundStyle(Neo.graphite)
                    .padding(.leading, 40)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                NeoHairline()

                NeoSectionHeader(title: "Practice")
                    .padding(.top, 28)
                Button {
                    showGoalSheet = true
                } label: {
                    valueRow("Daily Goal", value: "New \(goalNew) · Review \(goalReview)", chevron: true, icon: "target")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.dailyGoal")
                NeoHairline()
                menuRow("Order", value: order.shortLabel, icon: "arrow.up.arrow.down") {
                    ForEach(Array(StudyOrder.grouped.enumerated()), id: \.offset) { _, group in
                        Section(group.label) {
                            ForEach(group.options, id: \.self) { option in
                                Button {
                                    order = option
                                    env.settings.studyOrder = option
                                } label: {
                                    Label(option.label,
                                          systemImage: order == option ? "checkmark" : option.symbol)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("settings.studyOrder")
                NeoHairline()
                menuRow("Algorithm", value: scheduler.label, icon: "brain") {
                    ForEach(SchedulerKind.allCases, id: \.self) { kind in
                        Button {
                            requestSwitch(to: kind)
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
                NeoSubHairline()
                Text(scheduler.summary)
                    .font(.footnote)
                    .foregroundStyle(Neo.graphite)
                    .padding(.leading, 40)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                NeoHairline()
                NavigationLink {
                    AlgorithmPreviewPage()
                } label: {
                    valueRow("Compare Algorithms", value: "", chevron: true, icon: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.algPreview")
                NeoHairline()
                NavigationLink {
                    PracticeInputPage()
                } label: {
                    valueRow("Practice Settings", value: env.settings.answerStyle.label, chevron: true, icon: "hand.tap")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.practiceInput")
                NeoHairline()

                NeoSectionHeader(title: "Data")
                    .padding(.top, 28)
                NavigationLink {
                    DataToolsPage()
                } label: {
                    valueRow("Export · Import · Clear", value: "", chevron: true, icon: "externaldrive")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.data")
                NeoHairline()
                NavigationLink {
                    ResourcesPage()
                } label: {
                    valueRow("Resources", value: "", chevron: true, icon: "internaldrive")
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("settings.resources")
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
        .background(Neo.page)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGoalSheet) {
            goalSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: load)
        .navigationDestination(isPresented: $goToAlgSettings) {
            AlgorithmSettingsPage()
        }
        .alert("Switch to \(pendingKind?.label ?? "")?", isPresented: $showSwitchConfirm) {
            Button("Switch") { confirmSwitch() }
            Button("Cancel", role: .cancel) { pendingKind = nil; switchPlan = nil }
        } message: {
            Text(switchPlan?.summary ?? "")
        }
        .alert("Switched to \(scheduler.label)", isPresented: $showReviewOffer) {
            Button("Review Practice Settings") { goToAlgSettings = true }
            Button("Done", role: .cancel) {}
        } message: {
            Text("You can adjust its settings anytime; anything the switch auto-converted is marked there this once.")
        }
        .task {
            voiceStatus = "Checking pronunciation recordings…"
            switch await SpeechService.probeRecordingAvailability() {
            case .available:
                voiceStatus = "Recordings available (Wikimedia Commons)"
            case .unavailable(let reason):
                voiceStatus = "Recordings unavailable — \(reason)"
            case .checking:
                break
            }
        }
    }

    // MARK: Rows

    private func valueRow(_ title: String, value: String, chevron: Bool,
                          icon: String? = nil) -> some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Neo.blue)
                    .frame(width: 24, alignment: .leading)
            }
            Text(title)
                .font(.body)
                .foregroundStyle(Neo.ink)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(Neo.graphite)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Neo.faint)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func menuRow<MenuContent: View>(_ title: String, value: String, icon: String? = nil,
                                            @ViewBuilder menu: () -> MenuContent) -> some View {
        Menu {
            menu()
        } label: {
            HStack {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(Neo.blue)
                        .frame(width: 24, alignment: .leading)
                }
                Text(title)
                    .font(.body)
                    .foregroundStyle(Neo.ink)
                Spacer()
                HStack(spacing: 5) {
                    Text(value)
                        .font(.body)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Neo.graphite)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private func toggleRow(_ source: DictionarySource) -> some View {
        Toggle(isOn: binding(for: source)) {
            HStack(spacing: 6) {
                Text(source.label)
                    .font(.body)
                if !source.hasBundledData {
                    Text("download")
                        .font(.caption)
                        .foregroundStyle(Neo.graphite)
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
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            NeoHairline()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("New")
                        .font(.footnote)
                        .foregroundStyle(Neo.graphite)
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
                        .foregroundStyle(Neo.graphite)
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
        order = env.settings.studyOrder
        scheduler = env.settings.scheduler
        enabledDictionaries = Set(env.settings.enabledDictionaries)
        defaultDefinitions = env.settings.defaultDefinitionSource
    }
}

/// CSV import — same zone structure (explainer, example table, import action)
/// with a trailing pale-blue commit.
struct NeoImportWordsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var mergeTarget: WordList?
    @StateObject private var importRunner = ImportRunner()

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
                    .foregroundStyle(Neo.graphite)

                exampleTable

                HStack {
                    Text("Add to")
                        .font(Neo.bodyFont.weight(.medium))
                    Spacer()
                    Menu {
                        Button("New list") { mergeTarget = nil }
                        ForEach(env.userStore.lists(), id: \.id) { list in
                            Button(list.name) { mergeTarget = list }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(mergeTarget?.name ?? "New list")
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(Neo.bodyFont)
                        .foregroundStyle(Neo.graphite)
                    }
                    .accessibilityIdentifier("import.target")
                }
                .padding(.top, 8)

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
        .background(Neo.page)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPicker,
            // .item so no file is greyed out in the picker — format problems
            // are diagnosed (and usually repaired) after selection instead.
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .failure(let error):
                importRunner.failureReason = "Not imported. \(error.localizedDescription)"
            case .success(let url):
                importRunner.importFile(
                    url: url, mergeInto: mergeTarget?.id,
                    userStore: env.userStore) { env.touch() }
            }
        }
        .importFlowUI(importRunner) { dismiss() }
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
            .foregroundStyle(Neo.graphite)
            .padding(.vertical, 8)
            NeoHairline()
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.footnote.weight(.medium))
                        .frame(width: 90, alignment: .leading)
                    Text(row.1)
                        .font(.footnote)
                        .foregroundStyle(Neo.graphite)
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

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importRunner.failureReason = "Not imported. The clipboard is empty."
            return
        }
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        importRunner.importText(
            text, listName: "Pasted \(stamp)", mergeInto: mergeTarget?.id,
            userStore: env.userStore) { env.touch() }
    }
}

extension NeoSettingsView {
    private func requestSwitch(to kind: SchedulerKind) {
        guard kind != env.settings.scheduler else { return }
        pendingKind = kind
        switchPlan = AlgorithmSwitch.plan(from: env.settings.scheduler, to: kind,
                                          settings: env.settings, store: env.userStore)
        showSwitchConfirm = true
    }

    private func confirmSwitch() {
        guard let kind = pendingKind, let plan = switchPlan else { return }
        AlgorithmSwitch.apply(plan, to: kind, settings: env.settings, store: env.userStore)
        scheduler = kind
        pendingKind = nil
        switchPlan = nil
        env.touch()
        showReviewOffer = true
    }
}
