import SwiftUI
import VocabKit

/// "Import into Library…" — the one place the draft crosses into the app's real
/// data. Deliberately manual and deliberately explicit about what it did: the
/// draft is a scratchpad, and nothing leaves it without being asked.
struct ImportSheet: View {
    let rows: [DraftRow]
    /// Called after a successful import so the workspace can offer to clear.
    let onImported: () -> Void

    @EnvironmentObject private var env: MacEnvironment
    @Environment(\.dismiss) private var dismiss

    private enum Target: Hashable {
        case newList
        case existing(Int)
    }

    @State private var target: Target = .newList
    @State private var newListName = "Drafted Words"
    @State private var lists: [WordList] = []
    @State private var outcome: Outcome?

    private struct Outcome {
        var succeeded: Bool
        var title: String
        var detail: String
    }

    private var importable: [DraftRow] {
        rows.filter(\.isSubstantive)
    }

    private var wordCount: Int {
        importable.count
    }

    private var canImport: Bool {
        guard wordCount > 0 else { return false }
        switch target {
        case .newList:
            return !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existing:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MacHairline()
            if let outcome {
                result(outcome)
            } else {
                form
            }
            MacHairline()
            footer
        }
        .frame(width: 460)
        .background(Mac.paper)
        .onAppear {
            lists = env.userStore.lists()
            if lists.isEmpty { target = .newList }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Import into Library")
                .font(.system(size: 15, weight: .semibold))
            Text(wordCount == 1
                 ? "1 word from the draft."
                 : "\(wordCount) words from the draft.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Destination", selection: $target) {
                Text("New list").tag(Target.newList)
                ForEach(lists) { list in
                    Text("\(list.name) · \(list.wordCount)").tag(Target.existing(list.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .newList = target {
                VStack(alignment: .leading, spacing: 5) {
                    Text("List name")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("", text: $newListName)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text("Words already in the list are left where they are. A note on a word that already has a different note is appended on a new line, never overwritten.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if wordCount == 0 {
                Text("Nothing to import — no row in the draft has a word yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func result(_ outcome: Outcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome.succeeded ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.title)
                    .font(.system(size: 13, weight: .medium))
                Text(outcome.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if outcome == nil {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { performImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Import

    private func performImport() {
        let parsed = DraftTransfer.importedRows(from: importable)
        guard !parsed.isEmpty else {
            outcome = Outcome(
                succeeded: false,
                title: "Nothing was imported",
                detail: "None of the drafted rows had a usable word. The draft is untouched."
            )
            return
        }

        let listName: String
        let mergeID: Int?
        switch target {
        case .newList:
            listName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
            mergeID = nil
        case .existing(let id):
            listName = lists.first(where: { $0.id == id })?.name ?? ""
            mergeID = id
        }

        let list = CSVImport.importRows(
            parsed,
            listName: listName,
            userStore: env.userStore,
            mergeInto: mergeID
        )
        let merged = CSVImport.lastMergedNoteCount

        guard let list else {
            outcome = Outcome(
                succeeded: false,
                title: "The list could not be created",
                detail: "Nothing was written. Your draft is untouched — try a different list name."
            )
            return
        }

        let skipped = importable.count - parsed.count
        var details: [String] = [
            "\(parsed.count) \(parsed.count == 1 ? "word" : "words") sent to “\(list.name)”.",
        ]
        if merged > 0 {
            details.append("Notes merged on \(merged) existing \(merged == 1 ? "word" : "words").")
        }
        if skipped > 0 {
            details.append("\(skipped) duplicate or unusable \(skipped == 1 ? "row was" : "rows were") skipped.")
        }
        details.append("The draft was left as it is.")

        env.touch()
        onImported()
        outcome = Outcome(
            succeeded: true,
            title: "Imported into “\(list.name)”",
            detail: details.joined(separator: " ")
        )
    }
}
