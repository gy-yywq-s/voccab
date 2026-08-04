import SwiftUI
import VocabKit

// Placeholder scaffold for the redesigned frontend. The full redesigned GUI
// (same page structure, new visual language) replaces this in the redesign
// milestone.
struct NeoHomeView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Voccab")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                Text("Redesigned frontend — under construction")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }
}
