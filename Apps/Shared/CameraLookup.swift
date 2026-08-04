import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Photo-based word lookup: take a photo or pick one, OCR the text, tap a
/// recognized word.
struct CameraLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var words: [String] = []
    @State private var busy = false
    @State private var showCamera = false
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
                        "Snap or pick a photo with text",
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
                                        .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                    }
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

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        await recognize(uiImage)
    }

    private func recognize(_ uiImage: UIImage) async {
        busy = true
        defer { busy = false }
        guard let cgImage = uiImage.cgImage else { return }
        image = uiImage

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .init(uiImage.imageOrientation))
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
