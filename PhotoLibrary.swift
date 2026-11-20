import Photos
import SwiftUI

private final class ImageCollector {
    var images: [UIImage] = []
}

final class PhotoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var albums: [PHAssetCollection] = []
    @Published var authorized = false

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let autoRefresh = UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true
        guard autoRefresh else { return }
        DispatchQueue.main.async {
            self.reload()
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

    func reload() {
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
            self.assets = photoList
            self.albums = albumList
        }
    }

    func loadImages(_ assets: [PHAsset], completion: @escaping ([UIImage]) -> Void) {
        let photosOnly = assets.filter { $0.mediaType == .image }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let collector = ImageCollector()
        let group = DispatchGroup()
        for asset in photosOnly {
            group.enter()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, _ in
                DispatchQueue.main.async {
                    if let image { collector.images.append(image) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion(collector.images)
        }
    }

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

    func delete(_ assets: [PHAsset], done: @escaping () -> Void) {
        apply({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
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

    // Sauvegarde une image éditée (rotation / luminosité / recadrage)
    func saveEditedImage(_ image: UIImage, replacing asset: PHAsset?, done: @escaping () -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            done()
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            if let asset {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
        }) { _, _ in
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }

    private func apply(_ changes: @escaping () -> Void, done: @escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges(changes) { _, _ in
            self.reload()
            DispatchQueue.main.async(execute: done)
        }
    }
}
