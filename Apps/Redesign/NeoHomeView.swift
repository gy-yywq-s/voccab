import SwiftUI
import VocabKit

/// Home — identical zoning to the classic app (greeting/stats, word lists,
/// All Words aggregate, camera promo, bottom lookup bar) in the Passage
/// language: white page, centered masthead over a hairline, bold sans
/// section titles, plain rows, pale-blue actions.
struct NeoHomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var showSearch = false
    @State private var showCamera = false
    @State private var searchInitialQuery = ""
    @State private var showNewListPrompt = false
    @State private var newListName = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                        greetingZone
                        listsZone
                        allWordsZone
                        promoZone
                        Color.clear.frame(height: 110)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .background(Color(uiColor: .systemBackground))

                bottomBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("New List", isPresented: $showNewListPrompt) {
                TextField("List name", text: $newListName)
                Button("Create") {
                    let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        env.userStore.createList(name: trimmed)
                        env.touch()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .neoDestinations(env: env)
            .fullScreenCover(isPresented: $showSearch) {
                NeoSearchOverlay(env: env, initialQuery: searchInitialQuery) { word, context in
                    path.append(Route.wordDetail(word: word, context: context))
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraLookupView { word in
                    showCamera = false
                    path.append(Route.wordDetail(word: word, context: []))
                }
            }
        }
        .tint(Neo.blue)
    }

    // MARK: Zones

    private var masthead: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Text("Voccab")
                    .font(Neo.masthead)
                    .accessibilityIdentifier("home.greeting")
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    path.append(Route.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.settings")
            }
            NeoHairline()
                .padding(.horizontal, -20)
        }
        .padding(.top, 6)
    }

    private var greetingZone: some View {
        let counts = env.userStore.todayCounts()
        return VStack(alignment: .leading, spacing: 7) {
            // A real heading: large serif, editorial weight, varied line.
            Text(greetingLine)
                .font(.system(size: 34, weight: .semibold, design: .serif))
            statText(counts)
                .font(Neo.bodyFont)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
        .id(env.dataVersion)
    }

    /// Varied by time of day AND by day, so it doesn't read like a fixed
    /// system string.
    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let day = Calendar.current.component(.day, from: Date())
        let pool: [String]
        switch hour {
        case 5..<12:
            pool = ["Good morning", "Morning, reader", "First light", "Early pages"]
        case 12..<18:
            pool = ["Good afternoon", "Afternoon, reader", "Midday pages", "Keep at it"]
        default:
            pool = ["Good evening", "Evening, reader", "Night pages", "Quiet hours"]
        }
        return pool[day % pool.count]
    }

    private func statText(_ counts: (newWords: Int, reviewed: Int)) -> Text {
        if counts.newWords == 0 && counts.reviewed == 0 {
            return Text("A blank page so far today — pick a list and make a dent.")
        }
        return Text("\(counts.newWords) new · \(counts.reviewed) revisited today — nice pace.")
    }

    /// Word lists — the primary zone: user lists in their own order, a
    /// new-list action, and an always-visible import row.
    private var listsZone: some View {
        let lists = env.userStore.lists()
        return VStack(alignment: .leading, spacing: 0) {
            NeoSectionHeader(title: "Word lists") {
                Button {
                    newListName = ""
                    showNewListPrompt = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New List")
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Neo.blue)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.newList")
            }
            .padding(.top, 30)
            if lists.isEmpty {
                Text("No word lists yet. Create one or import your own vocabulary.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            }
            VStack(spacing: 0) {
                ForEach(lists) { list in
                    Button {
                        path.append(Route.wordList(list))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(Neo.rowTitle)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(list.wordCount) words")
                                    .font(Neo.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NeoPressStyle())
                    .accessibilityIdentifier("home.list.\(list.name)")
                    NeoHairline()
                }
            }
            .padding(.top, 4)
            Button {
                path.append(Route.importWords)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                    Text("Import Words")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(Neo.blue)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.import")
        }
        .padding(.top, 2)
    }

    /// All Words — the aggregate of every list, replacing the old builtin
    /// "My Words" collection.
    private var allWordsZone: some View {
        let count = env.userStore.allWordsCount()
        return VStack(alignment: .leading, spacing: 0) {
            NeoHairline()
            NeoSectionHeader(title: "All Words")
                .padding(.top, 24)
            Button {
                path.append(Route.wordList(.aggregate))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Every word across your lists")
                            .font(Neo.caption)
                            .foregroundStyle(.secondary)
                        Text(count == 0 ? "None yet" : "\(count) words")
                            .font(Neo.rowTitle)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.myWords")
        }
        .padding(.top, 18)
    }

    private var promoZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            NeoHairline()
            NeoSectionHeader(title: "Snap words")
                .padding(.top, 24)
            Text("Photograph text and tap any word to look it up. The camera button below starts a capture.")
                .font(Neo.bodyFont)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            PromoCarousel(cornerRadius: 10) { word in
                path.append(Route.wordDetail(word: word, context: []))
            }
            .padding(.top, 6)
        }
        .padding(.top, 18)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                searchInitialQuery = ""
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Lookup words or sentences")
                        .foregroundStyle(Color(uiColor: .placeholderText))
                    Spacer()
                }
                .font(.body)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(
                    Capsule().fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                )
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.search")

            Button {
                searchInitialQuery = UIPasteboard.general.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                showSearch = true
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Neo.blue)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Neo.paleBlue))
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.paste")

            Button {
                showCamera = true
            } label: {
                Image(systemName: "camera")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Neo.blue)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Neo.paleBlue))
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.camera")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }
}

extension View {
    @MainActor
    func neoDestinations(env: AppEnvironment) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .wordList(let list):
                NeoWordListView(model: WordListModel(list: list, env: env))
            case .wordDetail(let word, let context):
                NeoWordDetailPager(word: word, context: context)
            case .settings:
                NeoSettingsView()
            case .importWords:
                NeoImportWordsView()
            }
        }
    }
}
