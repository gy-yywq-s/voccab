import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Photo-based word lookup, matching the original app's flow:
/// pick from the album or take a photo, then the photo is shown with every
/// recognized word overlaid as a tappable token at its detected position.
/// Tapped words collect into a chip row (dictionary-known words highlighted,
/// unknown ones dimmed); tapping a chip opens the word. A plain recognized-word
/// list sits below as a fallback for small or missed text.
struct CameraLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var selection: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var tokens: [OCRToken] = []
    @State private var words: [String] = []
    @State private var knownWords: Set<String> = []
    @State private var selectedWords: [String] = []
    @State private var busy = false
    @State private var showCamera = false
    let onWordPicked: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if image == nil, !busy {
                    landing
                } else {
                    results
                }
            }
            .navigationTitle("Snap Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selection) {
                guard let selection else { return }
                Task { await load(selection) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { captured in
                    showCamera = false
                    guard let captured else { return }
                    Task { await recognize(captured) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: First screen — the "Pick from album / Take a photo" menu

    private var landing: some View {
        VStack(spacing: 16) {
            Spacer()
            ContentUnavailableView(
                "Snap or pick a photo with text",
                systemImage: "camera.viewfinder",
                description: Text("Recognized words appear right on the photo — tap one to look it up.")
            )
            .frame(maxHeight: 260)
            Spacer()
            sourceButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    private var sourceButtons: some View {
        VStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take a Photo", systemImage: "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Pick from Album", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
            }
        }
    }

    // MARK: Results — photo with token overlay, chips, fallback list

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image {
                    annotatedPhoto(image)
                        .padding(.horizontal, 16)
                }
                if busy {
                    ProgressView("Recognizing words…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    if !selectedWords.isEmpty {
                        selectedChips
                    }
                    if words.isEmpty {
                        Text("No English words found in this photo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        fallbackList
                    }
                }
                retakeRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .padding(.top, 12)
        }
    }

    /// The photo, aspect-fit, with one tappable capsule per detected word.
    /// `.scaledToFit()` makes the Image view's own bounds exactly the fitted
    /// image rect, so the overlay GeometryReader sees the displayed image size
    /// directly and normalized boxes map with a plain multiply (no letterbox
    /// offsets to subtract).
    private func annotatedPhoto(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                GeometryReader { geo in
                    ForEach(tokens) { token in
                        tokenOverlay(token, in: geo.size)
                    }
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func tokenOverlay(_ token: OCRToken, in size: CGSize) -> some View {
        // token.box is normalized with a TOP-left origin (already flipped from
        // Vision's bottom-left origin at recognition time).
        let rect = CGRect(
            x: token.box.minX * size.width,
            y: token.box.minY * size.height,
            width: token.box.width * size.width,
            height: token.box.height * size.height
        )
        // Inflate tiny boxes so every word stays comfortably tappable.
        let width = max(rect.width + 6, 26)
        let height = max(rect.height + 4, 22)
        let selected = selectedWords.contains(token.text)
        return Button {
            toggle(token.text)
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(selected ? Color.blue.opacity(0.30) : Color.yellow.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            selected ? Color.blue.opacity(0.85) : Color.yellow.opacity(0.6),
                            lineWidth: selected ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(Text(token.text))
    }

    /// Words tapped on the photo, collected as removable chips. Tapping a chip
    /// looks the word up; words the dictionary knows get priority styling and
    /// unknown ones are dimmed.
    private var selectedChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedWords, id: \.self) { word in
                        chip(for: word)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func chip(for word: String) -> some View {
        let known = knownWords.contains(word)
        return HStack(spacing: 6) {
            Button {
                onWordPicked(word)
            } label: {
                HStack(spacing: 5) {
                    if known {
                        Image(systemName: "book.fill")
                            .font(.caption2)
                    }
                    Text(word)
                        .font(.subheadline.weight(known ? .semibold : .regular))
                }
            }
            .buttonStyle(.plain)
            Button {
                selectedWords.removeAll { $0 == word }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(known ? Color.blue.opacity(0.15) : Color(uiColor: .secondarySystemFill))
        )
        .foregroundStyle(known ? Color.blue : Color.secondary)
        .opacity(known ? 1 : 0.6)
    }

    /// Plain list of everything recognized — catches small or missed text
    /// whose overlay token is too tiny to hit.
    private var fallbackList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All recognized words")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            FlowLayout(spacing: 8) {
                ForEach(words, id: \.self) { word in
                    Button {
                        onWordPicked(word)
                    } label: {
                        Text(word)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                            .foregroundStyle(knownWords.contains(word) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .opacity(knownWords.contains(word) ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var retakeRow: some View {
        HStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Retake", systemImage: "camera")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Another Photo", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
            }
        }
    }

    private func toggle(_ word: String) {
        if let index = selectedWords.firstIndex(of: word) {
            selectedWords.remove(at: index)
        } else {
            selectedWords.append(word)
        }
    }

    // MARK: OCR

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        await recognize(uiImage)
    }

    private func recognize(_ uiImage: UIImage) async {
        busy = true
        image = uiImage
        tokens = []
        words = []
        selectedWords = []
        defer { busy = false }
        guard let cgImage = uiImage.cgImage else { return }

        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        // Vision work off the main actor; the handler run is CPU-heavy.
        let recognized = await Task.detached(priority: .userInitiated) {
            Self.runOCR(cgImage: cgImage, orientation: orientation)
        }.value

        tokens = recognized
        var seen = Set<String>()
        words = recognized.map(\.text).filter { seen.insert($0).inserted }
        let found = env.dictionary?.lookup(words: words) ?? [:]
        knownWords = Set(found.keys)
    }

    /// Runs accurate English OCR and splits each observation line into
    /// per-word tokens with normalized top-left-origin boxes.
    private static func runOCR(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [OCRToken] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try? handler.perform([request])

        var tokens: [OCRToken] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            let lineBox = observation.boundingBox // normalized, bottom-left origin
            for range in wordRanges(in: line) {
                let raw = String(line[range])
                let cleaned = raw.lowercased()
                    .trimmingCharacters(in: CharacterSet.letters.inverted)
                guard cleaned.count >= 2,
                      cleaned.rangeOfCharacter(from: .letters) != nil else { continue }

                // Preferred: Vision's own sub-range box. Fallback: slice the
                // line's box proportionally by character position, since the
                // line is roughly monospaced enough for a tap target.
                let wordBox: CGRect
                if let sub = try? candidate.boundingBox(for: range)?.boundingBox {
                    wordBox = sub
                } else {
                    let startFraction = CGFloat(line.distance(from: line.startIndex, to: range.lowerBound))
                        / CGFloat(max(line.count, 1))
                    let endFraction = CGFloat(line.distance(from: line.startIndex, to: range.upperBound))
                        / CGFloat(max(line.count, 1))
                    wordBox = CGRect(
                        x: lineBox.minX + startFraction * lineBox.width,
                        y: lineBox.minY,
                        width: (endFraction - startFraction) * lineBox.width,
                        height: lineBox.height
                    )
                }
                // Flip Vision's bottom-left origin to SwiftUI's top-left.
                let flipped = CGRect(
                    x: wordBox.minX,
                    y: 1 - wordBox.maxY,
                    width: wordBox.width,
                    height: wordBox.height
                )
                tokens.append(OCRToken(text: cleaned, box: flipped))
            }
        }
        return tokens
    }

    /// Ranges of letter runs (keeping in-word apostrophes and hyphens).
    private static func wordRanges(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = line.startIndex
        func isWordChar(_ c: Character) -> Bool {
            c.isLetter || c == "'" || c == "\u{2019}" || c == "-"
        }
        while index < line.endIndex {
            if isWordChar(line[index]) {
                if start == nil { start = index }
            } else if let s = start {
                ranges.append(s..<index)
                start = nil
            }
            index = line.index(after: index)
        }
        if let s = start {
            ranges.append(s..<line.endIndex)
        }
        return ranges
    }
}

/// A recognized word with its normalized (top-left origin) box on the image.
private struct OCRToken: Identifiable {
    let id = UUID()
    let text: String
    let box: CGRect
}

/// Minimal system camera sheet; hands back the captured image (or nil).
private struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
