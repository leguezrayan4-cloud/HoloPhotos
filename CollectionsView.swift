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
                        CollectionGrid(title: "Ajoutées récemment", assets: smartAssets(.smartAlbumRecentlyAdded), library: library)
                    } label: {
                        Label("Ajoutées récemment", systemImage: "plus.circle")
                    }

                    NavigationLink {
                        CollectionGrid(title: "Vidéos", assets: smartAssets(.smartAlbumVideos), library: library)
                    } label: {
                        Label("Vidéos", systemImage: "video")
                    }
                }

                Section {
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
                } header: {
                    Text("Nettoyer")
                } footer: {
                    Text("Les doublons et les photos floues arriveront avec l'analyse IA.")
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
                // L'album privé est créé dans Photos dès la première ouverture
                if library.authorized {
                    Vault.createIfNeeded { _ in }
                }
            }
        }
    }
}

struct CollectionGrid: View {
    let title: String
    let assets: [PHAsset]
    @ObservedObject var library: PhotoLibrary
    @State private var viewerIndex: ViewerItem?

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                Text("Rien ici pour le moment.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        ThumbnailView(asset: asset, targetPixels: 300)
                            .onTapGesture {
                                viewerIndex = ViewerItem(index: index)
                            }
                    }
                }
            }
        }
        .navigationTitle(title)
        .fullScreenCover(item: $viewerIndex) { item in
            PhotoViewer(assets: assets, library: library, startIndex: item.index)
        }
    }
}
