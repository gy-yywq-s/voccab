import Combine
import SwiftUI

/// The home-page camera promo: public-domain artworks with the in-photo
/// word-lookup effect recreated as a live overlay. Auto-advances, swipes
/// left/right, and marks the position with small dots at the bottom of the
/// image.
struct PromoSlide: Identifiable {
    let id: Int
    let imageName: String
    let word: String
    let phonetic: String
    let definition: String
}

struct PromoCarousel: View {
    static let slides: [PromoSlide] = [
        PromoSlide(id: 0, imageName: "Promo1", word: "peruse", phonetic: "pə'ruːz", definition: "vt. 熟读, 精读, 阅读"),
        PromoSlide(id: 1, imageName: "Promo2", word: "luminous", phonetic: "'luːminəs", definition: "a. 发光的, 明亮的"),
        PromoSlide(id: 2, imageName: "Promo3", word: "vernal", phonetic: "'vəːnl", definition: "a. 春天的, 和煦的"),
        PromoSlide(id: 3, imageName: "Promo4", word: "sublime", phonetic: "sə'blaim", definition: "a. 高尚的, 壮观的"),
    ]

    /// Corner radius differs slightly per frontend; everything else is shared.
    var cornerRadius: CGFloat = 16

    @State private var index = 0
    private let ticker = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $index) {
            ForEach(Self.slides) { slide in
                slideView(slide)
                    .tag(slide.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        )
        .overlay(alignment: .bottom) {
            dots
                .padding(.bottom, 10)
        }
        .onReceive(ticker) { _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                index = (index + 1) % Self.slides.count
            }
        }
        .accessibilityIdentifier("home.promoCarousel")
    }

    private func slideView(_ slide: PromoSlide) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let image = UIImage(named: slide.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                }
                lookupCard(slide)
                    .padding(.leading, 14)
                    .padding(.bottom, 30)
            }
        }
    }

    /// The word-lookup popup, recreated over the artwork.
    private func lookupCard(_ slide: PromoSlide) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(slide.word)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                Spacer(minLength: 14)
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
            }
            HStack(spacing: 5) {
                Text("/\(slide.phonetic)/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
            }
            Text(slide.definition)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
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
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption2)
                Text("Save to My Words")
                    .font(.caption)
            }
            .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.62))
        )
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Self.slides) { slide in
                Circle()
                    .fill(slide.id == index ? .white : .white.opacity(0.45))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.25)))
    }
}
