import Photos
import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibrary()
    @State private var path: [PHAsset] = []
    @State private var isSelecting = false
    @State private var selected = Set<String>()
    @State private var showAlbumPicker = false
    @State private var showDeleteConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    private var selectedAssets: [PHAsset] {
        library.assets.filter { selected.contains($0.localIdentifier) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.authorized {
                    grid
                } else {
                    accessRequest
                }
            }
            .navigationTitle(isSelecting ? "\(selected.count) sélectionnée(s)" : "Photos")
            .toolbar {
                if library.authorized {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "OK" : "Sélectionner") {
                            if isSelecting {
                                finishSelection()
                            } else {
                                isSelecting = true
                            }
                        }
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { copySelected() } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button { duplicateSelected() } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        Button { hideSelected() } label: {
                            Image(systemName: "eye.slash")
                        }
                        Button { showAlbumPicker = true } label: {
                            Image(systemName: "rectangle.stack.badge.plus")
                        }
                        Spacer()
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .navigationDestination(for: PHAsset.self) { asset in
                FullPhotoView(asset: asset, library: library)
            }
        }
        .onAppear { library.checkAccess() }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPicker(library: library, assets: selectedAssets) {
                finishSelection()
            }
        }
        .confirmationDialog(
            "Supprimer \(selected.count) photo(s) ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                library.delete(selectedAssets) { finishSelection() }
            }
        } message: {
            Text("Elles iront dans « Supprimés récemment » pendant 30 jours.")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    ThumbnailView(
                        asset: asset,
                        isSelecting: isSelecting,
                        isSelected: selected.contains(asset.localIdentifier)
                    )
                    .onTapGesture {
                        if isSelecting {
                            toggle(asset)
                        } else {
                            path.append(asset)
                        }
                    }
                }
            }
        }
    }

    private var accessRequest: some View {
        VStack(spacing: 16) {
            Text("HoloPhotos a besoin d'accéder à tes photos.")
                .multilineTextAlignment(.center)
            Button("Autoriser l'accès") {
                library.requestAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    private func finishSelection() {
        selected.removeAll()
        isSelecting = false
    }

    private func copySelected() {
        library.loadImages(selectedAssets) { images in
            UIPasteboard.general.images = images
        }
    }

    private func duplicateSelected() {
        library.duplicate(selectedAssets) { finishSelection() }
    }

    private func hideSelected() {
        library.hide(selectedAssets) { finishSelection() }
    }
}

struct AlbumPicker: View {
    @ObservedObject var library: PhotoLibrary
    let assets: [PHAsset]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showNewAlbum = true
                } label: {
                    Label("Nouvel album", systemImage: "plus")
                }

                ForEach(library.albums, id: \.localIdentifier) { album in
                    Button(album.localizedTitle ?? "Album") {
                        library.add(assets, to: album) {
                            dismiss()
                            onDone()
                        }
                    }
                }
            }
            .navigationTitle("Ajouter à un album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .alert("Nouvel album", isPresented: $showNewAlbum) {
                TextField("Nom de l'album", text: $newAlbumName)
                Button("Créer") {
                    library.createAlbum(named: newAlbumName, adding: assets) {
                        dismiss()
                        onDone()
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}
