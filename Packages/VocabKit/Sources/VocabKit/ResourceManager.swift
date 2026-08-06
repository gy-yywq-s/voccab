import Foundation

/// On-device resource registry — dictionaries, TTS models, audio caches.
///
/// The app is moving toward downloadable resources: some assets ship in the
/// bundle today for convenience, but everything routes through this registry
/// so the Data → Resources screen can show what is on the device, how big it
/// is, and delete anything that is not required. ECDICT (the default
/// definition provider) is the one undeletable resource.
public struct AppResource: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case dictionary
        case ttsModel
        case audioCache
    }

    public enum Location: Sendable {
        /// Ships inside the app bundle (cannot be deleted; removing it needs
        /// an app update).
        case bundled(URL?)
        /// Lives in the downloads directory (deletable).
        case downloaded(URL)
        /// Registered but not on this device yet.
        case notDownloaded
    }

    public let id: String
    public let title: String
    public let detail: String
    public let kind: Kind
    public let location: Location
    /// The definition provider (ECDICT) keeps the app functional — never
    /// deletable even once it moves out of the bundle.
    public let isRequired: Bool
    /// Public source files fetched on demand; empty means the resource has
    /// no download path yet.
    public var downloadURLs: [URL] = []

    public var sizeBytes: Int64 {
        switch location {
        case .bundled(let url):
            guard let url else { return 0 }
            return Self.size(of: url)
        case .downloaded(let url):
            return Self.size(of: url)
        case .notDownloaded:
            return 0
        }
    }

    public var isDeletable: Bool {
        if isRequired { return false }
        if case .downloaded = location { return true }
        return false
    }

    static func size(of url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
           values.isDirectory != true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

public enum ResourceManager {

    /// Where downloadable resources live (created on demand).
    public static var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Resources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func downloadedURL(for id: String) -> URL? {
        let url = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The full registry, reflecting current on-device state.
    public static func all() -> [AppResource] {
        let bundle = Bundle.main
        func bundled(_ name: String, _ ext: String) -> AppResource.Location {
            .bundled(bundle.url(forResource: name, withExtension: ext))
        }
        var resources: [AppResource] = [
            AppResource(
                id: "dict.ecdict",
                title: "English-Chinese (ECDICT)",
                detail: "Provides the definitions on every word card — required.",
                kind: .dictionary,
                location: bundled("voccab-dict", "sqlite"),
                isRequired: true),
            AppResource(
                id: "dict.extras",
                title: "Webster 1913 · Moby Thesaurus",
                detail: "The public-domain dictionary and thesaurus tabs.",
                kind: .dictionary,
                location: bundled("voccab-extras", "sqlite"),
                isRequired: false),
            AppResource(
                id: "dict.opengloss",
                title: "OpenGloss dictionaries",
                detail: "One download powering OpenGloss, OpenGloss Usage and OpenGloss Story.",
                kind: .dictionary,
                location: downloadedURL(for: "dict.opengloss").map { .downloaded($0) }
                    ?? .notDownloaded,
                isRequired: false),
            AppResource(
                id: "tts.libritts-r-medium",
                title: "Piper voice model (LibriTTS-R)",
                detail: "904-speaker neural text-to-speech, en_US. ~75 MB from Hugging Face.",
                kind: .ttsModel,
                location: downloadedURL(for: "tts.libritts-r-medium").map { .downloaded($0) }
                    ?? .notDownloaded,
                isRequired: false,
                downloadURLs: [
                    URL(string: "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx")!,
                    URL(string: "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx.json")!,
                ]),
        ]
        // Cached pronunciation recordings (Wikimedia fetches).
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let audio = caches.appendingPathComponent("PronunciationAudio", isDirectory: true)
        if FileManager.default.fileExists(atPath: audio.path) {
            resources.append(AppResource(
                id: "cache.pronunciation",
                title: "Downloaded pronunciations",
                detail: "Cached human recordings fetched while studying.",
                kind: .audioCache,
                location: .downloaded(audio),
                isRequired: false))
        }
        return resources
    }

    /// Fetches every source file of a downloadable resource into its
    /// downloads folder. Files land under temporary names and move into
    /// place only after all of them arrive, so a cancelled or failed
    /// download never leaves a half-installed resource behind.
    public static func download(_ resource: AppResource) async throws {
        guard !resource.downloadURLs.isEmpty else { return }
        let dir = downloadsDirectory.appendingPathComponent(resource.id, isDirectory: true)
        let staging = downloadsDirectory.appendingPathComponent(".\(resource.id).staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for url in resource.downloadURLs {
                let (temp, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                    throw URLError(.badServerResponse)
                }
                try Task.checkCancellation()
                let dest = staging.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: temp, to: dest)
            }
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.moveItem(at: staging, to: dir)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Deletes a deletable resource from disk. Returns true on success.
    @discardableResult
    public static func delete(_ resource: AppResource) -> Bool {
        guard resource.isDeletable, case .downloaded(let url) = resource.location else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
