import SwiftUI
import VocabKit

/// Settings — same sections (Word List / Word / Study / About), rendered as
/// grouped white field blocks with internal hairlines, inline trailing
/// values, autosave, and a wheel sheet for the daily goal.
struct NeoSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accent: PronunciationAccent = .american
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
                group(title: "Word List") {
                    NavigationLink(value: Route.importWords) {
                        rowLabel("Import Words", trailing: "CSV")
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("settings.import")
                }

                group(title: "Word") {
                    menuRow("Pronunciation", value: accent.label) {
                        ForEach(PronunciationAccent.allCases, id: \.self) { option in
                            Button(option.label) {
                                accent = option
                                env.settings.pronunciationAccent = option
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.pronunciation")

                    hairline
                    ForEach([DictionarySource.oxford, .english, .synonyms, .apple], id: \.self) { source in
                        toggleRow(source)
                        if source != .apple { hairline }
                    }
                }

                group(title: "Study") {
                    Button {
                        showGoalSheet = true
                    } label: {
                        rowLabel("Daily Goal", trailing: "New \(goalNew) · Review \(goalReview)")
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("settings.dailyGoal")

                    hairline
                    menuRow("Target Familiarity", value: ">=\(target)%") {
                        ForEach([70, 80, 90, 100], id: \.self) { value in
                            Button(">=\(value)%") {
                                target = value
                                env.settings.targetFamiliarity = value
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.targetFamiliarity")

                    hairline
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

                    hairline
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
                }
                Text(scheduler.summary)
                    .font(.footnote)
                    .foregroundStyle(Neo.faint)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)

                group(title: "About") {
                    rowLabel("Version",
                             trailing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                             chevron: false)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .background(Neo.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(Neo.serif(17, weight: .semibold))
                    .foregroundStyle(Neo.ink)
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            goalSheet
                .presentationDetents([.height(320)])
        }
        .onAppear(perform: load)
    }

    // MARK: Building blocks

    private var hairline: some View {
        Rectangle().fill(Neo.hairline).frame(height: 0.5).padding(.leading, 16)
    }

    @ViewBuilder
    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NeoSectionHeader(title: title)
            .padding(.top, 26)
            .padding(.bottom, 8)
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
    }

    private func rowLabel(_ title: String, trailing: String, chevron: Bool = true) -> some View {
        HStack {
            Text(title)
                .font(Neo.sans(15, weight: .medium))
                .foregroundStyle(Neo.ink)
            Spacer()
            Text(trailing)
                .font(Neo.sans(15))
                .foregroundStyle(Neo.graphite)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Neo.faint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func menuRow<MenuContent: View>(_ title: String, value: String, @ViewBuilder menu: () -> MenuContent) -> some View {
        Menu {
            menu()
        } label: {
            HStack {
                Text(title)
                    .font(Neo.sans(15, weight: .medium))
                    .foregroundStyle(Neo.ink)
                Spacer()
                Text(value)
                    .font(Neo.sans(15))
                    .foregroundStyle(Neo.blue)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Neo.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
    }

    private func toggleRow(_ source: DictionarySource) -> some View {
        Toggle(isOn: binding(for: source)) {
            HStack(spacing: 6) {
                Text(source.label)
                    .font(Neo.sans(15, weight: .medium))
                    .foregroundStyle(Neo.ink)
                if !source.hasBundledData {
                    Text("no data")
                        .font(.caption2)
                        .foregroundStyle(Neo.warm)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Neo.warm.opacity(0.5), lineWidth: 0.8)
                        )
                }
            }
        }
        .tint(Neo.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("settings.dictionary.\(source.rawValue)")
    }

    private var goalSheet: some View {
        VStack(spacing: 12) {
            Text("Daily Goal")
                .font(Neo.serif(19, weight: .semibold))
                .foregroundStyle(Neo.ink)
                .padding(.top, 18)
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("NEW")
                        .font(.caption2.weight(.semibold))
                        .kerning(1)
                        .foregroundStyle(Neo.faint)
                    Picker("New", selection: $goalNew) {
                        ForEach(Array(stride(from: 0, through: 60, by: 5)), id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                VStack(spacing: 2) {
                    Text("REVIEW")
                        .font(.caption2.weight(.semibold))
                        .kerning(1)
                        .foregroundStyle(Neo.faint)
                    Picker("Review", selection: $goalReview) {
                        ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .frame(height: 180)
            .onChange(of: goalNew) { env.settings.dailyGoalNew = goalNew }
            .onChange(of: goalReview) { env.settings.dailyGoalReview = goalReview }
        }
        .presentationBackground(Neo.paper)
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

/// CSV import — same zone structure (explainer, example table, import action).
struct NeoImportWordsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var importedList: WordList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Words")
                    .font(Neo.pageTitle)
                    .foregroundStyle(Neo.ink)
                    .padding(.top, 10)
                (Text("A CSV file with columns ")
                    + Text("word").font(Neo.sans(15, weight: .semibold))
                    + Text(" and optional ")
                    + Text("note").font(Neo.sans(15, weight: .semibold))
                    + Text(". Each import creates a new list named after the file."))
                    .font(Neo.sans(15))
                    .foregroundStyle(Neo.graphite)
                    .lineSpacing(3)

                exampleTable

                HStack {
                    Spacer()
                    NeoPrimaryButton(title: "Choose File", systemImage: "square.and.arrow.down") {
                        showPicker = true
                    }
                    .accessibilityIdentifier("import.button")
                }
                .padding(.top, 8)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .background(Neo.paper)
        .navigationBarTitleDisplayMode(.inline)
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
            ("Back Down", "To withdraw your position in a fight or argument."),
            ("Beef Up", "To make changes or an improvement."),
            ("Blow Up", "To make something explode."),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("word").frame(width: 84, alignment: .leading)
                Text("note").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Neo.graphite)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Neo.sectionRule).frame(height: 0.8)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(Neo.serif(13))
                        .frame(width: 84, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(Neo.graphite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                if index < rows.count - 1 {
                    Rectangle().fill(Neo.hairline).frame(height: 0.5).padding(.leading, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Neo.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Neo.hairline, lineWidth: 0.8)
                )
        )
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
