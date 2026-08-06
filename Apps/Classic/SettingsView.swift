import SwiftUI
import VocabKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accent: PronunciationAccent = .american
    @State private var pronunciationSource: PronunciationSource = .system
    @State private var voiceStatus = ""
    @State private var goalNew = 15
    @State private var goalReview = 30
    @State private var order: StudyOrder = .listOrder
    @State private var scheduler: SchedulerKind = .circles
    @State private var enabledDictionaries: Set<DictionarySource> = []
    @State private var expandGoal = false
    @State private var pendingKind: SchedulerKind?
    @State private var switchPlan: AlgorithmSwitch.Plan?
    @State private var showSwitchConfirm = false
    @State private var showReviewOffer = false
    @State private var goToAlgSettings = false

    var body: some View {
        List {
            Section("Word") {
                NavigationLink {
                    VoiceSettingsPage()
                } label: {
                    Label("Voice", systemImage: "person.wave.2")
                        .badge(env.settings.pronunciationSource.label)
                }
                .accessibilityIdentifier("settings.voice")

                if !voiceStatus.isEmpty {
                    Text(voiceStatus)
                        .font(.footnote)
                        .foregroundStyle(voiceStatus.hasPrefix("Recordings available") ? Color.green : .secondary)
                }

                NavigationLink {
                    DictionaryPreviewPage()
                } label: {
                    Label("Dictionaries", systemImage: "text.book.closed")
                        .badge("\(env.settings.enabledDictionaries.count) enabled")
                }
                .accessibilityIdentifier("settings.dictPreview")
            }

            Section {
                DisclosureGroup(isExpanded: $expandGoal) {
                    goalEditor
                } label: {
                    HStack {
                        Label("Daily Goal", systemImage: "star.square")
                        Spacer()
                        Text("New \(goalNew) Review \(goalReview)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.dailyGoal")

                // The headline upgrade: default recitation order.
                Picker(selection: $order) {
                    ForEach(Array(StudyOrder.grouped.enumerated()), id: \.offset) { _, group in
                        Section(group.label) {
                            ForEach(group.options, id: \.self) { order in
                                Label(order.label, systemImage: order.symbol).tag(order)
                            }
                        }
                    }
                } label: {
                    Label("Practice Order", systemImage: "arrow.up.arrow.down")
                }
                .onChange(of: order) { env.settings.studyOrder = order }
                .accessibilityIdentifier("settings.studyOrder")

                // Selectable memory algorithm; Memory Circles is the default.
                Picker(selection: $scheduler) {
                    ForEach(SchedulerKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                } label: {
                    Label("Algorithm", systemImage: "brain")
                }
                .onChange(of: scheduler) {
                    guard scheduler != env.settings.scheduler else { return }
                    pendingKind = scheduler
                    scheduler = env.settings.scheduler   // hold until confirmed
                    switchPlan = AlgorithmSwitch.plan(from: env.settings.scheduler, to: pendingKind!,
                                                      settings: env.settings, store: env.userStore)
                    showSwitchConfirm = true
                }
                .accessibilityIdentifier("settings.scheduler")

                NavigationLink {
                    AlgorithmSettingsPage()
                } label: {
                    Label("Algorithm Settings", systemImage: "slider.horizontal.3")
                        .badge(scheduler.label)
                }
                .accessibilityIdentifier("settings.algSettings")

                NavigationLink {
                    AlgorithmPreviewPage()
                } label: {
                    Label("Compare Algorithms", systemImage: "chart.line.uptrend.xyaxis")
                }
                .accessibilityIdentifier("settings.algPreview")

                NavigationLink {
                    PracticeInputPage()
                } label: {
                    Label("Practice Settings", systemImage: "hand.tap")
                        .badge(env.settings.answerStyle.label)
                }
                .accessibilityIdentifier("settings.practiceInput")
            } header: {
                Text("Practice")
            } footer: {
                Text(scheduler.summary)
            }

            Section("Data") {
                NavigationLink {
                    DataToolsPage()
                } label: {
                    Label("Export · Import · Clear", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.data")
            }

            Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .navigationDestination(isPresented: $goToAlgSettings) {
            AlgorithmSettingsPage()
        }
        .alert("Switch to \(pendingKind?.label ?? "")?", isPresented: $showSwitchConfirm) {
            Button("Switch") {
                if let kind = pendingKind, let plan = switchPlan {
                    AlgorithmSwitch.apply(plan, to: kind, settings: env.settings, store: env.userStore)
                    scheduler = kind
                    env.touch()
                    showReviewOffer = true
                }
                pendingKind = nil
                switchPlan = nil
            }
            Button("Cancel", role: .cancel) { pendingKind = nil; switchPlan = nil }
        } message: {
            Text(switchPlan?.summary ?? "")
        }
        .alert("Switched to \(scheduler.label)", isPresented: $showReviewOffer) {
            Button("Review Algorithm Settings") { goToAlgSettings = true }
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

    private var goalEditor: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                presetChip("Default", new: 15, review: 30)
                presetChip("More New", new: 30, review: 30)
                presetChip("More Review", new: 15, review: 60)
            }
            HStack {
                Picker("New", selection: $goalNew) {
                    ForEach(Array(stride(from: 0, through: 60, by: 5)), id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .clipped()
                Picker("Review", selection: $goalReview) {
                    ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .clipped()
            }
            .onChange(of: goalNew) { env.settings.dailyGoalNew = goalNew }
            .onChange(of: goalReview) { env.settings.dailyGoalReview = goalReview }
        }
    }

    private func presetChip(_ label: String, new: Int, review: Int) -> some View {
        Button(label) {
            goalNew = new
            goalReview = review
            env.settings.dailyGoalNew = new
            env.settings.dailyGoalReview = review
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
        .foregroundStyle(goalNew == new && goalReview == review ? Color.accentColor : .secondary)
        .buttonStyle(.plain)
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
    }
}

struct ImportWordsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var mergeTarget: WordList?
    @StateObject private var importRunner = ImportRunner()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    (Text("Import a word table from a file or the clipboard. CSV, TSV (Excel / Numbers / Sheets copy-paste), semicolon tables and plain lists like ")
                        + Text("1. word - meaning").bold()
                        + Text(" all work. Columns can be named ")
                        + Text("word").bold()
                        + Text(" and ")
                        + Text("note").bold()
                        + Text(" but don't have to be."))
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    exampleTable

                    HStack {
                        Text("Add to")
                            .font(.headline)
                        Spacer()
                        Menu {
                            Button("New list") { mergeTarget = nil }
                            ForEach(env.userStore.lists(), id: \.id) { list in
                                Button(list.name) { mergeTarget = list }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(mergeTarget?.name ?? "New list")
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.tint)
                        }
                        .accessibilityIdentifier("import.target")
                    }
                    .padding(.top, 10)

                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            HStack(spacing: 12) {
                Button {
                    importFromClipboard()
                } label: {
                    Text("Paste")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(ClassicTheme.continueButtonBackground))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("import.paste")

                Button {
                    showPicker = true
                } label: {
                    Text("Import File")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(ClassicTheme.continueButtonBackground))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("import.button")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationTitle("Import Words")
        .navigationBarTitleDisplayMode(.large)
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
            ("Ask For", "To request something."),
            ("Back Down", "To withdraw your position in a fight, argument, plan, etc."),
            ("Back Up", "To walk or drive a vehicle backwards."),
            ("Beef Up", "To make changes or an improvement."),
            ("Believe In", "To feel confident about something or someone."),
            ("Blow Out", "To extinguish or make a flame stop burning."),
            ("Blow Up", "To make something explode."),
        ]
        return VStack(spacing: 0) {
            HStack {
                Text("word").bold().frame(width: 90, alignment: .leading)
                Text("note").bold().frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .padding(6)
            .background(Color(uiColor: .systemGray4))
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0).bold().frame(width: 90, alignment: .leading)
                    Text(row.1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .padding(6)
                .background(index.isMultiple(of: 2) ? Color(uiColor: .systemGray6) : Color(uiColor: .systemGray5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
