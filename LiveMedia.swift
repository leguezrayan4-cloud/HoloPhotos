import Photos
import SwiftUI
import UIKit
import VisionKit

// Live Photo : affichage, et lecture du mouvement quand on maintient le doigt
struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playTrigger: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto {
            view.livePhoto = livePhoto
        }
        if playTrigger != context.coordinator.lastTrigger {
            context.coordinator.lastTrigger = playTrigger
            view.startPlayback(with: .full)
        }
    }

    final class Coordinator {
        var lastTrigger = 0
    }
}

// Live Text : sélection et copie du texte présent dans une photo
struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .textSelection
        imageView.addInteraction(interaction)
        context.coordinator.interaction = interaction
        context.coordinator.analyze(image)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if imageView.image !== image {
            imageView.image = image
            context.coordinator.analyze(image)
        }
    }

    final class Coordinator {
        var interaction: ImageAnalysisInteraction?
        private var analyzing = false

        @MainActor
        func analyze(_ image: UIImage) {
            guard !analyzing else { return }
            analyzing = true
            Task { @MainActor in
                defer { self.analyzing = false }
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                if let analysis = try? await analyzer.analyze(image, configuration: configuration) {
                    self.interaction?.analysis = analysis
                }
            }
        }
    }
}
