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

func hiddenAssets() -> [PHAsset] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.includeHiddenAssets = true
    options.predicate = NSPredicate(format: "isHidden == YES")
    var list: [PHAsset] = []
    PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
        list.append(asset)
    }
    return list
}

func recentlyDeletedAssets() -> [PHAsset] {
    guard let collection = PHAssetCollection.fetchAssetCollections(
        with: .smartAlbum, subtype: PHAssetCollectionSubtype(rawValue: 1_000_000_201)!, options: nil
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

    var body: some View {
        NavigationStack {
            List {
                Section("Mes collections") {
                    NavigationLink {
                        CollectionGrid(title: "Récents", assets: library.assets, library: library)
                    } label: {
                        Label("Récents", systemImage: "clock")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Favoris", assets: smartAssets(.smartAlbumFavorites), library: library)
                    } label: {
                        Label("Favoris", systemImage: "heart")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Captures d'écran", assets: smartAssets(.smartAlbumScreenshots), library: library)
                    } label: {
                        HStack {
                            Label("Captures d'écran", systemImage: "camera.viewfinder")
                            Spacer()
                            Text("\(smartAssets(.smartAlbumScreenshots).count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        CollectionGrid(title: "Vidéos", assets: smartAssets(.smartAlbumVideos), library: library)
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
                        CollectionGrid(title: "Masqués", assets: hiddenAssets(), library: library, showUnhide: true)
                    } label: {
                        Label("Masqués", systemImage: "eye.slash")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Supprimés récemment", assets: recentlyDeletedAssets(), library: library, isRecentlyDeleted: true)
                    } label: {
                        Label("Supprimés récemment", systemImage: "trash")
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
                CollectionGrid(title: "Captures d'écran", assets: smartAssets(.smartAlbumScreenshots), library: library)
            } label: {
                Label("Captures d'écran", systemImage: "camera.viewfinder")
            }

            NavigationLink {
                CollectionGrid(title: "Vidéos", assets: smartAssets(.smartAlbumVideos), library: library)
            } label: {
                Label("Vidéos", systemImage: "video")
            }
        }
        .navigationTitle("Nettoyer")
    }
}

struct AlbumDetailView: View {
    let album: PHAssetCollection
    @ObservedObject var library: PhotoLibrary
    @State private var assets: [PHAsset] = []
    @State private var subAlbums: [PHAssetCollection] = []

    var body: some View {
        List {
            if !subAlbums.isEmpty {
                Section("Dossiers & sous-albums") {
                    ForEach(subAlbums, id: \.localIdentifier) { sub in
                        NavigationLink {
                            AlbumDetailView(album: sub, library: library)
                        } label: {
                            Label(sub.localizedTitle ?? "Album", systemImage: "folder")
                        }
                    }
                }
            }

            Section("Contenu") {
                if assets.isEmpty {
                    Text("Album vide")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        CollectionGrid(title: album.localizedTitle ?? "Album", assets: assets, library: library)
                    } label: {
                        Label("Voir les \(assets.count) éléments", systemImage: "photo.on.rectangle")
                    }
                }
            }
        }
        .navigationTitle(album.localizedTitle ?? "Album")
        .onAppear(perform: load)
    }

    private func load() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var list: [PHAsset] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        assets = list

        // Support basique des dossiers / albums imbriqués via PHCollectionList
        var subs: [PHAssetCollection] = []
        if let list = album as? PHCollectionList {
            let children = PHCollectionList.fetchCollections(in: list, options: nil)
            children.enumerateObjects { collection, _, _ in
                if let albumCollection = collection as? PHAssetCollection {
                    subs.append(albumCollection)
                }
            }
        }
        subAlbums = subs
    }
}

struct CollectionGrid: View {
    let title: String
    let assets: [PHAsset]
    @ObservedObject var library: PhotoLibrary
    var showUnhide = false
    var isRecentlyDeleted = false
    @State private var viewerIndex: ViewerItem?
    @State private var isSelecting = false
    @State private var selected = Set<String>()
    @State private var showDeleteConfirm = false

    private var selectedAssets: [PHAsset] {
        assets.filter { selected.contains($0.localIdentifier) }
    }

    var body: some View {
        ScrollView {
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
                            isSelected: selected.contains(asset.localIdentifier)
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
                } else {
                    Button("Sélectionner") { isSelecting = true }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    if showUnhide {
                        Button {
                            unhideSelected()
                        } label: {
                            Image(systemName: "eye")
                        }
                        .disabled(selected.isEmpty)
                    }
                    Spacer()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { item in
            PhotoViewer(assets: assets, library: library, startIndex: item.index)
        }
        .confirmationDialog(
            "Supprimer \(selected.count) élément(s) ?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                library.delete(selectedAssets) {
                    selected.removeAll()
                    isSelecting = false
                }
            }
        } message: {
            Text(isRecentlyDeleted
                 ? "Ces éléments seront définitivement effacés."
                 : "Ils iront dans « Supprimés récemment » pendant 30 jours.")
        }
    }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    private func unhideSelected() {
        library.unhide(selectedAssets) {
            selected.removeAll()
            isSelecting = false
        }
    }
}