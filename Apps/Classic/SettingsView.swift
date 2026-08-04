import SwiftUI
import VocabKit

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accent: PronunciationAccent = .american
    @State private var goalNew = 15
    @State private var goalReview = 30
    @State private var target = 90
    @State private var order: StudyOrder = .listOrder
    @State private var scheduler: SchedulerKind = .circles
    @State private var enabledDictionaries: Set<DictionarySource> = []
    @State private var expandGoal = false

    var body: some View {
        List {
            Section("Word List") {
                NavigationLink(value: Route.importWords) {
                    Label("Import Words", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("settings.import")
            }

            Section("Word") {
                Picker(selection: $accent) {
                    ForEach(PronunciationAccent.allCases, id: \.self) { accent in
                        Text(accent.label).tag(accent)
                    }
                } label: {
                    Label("Pronunciation", systemImage: "waveform")
                }
                .onChange(of: accent) { env.settings.pronunciationAccent = accent }
                .accessibilityIdentifier("settings.pronunciation")

                // Upgrade: choose which dictionaries show on the word page.
                ForEach([DictionarySource.oxford, .english, .synonyms, .apple], id: \.self) { source in
                    Toggle(isOn: binding(for: source)) {
                        Label {
                            HStack {
                                Text(source.label)
                                if !source.hasBundledData {
                                    Text("no data")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "character.book.closed")
                        }
                    }
                    .accessibilityIdentifier("settings.dictionary.\(source.rawValue)")
                }
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

                Picker(selection: $target) {
                    ForEach([70, 80, 90, 100], id: \.self) { value in
                        Text(">=\(value)%").tag(value)
                    }
                } label: {
                    Label("Target Familiarity", systemImage: "archivebox")
                }
                .onChange(of: target) { env.settings.targetFamiliarity = target }
                .accessibilityIdentifier("settings.targetFamiliarity")

                // The headline upgrade: default recitation order.
                Picker(selection: $order) {
                    ForEach(StudyOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                } label: {
                    Label("Study Order", systemImage: "arrow.up.arrow.down")
                }
                .onChange(of: order) { env.settings.studyOrder = order }
                .accessibilityIdentifier("settings.studyOrder")

                // Selectable memory algorithm; the default matches the
                // original app's circles.
                Picker(selection: $scheduler) {
                    ForEach(SchedulerKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                } label: {
                    Label("Algorithm", systemImage: "brain")
                }
                .onChange(of: scheduler) { env.settings.scheduler = scheduler }
                .accessibilityIdentifier("settings.scheduler")
            } header: {
                Text("Study")
            } footer: {
                Text(scheduler.summary)
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
        goalNew = env.settings.dailyGoalNew
        goalReview = env.settings.dailyGoalReview
        target = env.settings.targetFamiliarity
        order = env.settings.studyOrder
        scheduler = env.settings.scheduler
        enabledDictionaries = Set(env.settings.enabledDictionaries)
    }
}

struct ImportWordsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var importedList: WordList?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    (Text("Import words from a csv file, this file contains these columns: ")
                        + Text("word").bold()
                        + Text(", ")
                        + Text("note").bold()
                        + Text(" (optional)."))
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    exampleTable
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            Button {
                showPicker = true
            } label: {
                Text("Import")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(ClassicTheme.continueButtonBackground))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .accessibilityIdentifier("import.button")
        }
        .navigationTitle("Import Words")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
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

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                errorMessage = "Could not read the file."
                return
            }
            do {
                let rows = try CSVImport.parse(text)
                let name = url.deletingPathExtension().lastPathComponent
                importedList = CSVImport.importRows(rows, listName: name, userStore: env.userStore)
                env.touch()
            } catch {
                errorMessage = "The file must contain a 'word' column."
            }
        }
    }
}
