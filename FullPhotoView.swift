import AVKit
import Photos
import SwiftUI

struct PhotoViewer: View {
    let assets: [PHAsset]
    @ObservedObject var library: PhotoLibrary
    @State private var currentIndex: Int
    @State private var favoriteIDs: Set<String> = []
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showInfo = false
    @State private var showAlbumPicker = false
    @State private var showDelete = false
    @Environment(\.dismiss) private var dismiss

    init(assets: [PHAsset], library: PhotoLibrary, startIndex: Int) {
        self.assets = assets
        self.library = library
        let safe = min(max(startIndex, 0), max(assets.count - 1, 0))
        _currentIndex = State(initialValue: safe)
    }

    private var currentAsset: PHAsset? {
        assets.indices.contains(currentIndex) ? assets[currentIndex] : nil
    }

    private var isFavorite: Bool {
        guard let id = currentAsset?.localIdentifier else { return false }
        return favoriteIDs.contains(id)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                    PhotoPage(asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("\(currentIndex + 1) sur \(assets.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button { prepareShare() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(currentAsset?.mediaType != .image)

                    Spacer()

                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }

                    Spacer()

                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                    }

                    Spacer()

                    Menu {
                        Button { copyCurrent() } label: {
                            Label("Copier", systemImage: "doc.on.doc")
                        }
                        .disabled(currentAsset?.mediaType != .image)

                        Button { duplicateCurrent() } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        .disabled(currentAsset?.mediaType != .image)

                        Button { showAlbumPicker = true } label: {
                            Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus")
                        }

                        Button { hideCurrent() } label: {
                            Label("Masquer", systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Spacer()

                    Button(role: .destructive) { showDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .onAppear {
            favoriteIDs = Set(assets.filter { $0.isFavorite }.map { $0.localIdentifier })
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showInfo) {
            if let asset = currentAsset {
                PhotoInfoView(asset: asset)
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            if let asset = currentAsset {
                AlbumPicker(library: library, assets: [asset]) {}
            }
        }
        .confirmationDialog("Supprimer cet élément ?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let asset = currentAsset {
                    library.delete([asset]) { dismiss() }
                }
            }
        } message: {
            Text("Il ira dans « Supprimés récemment » pendant 30 jours.")
        }
    }

    private func toggleFavorite() {
        guard let asset = currentAsset else { return }
        let newValue = !isFavorite
        if newValue {
            favoriteIDs.insert(asset.localIdentifier)
        } else {
            favoriteIDs.remove(asset.localIdentifier)
        }
        library.setFavorite(asset, newValue)
    }

    private func prepareShare() {
        guard let asset = currentAsset else { return }
        library.loadImages([asset]) { images in
            shareItems = images
            showShare = true
        }
    }

    private func copyCurrent() {
        guard let asset = currentAsset else { return }
        library.loadImages([asset]) { images in
            UIPasteboard.general.images = images
        }
    }

    private func duplicateCurrent() {
        guard let asset = currentAsset else { return }
        library.duplicate([asset]) {}
    }

    private func hideCurrent() {
        guard let asset = currentAsset else { return }
        library.hide([asset]) { dismiss() }
    }
}

// Une page = une photo ou une vidéo, avec zoom pour les photos
struct PhotoPage: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        Group {
            if asset.mediaType == .video {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                zoom = min(max(zoom * value, 1), 4)
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            zoom = 1
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    private func load() {
        if asset.mediaType == .video {
            guard player == nil else { return }
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard let item else { return }
                DispatchQueue.main.async {
                    player = AVPlayer(playerItem: item)
                }
            }
        } else {
            guard image == nil else { return }
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
