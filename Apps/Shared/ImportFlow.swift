import SwiftUI
import VocabKit

/// Drives a word-list import end to end: decoding, silent repair of common
/// file problems, and the final add-to-library step. The user never makes a
/// mid-import decision — the flow always ends in exactly one of two states:
/// imported (with a note about anything that had to be fixed) or a single
/// specific reason the file could not be imported. Repairs run off the main
/// thread with a visible status line and can be cancelled at any point.
@MainActor
final class ImportRunner: ObservableObject {

    struct Success: Equatable {
        var listName: String
        var wordCount: Int
        var mergedNotes: Int
        var fixes: [String]

        var message: String {
            var lines = ["Created list “\(listName)” with \(wordCount) word\(wordCount == 1 ? "" : "s")."]
            if mergedNotes > 0 {
                lines.append("Notes merged on \(mergedNotes) existing word\(mergedNotes == 1 ? "" : "s").")
            }
            if !fixes.isEmpty {
                lines.append("The file had problems that were fixed automatically:")
                lines.append(contentsOf: fixes.map { "• \($0)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    @Published var statusLine: String?
    @Published var success: Success?
    @Published var failureReason: String?

    var isRunning: Bool { statusLine != nil }

    /// Thread-safe cancel flag: `Task.cancel()` does not reach into the
    /// detached parsing task, so the pipeline polls this instead.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private var task: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    func importFile(url: URL, mergeInto listID: Int?, userStore: UserStore, onDone: (() -> Void)? = nil) {
        let listName = url.deletingPathExtension().lastPathComponent
        start(listName: listName, mergeInto: listID, userStore: userStore, onDone: onDone) { status, isCancelled in
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                throw ImportRepair.Failure.unfixable(reason:
                    "The file could not be read from its location. If it lives in iCloud Drive, make sure it has finished downloading, then try again.")
            }
            return try ImportRepair.run(data: data, status: status, isCancelled: isCancelled)
        }
    }

    func importText(_ text: String, listName: String, mergeInto listID: Int?, userStore: UserStore, onDone: (() -> Void)? = nil) {
        start(listName: listName, mergeInto: listID, userStore: userStore, onDone: onDone) { status, isCancelled in
            try ImportRepair.run(text: text, status: status, isCancelled: isCancelled)
        }
    }

    func cancel() {
        cancelFlag.set()
        task?.cancel()
        statusLine = nil
    }

    private func start(
        listName: String,
        mergeInto listID: Int?,
        userStore: UserStore,
        onDone: (() -> Void)?,
        work: @escaping @Sendable (
            _ status: @escaping @Sendable (String) -> Void,
            _ isCancelled: @escaping @Sendable () -> Bool
        ) throws -> ImportRepair.Outcome
    ) {
        guard !isRunning else { return }
        let flag = CancelFlag()
        cancelFlag = flag
        statusLine = "Reading the file…"
        let isCancelled: @Sendable () -> Bool = { flag.isSet }
        task = Task { [weak self] in
            let result: Result<ImportRepair.Outcome, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let outcome = try work({ line in
                        Task { @MainActor [weak self] in
                            if self?.isRunning == true { self?.statusLine = line }
                        }
                    }, isCancelled)
                    return .success(outcome)
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !flag.isSet else { return }
            switch result {
            case .failure(let error):
                self.statusLine = nil
                if let failure = error as? ImportRepair.Failure {
                    if failure == .cancelled { return }
                    self.failureReason = "Not imported. \(failure.reason)"
                } else {
                    self.failureReason = "Not imported. \(error.localizedDescription)"
                }
            case .success(let outcome):
                self.statusLine = "Adding words…"
                let list = CSVImport.importRows(
                    outcome.rows, listName: listName,
                    userStore: userStore, mergeInto: listID)
                self.statusLine = nil
                guard let list else {
                    self.failureReason = "Not imported. The words parsed correctly, but a list could not be created for them."
                    return
                }
                self.success = Success(
                    listName: list.name,
                    wordCount: list.wordCount,
                    mergedNotes: CSVImport.lastMergedNoteCount,
                    fixes: outcome.fixes)
                onDone?()
            }
        }
    }
}

/// Dim overlay with the current import status and a Cancel button, so a
/// slow repair never looks like a frozen app and can always be abandoned.
struct ImportProgressOverlay: View {
    @ObservedObject var runner: ImportRunner

    var body: some View {
        if let status = runner.statusLine {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("import.status")
                    Button("Cancel") { runner.cancel() }
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("import.cancel")
                }
                .padding(24)
                .frame(minWidth: 200)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .transition(.opacity)
        }
    }
}

extension View {
    /// Attaches the import progress overlay plus the two terminal alerts
    /// (imported / not imported) for the given runner.
    func importFlowUI(_ runner: ImportRunner, onImported: @escaping () -> Void = {}) -> some View {
        overlay { ImportProgressOverlay(runner: runner) }
            .animation(.easeInOut(duration: 0.15), value: runner.isRunning)
            .alert("Imported", isPresented: Binding(
                get: { runner.success != nil },
                set: { if !$0 { runner.success = nil } }
            )) {
                Button("OK") {
                    runner.success = nil
                    onImported()
                }
            } message: {
                Text(runner.success?.message ?? "")
            }
            .alert("Import failed", isPresented: Binding(
                get: { runner.failureReason != nil },
                set: { if !$0 { runner.failureReason = nil } }
            )) {
                Button("OK") { runner.failureReason = nil }
            } message: {
                Text(runner.failureReason ?? "")
            }
    }
}
