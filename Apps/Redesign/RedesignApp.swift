import SwiftUI
import VocabKit

@main
struct RedesignApp: App {
    @StateObject private var env = AppEnvironment()

    init() {
        if AppEnvironment.isUITest {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            NeoHomeView()
                .environmentObject(env)
                .preferredColorScheme(
                    ProcessInfo.processInfo.arguments.contains("-uitest-dark") ? .dark : nil
                )
        }
    }
}
