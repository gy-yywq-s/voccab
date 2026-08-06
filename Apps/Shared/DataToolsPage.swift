import SwiftUI
import UniformTypeIdentifiers
import VocabKit

/// Settings subpage: export (log / words / everything), import a previous
/// export, and wipe. Shared by both frontends.
struct DataToolsPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showImporter = false
    @State private var confirmClear = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                exportRow(title: "Export Study Log", subtitle: "Every review as CSV") {
                    DataTransfer.exportCSV(table: "study_log", from: env.userStore, name: "voccab-study-log.csv")
                }
                exportRow(title: "Export All Words", subtitle: "Words, notes, and progress as CSV") {
                    DataTransfer.exportCSV(table: "word_state", from: env.userStore, name: "voccab-words.csv")
                }
                exportRow(title: "Export Everything", subtitle: "All tables + settings + docs, as ZIP") {
                    DataTransfer.exportAll(store: env.userStore, settings: env.settings)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("The ZIP includes README-DATA.md documenting every file and column, and can be imported back below.")
            }

            Section("Restore") {
                Button {
                    showImporter = true
                } label: {
                    Label("Import from ZIP", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("data.import")
            }

            Section {
                NavigationLink {
                    ResourcesPage()
                } label: {
                    Label("Resources", systemImage: "internaldrive")
                }
                .accessibilityIdentifier("data.resources")
            } footer: {
                Text("Dictionaries and voice models on this device.")
            }

            Section {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear All Data", systemImage: "trash")
                }
                .accessibilityIdentifier("data.clear")
            } footer: {
                Text("Deletes lists, words, notes, progress, logs, and history on this device. Settings and the bundled dictionaries stay.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                if let summary = DataTransfer.importAll(from: url, store: env.userStore, settings: env.settings) {
                    message = "Restored: \(summary)."
                    env.touch()
                } else {
                    message = "Not a Voccab export ZIP — nothing was changed."
                }
            }
        }
        .confirmationDialog("Delete all your data on this device?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                DataTransfer.clearAll(store: env.userStore)
                env.touch()
                message = "All data cleared."
            }
        }
        .alert("Data", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func exportRow(title: String, subtitle: String, make: @escaping () -> URL?) -> some View {
        // Build lazily on tap so exports reflect the moment of sharing.
        ExportShareRow(title: title, subtitle: subtitle, make: make)
    }
}

/// Settings subpage: every dictionary, voice model and cache on this device —
/// what it is, how big it is, and (for downloads) a delete action. Deleting
/// the dictionary that currently provides the default definitions warns that
/// definitions fall back to English-Chinese.
struct ResourcesPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var resources: [AppResource] = []
    @State private var pendingDelete: AppResource?
    @State private var downloading: [String: Task<Void, Never>] = [:]
    @State private var downloadError: String?

    var body: some View {
        List {
            Section {
                ForEach(resources) { resource in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(resource.title)
                                if resource.isRequired {
                                    Text("REQUIRED")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(resource.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if downloading[resource.id] != nil {
                            ProgressView()
                            Button {
                                downloading[resource.id]?.cancel()
                                downloading[resource.id] = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        } else if case .notDownloaded = resource.location {
                            if resource.downloadURLs.isEmpty {
                                Text("Not downloaded")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Button {
                                    start(resource)
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("resources.download.\(resource.id)")
                            }
                        } else {
                            Text(ByteCountFormatter.string(fromByteCount: resource.sizeBytes,
                                                           countStyle: .file))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if resource.isDeletable, downloading[resource.id] == nil {
                            Button(role: .destructive) {
                                pendingDelete = resource
                            } label: {
                                Image(systemName: "trash")
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .accessibilityIdentifier("resources.\(resource.id)")
                }
            } footer: {
                Text("Bundled items ship with the app; downloaded items can be removed here and fetched again later. The definition provider (ECDICT) is required and never leaves.")
            }
        }
        .onAppear { resources = ResourceManager.all() }
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \(pendingDelete?.title ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let resource = pendingDelete {
                    _ = ResourceManager.delete(resource)
                    resources = ResourceManager.all()
                    env.touch()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteWarning)
        }
        .alert("Download failed", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK") { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }

    private var deleteWarning: String {
        guard let resource = pendingDelete else { return "" }
        if resource.id == "dict.opengloss",
           env.settings.defaultDefinitionSource == .openGloss {
            return "OpenGloss currently provides your default definitions. After deleting, definitions fall back to English-Chinese (ECDICT) until it is downloaded again."
        }
        return "This removes the download from this device. You can download it again later."
    }

    private func start(_ resource: AppResource) {
        guard downloading[resource.id] == nil else { return }
        downloading[resource.id] = Task {
            do {
                try await ResourceManager.download(resource)
            } catch is CancellationError {
                // User cancelled — nothing to report.
            } catch {
                downloadError = "Could not download \(resource.title). Check the connection and try again."
            }
            downloading[resource.id] = nil
            resources = ResourceManager.all()
            env.touch()
        }
    }
}

private struct ExportShareRow: View {
    let title: String
    let subtitle: String
    let make: () -> URL?
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) {
                    rowLabel(ready: true)
                }
            } else {
                Button {
                    url = make()
                } label: {
                    rowLabel(ready: false)
                }
            }
        }
    }

    private func rowLabel(ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if ready {
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote)
                }
            }
            Text(ready ? "Ready — tap to share" : subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
