import SwiftUI
import VocabKit

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var showSearch = false
    @State private var showCamera = false
    @State private var searchInitialQuery = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        BlobBackground()
                        content
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .scrollIndicators(.hidden)

                bottomBar
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("home.settings")
                }
            }
            .classicDestinations(env: env)
            .fullScreenCover(isPresented: $showSearch) {
                SearchOverlay(env: env, initialQuery: searchInitialQuery) { word, context in
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
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            greeting
                .padding(.top, 100)
            statsText
                .padding(.top, 44)
            myWordsCard
                .padding(.top, 18)
            listTiles
                .padding(.top, 26)
            promo
                .padding(.top, 36)
            Color.clear.frame(height: 120)
        }
        .padding(.horizontal, 20)
        .id(env.dataVersion)
    }

    private var greetingWord: String {
        let day = Calendar.current.component(.day, from: Date())
        let pool = ["Hello,", "Hey there,", "Welcome back,", "Onward,"]
        return pool[day % pool.count]
    }

    private var greeting: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(greetingWord)
                .font(.system(size: 46, weight: .bold, design: .rounded))
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    ClassicTheme.dynamic(
                        light: UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1),
                        dark: UIColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1)
                    )
                )
        }
        .accessibilityIdentifier("home.greeting")
    }

    private var statsText: some View {
        let counts = env.userStore.todayCounts()
        return Text(Formatting.greetingMessage(newWords: counts.newWords, reviewed: counts.reviewed))
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var myWordsCard: some View {
        let myWords = env.userStore.myWordsList()
        return Button {
            path.append(Route.wordList(myWords))
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Add New Words Now!")
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    Text("My Words")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)

                Divider()
                    .frame(height: 64)

                VStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                    Text("List")
                        .font(.caption)
                }
                .foregroundStyle(.primary)
                .frame(width: 92)
            }
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.72))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.myWords")
    }

    private var listTiles: some View {
        let lists = env.userStore.lists(includeBuiltin: false)
        let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 16, alignment: .topLeading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(lists) { list in
                Button {
                    path.append(Route.wordList(list))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)
                        Text(list.name)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(ClassicTheme.tileTitle)
                        Text("\(list.wordCount) words")
                            .font(.subheadline)
                            .foregroundStyle(ClassicTheme.tileSubtitle)
                    }
                    .padding(14)
                    .frame(width: 122, height: 122, alignment: .bottomLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(ClassicTheme.tileGreen)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.list.\(list.name)")
            }
        }
    }

    private var promo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snap up new words with your camera! Just tap the camera button to start.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 8)
                PromoCarousel(cornerRadius: 24) { word in
                    path.append(Route.wordDetail(word: word, context: []))
                }
                .frame(maxWidth: 320)
                CurvedArrow()
                    .stroke(
                        ClassicTheme.dynamic(
                            light: UIColor(red: 0.62, green: 0.73, blue: 0.88, alpha: 1),
                            dark: UIColor(red: 0.55, green: 0.66, blue: 0.82, alpha: 1)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 84, height: 170)
                    .padding(.bottom, -18)
                Spacer(minLength: 0)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            // Two siblings inside one capsule: the field opens search, the
            // clipboard icon pastes and searches in one tap.
            HStack {
                Button {
                    searchInitialQuery = ""
                    showSearch = true
                } label: {
                    HStack {
                        Text("Lookup words or sentences")
                            .foregroundStyle(Color(uiColor: .placeholderText))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.search")

                Button {
                    searchInitialQuery = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    showSearch = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.tint)
                        .padding(8)
                        .background(Circle().fill(ClassicTheme.wordChipBackground))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.paste")
            }
            .font(.body)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .frame(height: 52)
            .background(
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
            )

            Button {
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(ClassicTheme.wordChipBackground))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.camera")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

/// The organic green shape behind the home header.
struct BlobBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                BlobShape(seedOffset: 0.06)
                    .fill(ClassicTheme.blobSecondary)
                    .frame(width: w * 1.24, height: 620)
                    .offset(x: -w * 0.12, y: -60)
                BlobShape(seedOffset: 0)
                    .fill(ClassicTheme.blobPrimary)
                    .frame(width: w * 1.18, height: 590)
                    .offset(x: -w * 0.10, y: -80)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Hand-tuned closed bezier resembling the original blob.
struct BlobShape: Shape {
    var seedOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let s = seedOffset
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w * (0.94 + s), y: 0))
        path.addCurve(
            to: CGPoint(x: w * (0.78 + s), y: h * 0.62),
            control1: CGPoint(x: w * (0.99 + s), y: h * 0.26),
            control2: CGPoint(x: w * (0.94 + s), y: h * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.30, y: h * (0.96 - s)),
            control1: CGPoint(x: w * (0.62 + s), y: h * 0.78),
            control2: CGPoint(x: w * 0.48, y: h * (0.96 - s))
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.72),
            control1: CGPoint(x: w * 0.14, y: h * (0.96 - s)),
            control2: CGPoint(x: 0, y: h * 0.88)
        )
        path.closeSubpath()
        return path
    }
}

/// The blue arrow pointing from the promo image to the camera button.
struct CurvedArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 6, y: rect.minY + 20)
        let end = CGPoint(x: rect.maxX - 24, y: rect.maxY - 16)
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: rect.maxX - 6, y: rect.minY + 8),
            control2: CGPoint(x: rect.maxX - 2, y: rect.midY + 20)
        )
        // arrow head
        path.move(to: CGPoint(x: end.x - 16, y: end.y - 12))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x + 12, y: end.y - 18))
        return path
    }
}
