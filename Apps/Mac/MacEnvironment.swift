import Foundation
import SwiftUI
import VocabKit

/// What a live word-field lookup found.
enum LookupResult: Equatable {
    /// Nothing typed yet.
    case empty
    /// The bundled dictionary could not be opened at all.
    case unavailable
    /// Typed, looked up, no headword — shown quietly, never as an error.
    case missing
    case found(DictWord)

    var dictWord: DictWord? {
        if case .found(let word) = self { return word }
        return nil
    }
}

/// Everything the inspector shows for one word, gathered in a single pass.
struct MacWordDetail {
    var term: String
    var dictWord: DictWord?
    var senses: [WordNetSense] = []
    var webster: [String]?
    var moby: [String]?
    var related: [(label: String, words: [String])] = []

    var isEmpty: Bool {
        dictWord == nil && senses.isEmpty && (webster?.isEmpty ?? true) && (moby?.isEmpty ?? true)
    }

    /// WordNet synonym groups, one per part of speech, deduplicated in order.
    var synonymSections: [(pos: String, synonyms: [String])] {
        var order: [String] = []
        var grouped: [String: [String]] = [:]
        var seen: [String: Set<String>] = [:]
        for sense in senses {
            if grouped[sense.pos] == nil {
                order.append(sense.pos)
                grouped[sense.pos] = []
                seen[sense.pos] = []
            }
            for synonym in sense.synonyms {
                let key = synonym.lowercased()
                guard key != term.lowercased(), seen[sense.pos]?.contains(key) == false else { continue }
                seen[sense.pos]?.insert(key)
                grouped[sense.pos]?.append(synonym)
            }
        }
        return order.compactMap { pos in
            guard let words = grouped[pos], !words.isEmpty else { return nil }
            return (pos, words)
        }
    }
}

/// Dependency container for the Mac app: the bundled dictionary, the user's
/// library, and settings. Deliberately a smaller sibling of the iOS
/// `AppEnvironment` — the workspace needs read access to the dictionary and
/// write access to the library, and nothing else.
///
/// Every dictionary call happens on the main actor. `Database` serialises its
/// own access through a private queue, and the lookups here are single indexed
/// row fetches behind a 300 ms debounce, so there is nothing to gain from
/// moving them off and plenty of `Sendable` friction to avoid.
@MainActor
final class MacEnvironment: ObservableObject {
    let dictionary: DictionaryStore?
    let userStore: UserStore
    let settings: AppSettings

    /// Bumped after a library import so views that read `userStore` refresh.
    @Published var dataVersion = 0

    private var lookupCache: [String: DictWord?] = [:]

    init() {
        let dictPath = Bundle.main.path(forResource: "voccab-dict", ofType: "sqlite")
        let extrasPath = Bundle.main.path(forResource: "voccab-extras", ofType: "sqlite")
        dictionary = dictPath.flatMap { try? DictionaryStore(databasePath: $0, extrasPath: extrasPath) }

        // The user's library sits beside the draft, so everything this app
        // owns is in one folder the user can find, back up, or move.
        try? FileManager.default.createDirectory(
            at: VoccabMacPaths.supportDirectory, withIntermediateDirectories: true
        )
        let dbPath = VoccabMacPaths.supportDirectory
            .appendingPathComponent("voccab-user.sqlite").path

        // Fall back to a temp path only if Application Support is unwritable,
        // so the workspace still opens and the draft still saves.
        userStore = (try? UserStore(databasePath: dbPath))
            ?? (try! UserStore(databasePath: FileManager.default.temporaryDirectory
                .appendingPathComponent("voccab-user.sqlite").path))
        settings = AppSettings()
    }

    func touch() {
        dataVersion += 1
    }

    // MARK: - Lookups

    /// Live lookup for a workspace row. Cached, because the same word is
    /// re-resolved every time its row redraws.
    func lookup(_ term: String) -> LookupResult {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return .empty }
        guard let dictionary else { return .unavailable }
        if let cached = lookupCache[key] {
            return cached.map(LookupResult.found) ?? .missing
        }
        let found = dictionary.lookup(key)
        if lookupCache.count > 2_000 { lookupCache.removeAll(keepingCapacity: true) }
        lookupCache[key] = found
        return found.map(LookupResult.found) ?? .missing
    }

    /// Everything the inspector needs for one word.
    func detail(for term: String) -> MacWordDetail {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = MacWordDetail(term: trimmed, dictWord: nil, webster: nil, moby: nil)
        guard !trimmed.isEmpty, let dictionary else { return detail }
        // Prefer the dictionary's own spelling of the headword for the lookups
        // that follow, so "Corsage" finds the same rows as "corsage".
        let word = dictionary.lookup(trimmed)
        let headword = word?.word ?? trimmed
        detail.dictWord = word
        detail.senses = dictionary.senses(for: headword)
        detail.webster = dictionary.websterEntry(for: headword)
        detail.moby = dictionary.mobySynonyms(for: headword)
        detail.related = word.map { dictionary.relatedForms(of: $0) } ?? []
        return detail
    }
}
