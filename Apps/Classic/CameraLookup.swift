import PhotosUI
import SwiftUI
import Vision

/// Photo-based word lookup: pick a photo, OCR the text, tap a recognized word.
struct CameraLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var words: [String] = []
    @State private var busy = false
    let onWordPicked: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if busy {
                    ProgressView("Recognizing words…")
                } else if words.isEmpty {
                    ContentUnavailableView(
                        "Pick a photo with text",
                        systemImage: "camera.viewfinder",
                        description: Text("Recognized English words will appear here — tap one to look it up.")
                    )
                } else {
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(words, id: \.self) { word in
                                Button {
                                    onWordPicked(word)
                                } label: {
                                    Text(word)
                                        .font(.body)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(ClassicTheme.wordChipBackground))
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Spacer()
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(ClassicTheme.continueButtonBackground))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.top, 16)
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
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return }
        image = uiImage

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        var seen = Set<String>()
        words = text
            .components(separatedBy: CharacterSet.letters.inverted)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .letters) != nil }
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
    }
}
