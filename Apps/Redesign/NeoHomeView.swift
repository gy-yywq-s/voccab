import SwiftUI
import VocabKit

/// Home — identical zoning to the classic app (greeting/stats, My Words,
/// word-list tiles, camera promo, bottom lookup bar), re-expressed in the
/// quiet editorial language: paper surface, serif masthead, ink + hairlines
/// instead of blobs and cards.
struct NeoHomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var showSearch = false
    @State private var showCamera = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                        greetingZone
                        myWordsZone
                        listsZone
                        promoZone
                        Color.clear.frame(height: 110)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                .background(Neo.paper)

                bottomBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .neoDestinations(env: env)
            .fullScreenCover(isPresented: $showSearch) {
                NeoSearchOverlay(env: env) { word, context in
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
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Text("Voccab")
                    .font(Neo.masthead)
                    .foregroundStyle(Neo.ink)
                    .accessibilityIdentifier("home.greeting")
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    path.append(Route.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(Neo.graphite)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.settings")
            }
            NeoHairline()
        }
        .padding(.top, 6)
    }

    private var greetingZone: some View {
        let counts = env.userStore.todayCounts()
        return VStack(alignment: .leading, spacing: 14) {
            Text(greetingWord)
                .font(Neo.serif(34, weight: .semibold))
                .foregroundStyle(Neo.ink)
            (statText(counts))
                .font(Neo.sans(16))
                .foregroundStyle(Neo.graphite)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
        .id(env.dataVersion)
    }

    private var greetingWord: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    private func statText(_ counts: (newWords: Int, reviewed: Int)) -> Text {
        if counts.newWords == 0 && counts.reviewed == 0 {
            return Text("Nothing studied yet today — pick a list below to begin.")
        }
        return Text("Today you've learned ")
            + Text("\(counts.newWords)").font(Neo.sans(16, weight: .semibold)).foregroundColor(Neo.ink)
            + Text(" new words and reviewed ")
            + Text("\(counts.reviewed)").font(Neo.sans(16, weight: .semibold)).foregroundColor(Neo.ink)
            + Text(". Keep going.")
    }

    private var myWordsZone: some View {
        let myWords = env.userStore.myWordsList()
        return VStack(alignment: .leading, spacing: 0) {
            NeoSectionHeader(title: "My Words")
                .padding(.top, 34)
                .padding(.bottom, 10)
            Button {
                path.append(Route.wordList(myWords))
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("My Words")
                            .font(Neo.serif(22, weight: .semibold))
                            .foregroundStyle(Neo.ink)
                        Text(myWords.wordCount == 0
                             ? "Add new words now"
                             : "\(myWords.wordCount) saved word\(myWords.wordCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(Neo.faint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Neo.faint)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(NeoPressStyle())
            .accessibilityIdentifier("home.myWords")
            NeoHairline()
        }
    }

    private var listsZone: some View {
        let lists = env.userStore.lists(includeBuiltin: false)
        return VStack(alignment: .leading, spacing: 0) {
            NeoSectionHeader(title: "Word Lists")
                .padding(.top, 30)
                .padding(.bottom, 4)
            if lists.isEmpty {
                Text("Import a CSV in Settings to create your first list.")
                    .font(.subheadline)
                    .foregroundStyle(Neo.faint)
                    .padding(.vertical, 14)
            }
            ForEach(lists) { list in
                Button {
                    path.append(Route.wordList(list))
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(list.name)
                            .font(Neo.serif(20))
                            .foregroundStyle(Neo.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(list.wordCount)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Neo.graphite)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Neo.faint)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.list.\(list.name)")
                .overlay(alignment: .bottom) {
                    if list.id != lists.last?.id {
                        Rectangle().fill(Neo.hairline).frame(height: 0.5)
                    }
                }
            }
            NeoHairline()
        }
    }

    private var promoZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            NeoSectionHeader(title: "Snap Words")
                .padding(.top, 30)
            Text("Photograph text and tap any word to look it up — the camera button below starts a capture.")
                .font(Neo.sans(15))
                .foregroundStyle(Neo.graphite)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                PromoFigure()
                    .frame(maxWidth: 250)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            NeoHairline()
            HStack(spacing: 12) {
                Button {
                    showSearch = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(Neo.faint)
                        Text("Lookup words or sentences")
                            .font(Neo.sans(15))
                            .foregroundStyle(Neo.faint)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Neo.field)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Neo.hairline, lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.search")

                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Neo.blue)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Neo.paleBlue)
                        )
                }
                .buttonStyle(NeoPressStyle())
                .accessibilityIdentifier("home.camera")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Neo.paper.opacity(0.97))
        }
    }
}

/// The camera promo figure: bundled screenshot framed by a hairline.
struct PromoFigure: View {
    var body: some View {
        Group {
            if let image = UIImage(named: "PromoCamera") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(height: 320)
                    .overlay {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 40))
                            .foregroundStyle(Neo.faint)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Neo.hairline, lineWidth: 0.8)
        )
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
