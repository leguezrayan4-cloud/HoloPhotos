import Photos
import SwiftUI

// Dossiers d'albums, stockés dans Photos d'Apple (visibles aussi dans l'app Photos)
enum Folders {
    static func topLevel() -> [PHCollection] {
        var list: [PHCollection] = []
        PHCollectionList.fetchTopLevelUserCollections(with: nil).enumerateObjects { collection, _, _ in
            list.append(collection)
        }
        return list
    }

    static func albums(in folder: PHCollectionList) -> [PHAssetCollection] {
        var list: [PHAssetCollection] = []
        PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection { list.append(album) }
        }
        return list
    }

    static func folders() -> [PHCollectionList] {
        topLevel().compactMap { $0 as? PHCollectionList }
    }

    static func create(named name: String, done: @escaping () -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            _ = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: trimmed)
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    static func add(_ album: PHAssetCollection, to folder: PHCollectionList, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHCollectionListChangeRequest(for: folder)?.addChildCollections([album] as NSArray)
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    static func remove(_ album: PHAssetCollection, from folder: PHCollectionList, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHCollectionListChangeRequest(for: folder)?.removeChildCollections([album] as NSArray)
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    static func move(_ indexes: IndexSet, to destination: Int, in folder: PHCollectionList, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHCollectionListChangeRequest(for: folder)?.moveChildCollections(at: indexes, to: destination)
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    static func rename(_ folder: PHCollectionList, to name: String, done: @escaping () -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            PHCollectionListChangeRequest(for: folder)?.title = trimmed
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    static func delete(_ folder: PHCollectionList, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHCollectionListChangeRequest.deleteCollectionLists([folder] as NSArray)
        }) { _, _ in
            DispatchQueue.main.async(execute: done)
        }
    }
}

// Contenu d'un dossier : réorganisation des albums par glisser-déposer
struct FolderView: View {
    let folder: PHCollectionList
    @ObservedObject var library: PhotoLibrary
    @State private var albums: [PHAssetCollection] = []
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if albums.isEmpty {
                Text("Ce dossier est vide. Dans la liste des albums, glisse un album vers la gauche et touche « Ranger ».")
                    .foregroundStyle(.secondary)
            }
            ForEach(albums, id: \.localIdentifier) { album in
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
                    Button {
                        Folders.remove(album, from: folder) { reload() }
                    } label: {
                        Label("Sortir du dossier", systemImage: "arrow.up.right.square")
                    }
                    .tint(.blue)
                }
            }
            .onMove { indexes, destination in
                albums.move(fromOffsets: indexes, toOffset: destination)
                Folders.move(indexes, to: destination, in: folder) { reload() }
            }
        }
        .navigationTitle(folder.localizedTitle ?? "Dossier")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newName = folder.localizedTitle ?? ""; showRename = true } label: {
                        Label("Renommer", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Supprimer le dossier", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Plus d’options")
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .alert("Renommer le dossier", isPresented: $showRename) {
            TextField("Nom", text: $newName)
            Button("Enregistrer") {
                Folders.rename(folder, to: newName) { reload() }
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer ce dossier ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le dossier", role: .destructive) {
                Folders.delete(folder) { dismiss() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les albums et les photos restent dans ta galerie.")
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        albums = Folders.albums(in: folder)
    }
}

// Choix du dossier de destination pour un album
struct MoveAlbumSheet: View {
    let album: PHAssetCollection
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newFolder = true
                } label: {
                    Label("Nouveau dossier", systemImage: "folder.badge.plus")
                }
                ForEach(Folders.folders(), id: \.localIdentifier) { folder in
                    Button {
                        Folders.add(album, to: folder) {
                            onDone()
                            dismiss()
                        }
                    } label: {
                        Label(folder.localizedTitle ?? "Dossier", systemImage: "folder")
                    }
                }
            }
            .navigationTitle("Ranger dans un dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .alert("Nouveau dossier", isPresented: $newFolder) {
                TextField("Nom du dossier", text: $newFolderName)
                Button("Créer") {
                    Folders.create(named: newFolderName) {
                        onDone()
                        dismiss()
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}
