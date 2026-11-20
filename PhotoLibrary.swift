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
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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
        let trashed = TrashStore.ids
        return fetchHiddenAssets().filter { !trashed.contains($0.localIdentifier) }
    }

    static func trashedAssets() -> [PHAsset] {
        let trashed = TrashStore.ids
        return fetchHiddenAssets().filter { trashed.contains($0.localIdentifier) }
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

    // « Supprimer » : envoie dans la corbeille de l'app (masqué + daté)
    func trash(_ assets: [PHAsset], done: @escaping () -> Void) {
        let ids = assets.map { $0.localIdentifier }
        TrashStore.add(ids)
        PHPhotoLibrary.shared().performChanges({
            for asset in assets {
                PHAssetChangeRequest(for: asset).isHidden = true
            }
        }) { success, _ in
            if !success { TrashStore.remove(ids) }
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }

    func restore(_ assets: [PHAsset], done: @escaping () -> Void) {
        let ids = assets.map { $0.localIdentifier }
        PHPhotoLibrary.shared().performChanges({
            for asset in assets {
                PHAssetChangeRequest(for: asset).isHidden = false
            }
        }) { success, _ in
            if success { TrashStore.remove(ids) }
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }

    // Suppression réelle : iOS demande une confirmation, puis l'élément passe dans « Supprimés récemment » de Photos
    func deletePermanently(_ assets: [PHAsset], done: @escaping (Bool) -> Void) {
        let ids = assets.map { $0.localIdentifier }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, _ in
            if success { TrashStore.remove(ids) }
            self.reload()
            DispatchQueue.main.async { done(success) }
        }
    }

    // Efface définitivement les éléments dont le délai est dépassé
    func purgeExpired() {
        guard authorized else { return }
        let expired = Set(TrashStore.expiredIDs())
        guard !expired.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let found = Self.fetchHiddenAssets().filter { expired.contains($0.localIdentifier) }
            let foundIDs = Set(found.map { $0.localIdentifier })
            let orphans = Array(expired.subtracting(foundIDs))
            DispatchQueue.main.async {
                TrashStore.remove(orphans)
                if !found.isEmpty {
                    self.deletePermanently(found) { _ in }
                }
            }
        }
    }

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
        }) { success, _ in
            if success, let asset {
                self.trash([asset], done: done)
            } else {
                self.reload()
                DispatchQueue.main.async(execute: done)
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
