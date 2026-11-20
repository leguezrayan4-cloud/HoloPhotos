import LocalAuthentication
import Photos
import SwiftUI

enum Vault {
    private static let albumKey = "vaultAlbumID"
    private static let nameKey = "vaultName"

    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "Privé" }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static var albumID: String? {
        get { UserDefaults.standard.string(forKey: albumKey) }
        set { UserDefaults.standard.set(newValue, forKey: albumKey) }
    }

    static func album() -> PHAssetCollection? {
        guard let id = albumID else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    // Crée l'album dans Photos s'il n'existe pas encore
    static func createIfNeeded(completion: @escaping (PHAssetCollection?) -> Void) {
        if let existing = album() {
            completion(existing)
            return
        }
        var placeholderID: String?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholderID = request.placeholderForCreatedAssetCollection.localIdentifier
        }) { success, _ in
            DispatchQueue.main.async {
                if success, let id = placeholderID {
                    albumID = id
                    completion(album())
                } else {
                    completion(nil)
                }
            }
        }
    }

    static func rename(_ newName: String, completion: @escaping () -> Void) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let collection = album() else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest(for: collection)?.title = trimmed
        }) { _, _ in
            DispatchQueue.main.async {
                name = trimmed
                completion()
            }
        }
    }

    // Face ID ou code du téléphone, selon ce que le système propose
    static func authenticate(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ouvrir « \(name) »") { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}

struct VaultView: View {
    @ObservedObject var library: PhotoLibrary
    @State private var unlocked = false
    @State private var assets: [PHAsset] = []
    @State private var viewerIndex: ViewerItem?
    @State private var showRename = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        Group {
            if unlocked {
                unlockedView
            } else {
                lockedView
            }
        }
        .navigationTitle(Vault.name)
        .toolbar {
            if unlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newName = Vault.name
                            showRename = true
                        } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                        Button {
                            unlocked = false
                            assets = []
                        } label: {
                            Label("Verrouiller", systemImage: "lock")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Renommer le coffre", isPresented: $showRename) {
            TextField("Nom", text: $newName)
            Button("Enregistrer") {
                Vault.rename(newName) { reloadAssets() }
            }
            Button("Annuler", role: .cancel) {}
        }
        .fullScreenCover(item: $viewerIndex) { item in
            PhotoViewer(assets: assets, library: library, startIndex: item.index)
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(Vault.name)
                .font(.title2.bold())
            Text("Déverrouille avec Face ID ou le code de ton téléphone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Déverrouiller") {
                unlock()
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var unlockedView: some View {
        Group {
            if assets.isEmpty {
                VStack(spacing: 12) {
                    Text("Album vide")
                        .font(.headline)
                    Text("Dans la galerie, touche Sélectionner, puis Ajouter à un album, puis « \(Vault.name) ».")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
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
        }
    }

    private func unlock() {
        Vault.authenticate { ok in
            if ok {
                message = nil
                Vault.createIfNeeded { _ in
                    unlocked = true
                    reloadAssets()
                }
            } else {
                message = "Déverrouillage refusé, ou aucun code n'est défini sur ce téléphone."
            }
        }
    }

    private func reloadAssets() {
        guard let album = Vault.album() else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var list: [PHAsset] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        assets = list
    }
}
