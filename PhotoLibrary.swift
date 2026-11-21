import CoreLocation
import Photos
import SwiftUI

private final class ImageCollector {
    var slots: [UIImage?]
    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }
}

final class PhotoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var albums: [PHAssetCollection] = []
    @Published var authorized = false
    // Change à chaque modification de la photothèque : les écrans (albums, favoris…) se rechargent dessus
    @Published var changeToken = 0

    private var reloadGeneration = 0

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let autoRefresh = UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true
        DispatchQueue.main.async {
            if autoRefresh {
                self.reload()
            } else {
                self.changeToken += 1
            }
        }
    }

    func checkAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            authorized = true
            reload()
        }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                let ok = (status == .authorized || status == .limited)
                self?.authorized = ok
                if ok { self?.reload() }
            }
        }
    }

    // MARK: - Chargement

    // Ordre choisi par l'utilisateur (menu de tri de la grille)
    static var sortDescriptors: [NSSortDescriptor] {
        switch UserDefaults.standard.string(forKey: "sortOrder") ?? "newest" {
        case "oldest": return [NSSortDescriptor(key: "creationDate", ascending: true)]
        case "modified": return [NSSortDescriptor(key: "modificationDate", ascending: false)]
        default: return [NSSortDescriptor(key: "creationDate", ascending: false)]
        }
    }

    func reload() {
        if Thread.isMainThread {
            startReload()
        } else {
            DispatchQueue.main.async { self.startReload() }
        }
    }

    private func startReload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = PhotoLibrary.sortDescriptors
            options.predicate = NSPredicate(
                format: "mediaType == %d || mediaType == %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            var photos: [PHAsset] = []
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                photos.append(asset)
            }
            var albums: [PHAssetCollection] = []
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
                .enumerateObjects { collection, _, _ in
                    albums.append(collection)
                }
            let photoList = photos
            let albumList = albums
            DispatchQueue.main.async {
                guard generation == self.reloadGeneration else { return }
                self.assets = photoList
                self.albums = albumList
                self.changeToken += 1
            }
        }
    }

    static func fetchAssets(in album: PHAssetCollection) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = PhotoLibrary.sortDescriptors
        var list: [PHAsset] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        return list
    }

    // Tous les éléments masqués (y compris ceux de la corbeille interne)
    private static func fetchHiddenAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.sortDescriptors = PhotoLibrary.sortDescriptors
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        var list: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if asset.isHidden { list.append(asset) }
        }
        return list
    }

    static func hiddenAssets() -> [PHAsset] {
        fetchHiddenAssets()
    }

    // Géré par Photos : accessible seulement dans l'app Photos d'Apple
    static func trashedAssets() -> [PHAsset] {
        []
    }

    func loadImages(_ assets: [PHAsset], completion: @escaping ([UIImage]) -> Void) {
        let photosOnly = assets.filter { $0.mediaType == .image }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let collector = ImageCollector(count: photosOnly.count)
        let group = DispatchGroup()
        for (index, asset) in photosOnly.enumerated() {
            group.enter()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                // On ignore les versions dégradées pour ne pas libérer le groupe deux fois
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                DispatchQueue.main.async {
                    collector.slots[index] = image
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion(collector.slots.compactMap { $0 })
        }
    }

    // MARK: - Actions

    func setFavorite(_ asset: PHAsset, _ value: Bool) {
        apply({
            PHAssetChangeRequest(for: asset).isFavorite = value
        }, done: {})
    }

    func hide(_ assets: [PHAsset], done: @escaping () -> Void) {
        apply({
            for asset in assets {
                PHAssetChangeRequest(for: asset).isHidden = true
            }
        }, done: done)
    }

    func unhide(_ assets: [PHAsset], done: @escaping () -> Void) {
        apply({
            for asset in assets {
                PHAssetChangeRequest(for: asset).isHidden = false
            }
        }, done: done)
    }

    // « Supprimer » : iOS affiche sa propre confirmation, puis l'élément va dans « Supprimés récemment » de Photos
    func trash(_ assets: [PHAsset], done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { _, _ in
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }

    // Les éléments sont gérés par Photos : on ne restaure que les éléments masqués
    func restore(_ assets: [PHAsset], done: @escaping () -> Void) {
        unhide(assets, done: done)
    }

    // Suppression définitive : iOS demande confirmation
    func deletePermanently(_ assets: [PHAsset], done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, _ in
            self.reload()
            DispatchQueue.main.async { done(success) }
        }
    }

    // Plus de corbeille interne : rien à purger
    func purgeExpired() {}

    func remove(_ assets: [PHAsset], from album: PHAssetCollection, done: @escaping () -> Void) {
        apply({
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.removeAssets(assets as NSArray)
        }, done: done)
    }

    func duplicate(_ assets: [PHAsset], done: @escaping () -> Void) {
        loadImages(assets) { images in
            PHPhotoLibrary.shared().performChanges({
                for image in images {
                    guard let data = image.jpegData(compressionQuality: 0.95) else { continue }
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            }) { _, _ in
                self.reload()
                DispatchQueue.main.async(execute: done)
            }
        }
    }

    func add(_ assets: [PHAsset], to album: PHAssetCollection, done: @escaping () -> Void) {
        apply({
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets as NSArray)
        }, done: done)
    }

    func createAlbum(named name: String, adding assets: [PHAsset], done: @escaping () -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        apply({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: trimmed.isEmpty ? "Nouvel album" : trimmed
            )
            request.addAssets(assets as NSArray)
        }, done: done)
    }

    // Sauvegarde l'image retouchée avec la date et le lieu d'origine, puis met l'original à la corbeille
    func saveEditedImage(_ image: UIImage, replacing asset: PHAsset?, done: @escaping () -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            done()
            return
        }
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            if let asset {
                request.creationDate = asset.creationDate
                request.location = asset.location
            }
        }) { _, _ in
            // Enregistrer une copie : l'original n'est jamais supprimé
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }

    // Enregistrer une modification sur la photo elle-même, comme dans Photos (pas de suppression de l'original)
    func applyEdit(_ image: UIImage, to asset: PHAsset, done: @escaping (Bool) -> Void) {
        guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
            DispatchQueue.main.async { done(false) }
            return
        }
        let options = PHContentEditingInputRequestOptions()
        options.canHandleAdjustmentData = { _ in true }
        asset.requestContentEditingInput(with: options) { input, _ in
            guard let input else {
                DispatchQueue.main.async { done(false) }
                return
            }
            let output = PHContentEditingOutput(contentEditingInput: input)
            do {
                try jpeg.write(to: output.renderedContentURL, options: .atomic)
            } catch {
                DispatchQueue.main.async { done(false) }
                return
            }
            output.adjustmentData = PHAdjustmentData(
                formatIdentifier: "com.holophotos.edit",
                formatVersion: "1.0",
                data: Data("edit".utf8)
            )
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                request.contentEditingOutput = output
            }) { success, _ in
                DispatchQueue.main.async {
                    self.reload()
                    done(success)
                }
            }
        }
    }

    // Suppression d'une photo depuis la vue : rend le résultat réel (accepté ou refusé par iOS)
    func trashAsset(_ asset: PHAsset, done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, _ in
            DispatchQueue.main.async {
                self.reload()
                done(success)
            }
        }
    }

    private func apply(_ changes: @escaping () -> Void, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges(changes) { _, _ in
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }
}
