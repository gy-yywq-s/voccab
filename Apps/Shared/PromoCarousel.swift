import Combine
import SwiftUI
import VocabKit

/// The home-page promo: public-domain poster art that genuinely contains
/// the highlighted word (OCR-verified at build time), with the photo
/// word-lookup effect recreated live: a highlight box on the word in the
/// artwork plus a lookup card fed by the real dictionary. Auto-advances
/// every 10 seconds, swipes left/right, and tapping a slide opens the
/// word's detail page.
struct PromoCarousel: View {
    /// Corner radius differs slightly per frontend; everything else is shared.
    var cornerRadius: CGFloat = 16
    var onWordTap: ((String) -> Void)? = nil

    @EnvironmentObject private var env: AppEnvironment
    @State private var index = 0
    private let ticker = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var slides: [PromoSlideData] { PromoData.slides }

    var body: some View {
        TabView(selection: $index) {
            ForEach(slides) { slide in
                Group {
                    // Only the visible slide and its neighbors keep their
                    // image decoded; the rest stay as flat placeholders.
                    if isNear(slide.id) {
                        PromoSlideView(
                            slide: slide,
                            dictWord: env.dictionary?.lookup(slide.word)
                        )
                    } else {
                        Rectangle().fill(Color(uiColor: .secondarySystemFill))
                    }
                }
                .tag(slide.id)
                .contentShape(Rectangle())
                .onTapGesture { onWordTap?(slide.word) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        )
        .onReceive(ticker) { _ in
            guard !slides.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                index = (index + 1) % slides.count
            }
        }
        .accessibilityIdentifier("home.promoCarousel")
    }

    private func isNear(_ id: Int) -> Bool {
        let count = slides.count
        guard count > 0 else { return false }
        let distance = abs(id - index)
        return distance <= 1 || distance == count - 1
    }
}

private struct PromoSlideView: View {
    let slide: PromoSlideData
    let dictWord: DictWord?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            // The bundled image is exactly 3:4 like the frame, so the
            // normalized OCR box maps straight onto view coordinates.
            let box = CGRect(
                x: slide.x * width, y: slide.y * height,
                width: slide.width * width, height: slide.height * height
            )
            ZStack(alignment: .topLeading) {
                if let image = UIImage(named: slide.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    Rectangle().fill(Color(uiColor: .secondarySystemFill))
                }

                // Highlight box around the word in the artwork.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.95), lineWidth: 1.6)
                    )
                    .frame(width: box.width + 12, height: box.height + 10)
                    .position(x: box.midX, y: box.midY)
                    .shadow(color: .black.opacity(0.35), radius: 4)

                lookupCard
                    .padding(12)
                    .frame(
                        maxWidth: .infinity, maxHeight: .infinity,
                        // Keep the card away from the highlighted word.
                        alignment: box.midY < height / 2 ? .bottomLeading : .topLeading
                    )
            }
        }
    }

    private var lookupCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(dictWord?.word ?? slide.word)
                    .font(.system(size: 21, weight: .bold, design: .serif))
                Spacer(minLength: 14)
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
            }
            if let phonetic = dictWord?.phonetic, !phonetic.isEmpty {
                HStack(spacing: 5) {
                    Text("/\(phonetic)/")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
                }
            }
            if let line = dictWord?.translationLines.first {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
            }
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 0.5)
                .padding(.vertical, 3)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                Text("Word details")
                    .font(.caption)
            }
            .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.62))
        )
    }
}
