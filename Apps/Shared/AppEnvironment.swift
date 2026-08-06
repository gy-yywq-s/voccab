import Foundation
import SwiftUI
import VocabKit

/// Dependency container shared by both frontends. Also applies deterministic
/// UI-test seeding when launched with "-uitest".
@MainActor
final class AppEnvironment: ObservableObject {
    let dictionary: DictionaryStore?
    let userStore: UserStore
    let settings: AppSettings
    let speech = SpeechService()

    /// Opened fresh on each access so downloading or deleting the resource
    /// takes effect immediately; nil while the download isn't on the device.
    var openGloss: OpenGlossStore? { OpenGlossStore() }

    /// The default definition lines for a word, honoring the chosen source
    /// and falling back to ECDICT whenever that source can't answer —
    /// including after its resource was deleted.
    func definitionLines(for word: String, dictWord: DictWord?) -> [String] {
        switch settings.defaultDefinitionSource {
        case .english:
            let senses = dictionary?.senses(for: word) ?? []
            if !senses.isEmpty {
                return senses.prefix(4).map { "\($0.pos). \($0.gloss)" }
            }
        case .webster:
            if let paragraphs = dictionary?.websterEntry(for: word), !paragraphs.isEmpty {
                return Array(paragraphs.prefix(3))
            }
        case .openGloss:
            if let entry = openGloss?.entry(for: word), !entry.senses.isEmpty {
                return entry.senses.prefix(4).map { "\($0.pos). \($0.definition)" }
            }
        default:
            break
        }
        return dictWord?.translationLines ?? []
    }

    /// Bumped whenever user data changes so views refresh.
    @Published var dataVersion = 0

    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")

    init() {
        let bundlePath = Bundle.main.path(forResource: "voccab-dict", ofType: "sqlite")
        let extrasPath = Bundle.main.path(forResource: "voccab-extras", ofType: "sqlite")
        dictionary = bundlePath.flatMap { try? DictionaryStore(databasePath: $0, extrasPath: extrasPath) }

        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbName = Self.isUITest ? "voccab-uitest.sqlite" : "voccab-user.sqlite"
        let dbPath = supportDir.appendingPathComponent(dbName).path

        if Self.isUITest {
            try? FileManager.default.removeItem(atPath: dbPath)
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
        }

        // Fall back to a temp path only if Application Support is unwritable.
        userStore = (try? UserStore(databasePath: dbPath))
            ?? (try! UserStore(databasePath: FileManager.default.temporaryDirectory
                .appendingPathComponent("voccab-user.sqlite").path))
        settings = AppSettings()

        // Only UI tests get the embedded deterministic walkthrough content.
        if Self.isUITest {
            seedUITestList()
            UITestSeeder.seed(userStore: userStore, dictionary: dictionary, settings: settings)
        }
        // First launch with no lists at all: create a starter list so word
        // pages have somewhere to save into.
        if userStore.lists().isEmpty {
            userStore.createList(name: "Notebook")
        }
        warmUpAfterLaunch()
    }

    func touch() {
        dataVersion += 1
    }

    /// Deferred warm-ups that would otherwise stall a first tap.
    func warmUpAfterLaunch() {
        // Voice preferences live in settings but are read on every speak,
        // so hand them to the service once at launch.
        speech.rate = settings.speechRate
        speech.piperSpeaker = settings.piperSpeaker
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            AppleDictionaryInline.warmUp()
        }
    }

    /// UI-test-only: install the embedded walkthrough list.
    private func seedUITestList() {
        guard let rows = try? CSVImport.parse(SeedData.satRWVocabCSV) else { return }
        if !userStore.lists().contains(where: { $0.name == SeedData.satListName }) {
            CSVImport.importRows(rows, listName: SeedData.satListName, userStore: userStore)
        }
    }
}

/// Deterministic state for screenshot tests: fixed recall models, study log
/// counts matching the reference video, and a paused-free state.
enum UITestSeeder {
    @MainActor
    static func seed(userStore: UserStore, dictionary: DictionaryStore?, settings: AppSettings) {
        let calendar = Calendar.current
        let now = Date()
        userStore.withTransaction {
            seedContent(userStore: userStore, calendar: calendar, now: now)
        }
    }

    private static func seedContent(userStore: UserStore, calendar: Calendar, now: Date) {

        // Home stats: "You've learned 6 new words and reviewed 35 today."
        for i in 0..<6 {
            userStore.logStudy(word: "seed-new-\(i)", knew: true, wasNew: true, at: now)
        }
        for i in 0..<35 {
            userStore.logStudy(word: "seed-rev-\(i)", knew: true, wasNew: false, at: now)
        }

        // Word states shown in the reference recording.
        var some = WordState(word: "some")
        some.note = "特别义： certain， 如 some people = certain people"
        some.timesStudied = 2
        some.lastStudiedAt = now.addingTimeInterval(-3 * 3600)
        some.nextPlannedAt = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        some.memoryCircle = 2
        some.ebisuModel = EbisuModel()
        userStore.save(state: some)

        var indicative = WordState(word: "indicative")
        indicative.note = "adj. 表明……的"
        userStore.save(state: indicative)

        // A due review set with varied Ebisu halflives (hours), so predicted
        // recall spreads across the buckets for sort/filter screenshots.
        // All were last studied 96 hours ago.
        let recallWords: [(String, Double, Int)] = [
            ("adverse", 12, 2), ("breeze", 12, 1), ("conceive", 12, 1),
            ("concession", 12, 3), ("convey", 12, 2), ("defy", 12, 1),
            ("distinguished", 12, 2), ("flourish", 12, 1), ("formidable", 12, 1),
            ("induce", 48, 2), ("remedy", 48, 1), ("trophy", 120, 2),
            ("underscore", 120, 1), ("thrill", 480, 1), ("integral", 480, 2),
        ]
        for (word, halflifeHours, circle) in recallWords {
            var state = WordState(word: word)
            state.timesStudied = circle
            state.lastStudiedAt = now.addingTimeInterval(-4 * 86400)
            state.nextPlannedAt = calendar.date(byAdding: .day, value: -4, to: calendar.startOfDay(for: now))
            state.memoryCircle = circle
            state.ebisuModel = EbisuModel(halflifeHours: halflifeHours)
            userStore.save(state: state)
        }

        userStore.recordSearch(term: "wordage", at: now.addingTimeInterval(-23 * 60))
        userStore.recordSearch(term: "a", at: now.addingTimeInterval(-23 * 60 + 1))
    }
}
