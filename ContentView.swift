import Photos
import SwiftUI

struct ViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @AppStorage("columns") private var columns = 4
    @State private var pinchStart: Int?
    @State private var viewer: ViewerItem?
    @State private var isSelecting = false
    @State private var selected = Set<String>()
    @State private var showAlbumPicker = false
    @State private var showDeleteConfirm = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    // Plus la grille est serrée, plus la vignette doit être nette
    private var thumbnailPixels: CGFloat {
        columns <= 2 ? 600 : (columns <= 4 ? 300 : 220)
    }

    private var selectedAssets: [PHAsset] {
        library.assets.filter { selected.contains($0.localIdentifier) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.authorized {
                    grid
                } else {
                    accessRequest
                }
            }
            .navigationTitle(isSelecting ? (selected.isEmpty ? "Sélectionner" : "\(selected.count) sélectionné(s)") : "Photos")
            .toolbar {
                toolbarContent
            }
        }
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .onAppear { library.checkAccess() }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(assets: library.assets, library: library, startIndex: item.index)
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPicker(library: library, assets: selectedAssets) {
                finishSelection()
            }
        }
        .confirmationDialog(
            "Supprimer \(selected.count) élément(s) ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                library.delete(selectedAssets) { finishSelection() }
            }
        } message: {
            Text("Ils iront dans « Supprimés récemment » pendant 30 jours.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if library.authorized {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button { finishSelection() } label: {
                        Image(systemName: "xmark")
                    }
                } else {
                    Button("Sélectionner") { isSelecting = true }
                }
            }
        }
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { copySelected() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(selected.isEmpty)

                Button { duplicateSelected() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selected.isEmpty)

                Button { hideSelected() } label: {
                    Image(systemName: "eye.slash")
                }
                .disabled(selected.isEmpty)

                Button { showAlbumPicker = true } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .disabled(selected.isEmpty)

                Spacer()

                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
                .disabled(selected.isEmpty)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(Array(library.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    ThumbnailView(
                        asset: asset,
                        targetPixels: thumbnailPixels,
                        isSelecting: isSelecting,
                        isSelected: selected.contains(asset.localIdentifier)
                    )
                    .onTapGesture {
                        if isSelecting {
                            toggle(asset)
                        } else {
                            viewer = ViewerItem(index: index)
                        }
                    }
                }
            }
        }
        .gesture(pinchGesture)
        .refreshable {
            library.reload()
            // Minimum visible même si le chargement est immédiat
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    // Écarter les doigts = moins de colonnes (plus grand), rapprocher = plus de colonnes (plus petit)
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStart == nil { pinchStart = columns }
                let base = pinchStart ?? columns
                let newCount = Int((Double(base) / Double(scale)).rounded())
                columns = min(max(newCount, 1), 8)
            }
            .onEnded { _ in
                pinchStart = nil
            }
    }

    private var accessRequest: some View {
        VStack(spacing: 16) {
            Text("HoloPhotos a besoin d'accéder à tes photos et vidéos.")
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
