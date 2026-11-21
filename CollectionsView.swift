import UIKit
import Photos
import SwiftUI

func smartAssets(_ subtype: PHAssetCollectionSubtype) -> [PHAsset] {
    guard let collection = PHAssetCollection.fetchAssetCollections(
        with: .smartAlbum, subtype: subtype, options: nil
    ).firstObject else { return [] }

    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    var list: [PHAsset] = []
    PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
        list.append(asset)
    }
    return list
}

struct CollectionsView: View {
    @ObservedObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var albumToRename: PHAssetCollection?
    @State private var albumToDelete: PHAssetCollection?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Mes collections") {
                    NavigationLink {
                        CollectionGrid(title: "Récents", library: library) { library.assets }
                    } label: {
                        Label("Récents", systemImage: "clock")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Favoris", library: library) { smartAssets(.smartAlbumFavorites) }
                    } label: {
                        Label("Favoris", systemImage: "heart")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Captures d'écran", library: library) { smartAssets(.smartAlbumScreenshots) }
                    } label: {
                        HStack {
                            Label("Captures d'écran", systemImage: "camera.viewfinder")
                            Spacer()
                            Text("\(smartAssets(.smartAlbumScreenshots).count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        CollectionGrid(title: "Vidéos", library: library) { smartAssets(.smartAlbumVideos) }
                    } label: {
                        Label("Vidéos", systemImage: "video")
                    }
                }

                Section {
                    NavigationLink {
                        CleanUpView(library: library)
                    } label: {
                        Label("Nettoyer", systemImage: "sparkles")
                    }
                } header: {
                    Text("Utilitaires")
                } footer: {
                    Text("Doublons, floues et suggestions d'organisation via l'IA.")
                }

                Section("Masqués & corbeille") {
                    NavigationLink {
                        CollectionGrid(title: "Masqués", library: library, showUnhide: true) { PhotoLibrary.hiddenAssets() }
                    } label: {
                        Label("Masqués", systemImage: "eye.slash")
                    }

                    Button {
                        // Ouvre directement l'app Photos d'Apple, qui affiche « Supprimés récemment »
                        if let url = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Supprimés récemment (dans Photos)", systemImage: "trash")
                    }
                }

                Section("Albums") {
                    ForEach(library.albums, id: \.localIdentifier) { album in
                        NavigationLink {
                            AlbumDetailView(album: album, library: library)
                        } label: {
                            HStack {
                                Label(album.localizedTitle ?? "Album", systemImage: "rectangle.stack")
                                Spacer()
                                Text("\(PHAsset.fetchAssets(in: album, options: nil).count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                albumToDelete = album
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                            Button {
                                renameText = album.localizedTitle ?? ""
                                albumToRename = album
                            } label: {
                                Label("Renommer", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }

                Section("Privé") {
                    NavigationLink {
                        VaultView(library: library)
                    } label: {
                        Label(Vault.name, systemImage: "lock.fill")
                    }
                }
            }
            .alert("Renommer l'album", isPresented: Binding(
                get: { albumToRename != nil },
                set: { if !$0 { albumToRename = nil } }
            )) {
                TextField("Nom", text: $renameText)
                Button("Enregistrer") { renameAlbum() }
                Button("Annuler", role: .cancel) { albumToRename = nil }
            }
            .confirmationDialog(
                "Supprimer cet album ?",
                isPresented: Binding(
                    get: { albumToDelete != nil },
                    set: { if !$0 { albumToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer l'album", role: .destructive) { deleteAlbum() }
                Button("Annuler", role: .cancel) { albumToDelete = nil }
            } message: {
                Text("Les photos restent dans ta galerie.")
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear {
                if library.authorized {
                    Vault.createIfNeeded { _ in }
                }
            }
        }
    }
}

struct CleanUpView: View {
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        List {
            Section {
                Text("L'analyse IA des doublons et photos floues arrive bientôt. En attendant, tu peux parcourir les sections ci-dessous.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                CollectionGrid(title: "Captures d'écran", library: library) { smartAssets(.smartAlbumScreenshots) }
            } label: {
                Label("Captures d'écran", systemImage: "camera.viewfinder")
            }

            NavigationLink {
                CollectionGrid(title: "Vidéos", library: library) { smartAssets(.smartAlbumVideos) }
            } label: {
                Label("Vidéos", systemImage: "video")
            }
        }
        .navigationTitle("Nettoyer")
    }
}

// Un album s'ouvre directement sur sa grille, mise à jour en direct
struct AlbumDetailView: View {
    let album: PHAssetCollection
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        CollectionGrid(title: album.localizedTitle ?? "Album", library: library, album: album) {
            PhotoLibrary.fetchAssets(in: album)
        }
    }
}

struct CollectionGrid: View {
    let title: String
    @ObservedObject var library: PhotoLibrary
    var album: PHAssetCollection? = nil
    var showUnhide = false
    var isRecentlyDeleted = false
    let loader: () -> [PHAsset]

    @State private var assets: [PHAsset] = []
    @State private var viewerIndex: ViewerItem?
    @State private var isSelecting = false
    @State private var selected = Set<String>()
    @State private var showDeleteConfirm = false

    private var selectedAssets: [PHAsset] {
        assets.filter { selected.contains($0.localIdentifier) }
    }

    private var viewerContext: ViewerContext {
        if isRecentlyDeleted { return .trash }
        if showUnhide { return .hidden }
        if let album { return .album(album) }
        return .normal
    }

    var body: some View {
        ScrollView {
            if isRecentlyDeleted {
                Text("Les photos supprimées sont conservées 30 jours dans « Supprimés récemment » de l'app Photos d'Apple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            if assets.isEmpty {
                Text("Rien ici pour le moment.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        ThumbnailView(
                            asset: asset,
                            targetPixels: 300,
                            isSelecting: isSelecting,
                            isSelected: selected.contains(asset.localIdentifier),
                            caption: isRecentlyDeleted ? daysLeftText(asset) : nil
                        )
                        .onTapGesture {
                            if isSelecting {
                                toggle(asset)
                            } else {
                                viewerIndex = ViewerItem(index: index)
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            if !isSelecting {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isSelecting = true
                                    selected.insert(asset.localIdentifier)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isSelecting ? "\(selected.count) sélectionné(s)" : title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button("OK") {
                        selected.removeAll()
                        isSelecting = false
                    }
                } else if !assets.isEmpty {
                    Button("Sélectionner") { isSelecting = true }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Tout") {
                        selected = Set(assets.map { $0.localIdentifier })
                    }

                    if isRecentlyDeleted {
                        Spacer()
                        Button { restoreSelected() } label: {
                            Label("Restaurer", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(selected.isEmpty)
                    }

                    if showUnhide {
                        Spacer()
                        Button { unhideSelected() } label: {
                            Image(systemName: "eye")
                        }
                        .disabled(selected.isEmpty)
                    }

                    Spacer()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash").accessibilityLabel("Supprimer")
                    }
                    .tint(.red)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { item in
            PhotoViewer(assets: assets, library: library, startIndex: item.index, context: viewerContext)
        }
        .confirmationDialog(
            isRecentlyDeleted ? "Supprimer définitivement \(selected.count) élément(s) ?" : "Supprimer \(selected.count) élément(s) ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            if isRecentlyDeleted {
                Button("Supprimer définitivement", role: .destructive) {
                    deleteForever()
                }
            } else {
                if let album {
                    Button("Supprimer de l'album") {
                        removeFromAlbum(album)
                    }
                }
                Button("Supprimer", role: .destructive) {
                    trashSelected()
                }
            }
        } message: {
            Text(isRecentlyDeleted
                 ? "Ils seront effacés de ta galerie. iOS te demandera de confirmer."
                 : "Elles seront déplacées dans « Supprimés récemment » de Photos.")
        }
        .onAppear {
            if isRecentlyDeleted { library.purgeExpired() }
            reload()
        }
        .onChange(of: library.changeToken) { _, _ in
            reload()
        }
    }

    private func reload() {
        let load = loader
        DispatchQueue.global(qos: .userInitiated).async {
            let list = load()
            DispatchQueue.main.async {
                assets = list
                let ids = Set(list.map { $0.localIdentifier })
                selected = selected.filter { ids.contains($0) }
            }
        }
    }

    private func daysLeftText(_ asset: PHAsset) -> String? {
        guard let days = TrashStore.daysLeft(for: asset.localIdentifier) else { return nil }
        return "\(days) j"
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

    private func trashSelected() {
        library.trash(selectedAssets) { finishSelection() }
    }

    private func removeFromAlbum(_ album: PHAssetCollection) {
        library.remove(selectedAssets, from: album) { finishSelection() }
    }

    private func restoreSelected() {
        library.restore(selectedAssets) { finishSelection() }
    }

    private func deleteForever() {
        library.deletePermanently(selectedAssets) { success in
            if success { finishSelection() }
        }
    }

    private func unhideSelected() {
        library.unhide(selectedAssets) { finishSelection() }
    }
}

extension CollectionsView {
    fileprivate func renameAlbum() {
        guard let album = albumToRename else { return }
        let title = renameText.trimmingCharacters(in: .whitespaces)
        albumToRename = nil
        guard !title.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest(for: album)?.title = title
        }) { _, _ in
            library.reload()
        }
    }

    fileprivate func deleteAlbum() {
        guard let album = albumToDelete else { return }
        albumToDelete = nil
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }) { _, _ in
            library.reload()
        }
    }
}
