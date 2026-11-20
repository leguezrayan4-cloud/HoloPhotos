import AVKit
import Photos
import SwiftUI

struct FullPhotoView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isFavorite: Bool
    @State private var showShare = false
    @State private var showInfo = false
    @State private var showAlbumPicker = false
    @State private var showDelete = false

    init(asset: PHAsset, library: PhotoLibrary) {
        self.asset = asset
        self.library = library
        _isFavorite = State(initialValue: asset.isFavorite)
    }

    private var isVideo: Bool {
        asset.mediaType == .video
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.image = image
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc")
                    }
                    .disabled(image == nil || isVideo)

                    Button {
                        library.duplicate([asset]) {}
                    } label: {
                        Label("Dupliquer", systemImage: "plus.square.on.square")
                    }
                    .disabled(isVideo)

                    Button {
                        library.hide([asset]) { dismiss() }
                    } label: {
                        Label("Masquer", systemImage: "eye.slash")
                    }

                    Button {
                        showAlbumPicker = true
                    } label: {
                        Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(image == nil || isVideo)

                Spacer()

                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }

                Spacer()

                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                }

                Spacer()

                Button(role: .destructive) { showDelete = true } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .sheet(isPresented: $showShare) {
            if let image {
                ShareSheet(items: [image])
            }
        }
        .sheet(isPresented: $showInfo) {
            PhotoInfoView(asset: asset)
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPicker(library: library, assets: [asset]) {}
        }
        .confirmationDialog("Supprimer cet élément ?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                library.delete([asset]) { dismiss() }
            }
        } message: {
            Text("Il ira dans « Supprimés récemment » pendant 30 jours.")
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if isVideo {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ProgressView()
        }
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        isFavorite = newValue
        library.setFavorite(asset, newValue)
    }

    private func load() {
        if isVideo {
            loadVideo()
        } else {
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    image = result
                }
            }
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                player = AVPlayer(playerItem: item)
            }
        }
    }
}

struct PhotoInfoView: View {
    let asset: PHAsset

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Date") {
                    Text(asset.creationDate?.formatted(date: .long, time: .shortened) ?? "Inconnue")
                }
                LabeledContent("Dimensions") {
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                }
                if asset.mediaType == .video {
                    LabeledContent("Durée") {
                        Text(String(format: "%.0f s", asset.duration))
                    }
                }
                if let location = asset.location {
                    LabeledContent("Position") {
                        Text(String(format: "%.4f, %.4f",
                                    location.coordinate.latitude,
                                    location.coordinate.longitude))
                    }
                }
            }
            .navigationTitle("Infos")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
