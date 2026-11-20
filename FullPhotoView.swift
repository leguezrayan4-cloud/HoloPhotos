import Photos
import SwiftUI

struct FullPhotoView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(image == nil)

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
                    Button { showAlbumPicker = true } label: {
                        Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        library.duplicate([asset]) {}
                    } label: {
                        Label("Dupliquer", systemImage: "plus.square.on.square")
                    }
                    Button {
                        library.hide([asset]) { dismiss() }
                    } label: {
                        Label("Masquer", systemImage: "eye.slash")
                    }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        .confirmationDialog("Supprimer cette photo ?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                library.delete([asset]) { dismiss() }
            }
        } message: {
            Text("Elle ira dans « Supprimés récemment » pendant 30 jours.")
        }
        .onAppear(perform: load)
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        isFavorite = newValue
        library.setFavorite(asset, newValue)
    }

    private func load() {
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
