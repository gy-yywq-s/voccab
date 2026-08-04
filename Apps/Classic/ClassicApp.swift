import SwiftUI
import VocabKit

@main
struct ClassicApp: App {
    @StateObject private var env = AppEnvironment()

    init() {
        if AppEnvironment.isUITest {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(env)
                .preferredColorScheme(
                    ProcessInfo.processInfo.arguments.contains("-uitest-dark") ? .dark : nil
                )
        }
    }
}

/// Navigation destinations shared across the app.
enum Route: Hashable {
    case wordList(WordList)
    case wordDetail(word: String, context: [String])
    case settings
    case importWords
}

extension View {
    @MainActor
    func classicDestinations(env: AppEnvironment) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .wordList(let list):
                WordListView(model: WordListModel(list: list, env: env))
            case .wordDetail(let word, let context):
                WordDetailPager(word: word, context: context)
            case .settings:
                SettingsView()
            case .importWords:
                ImportWordsView()
            }
        }
    }
}
