import Photos
import SwiftUI

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var authorized = false

    func checkAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            authorized = true
            loadAssets()
        }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                let ok = (status == .authorized || status == .limited)
                self?.authorized = ok
                if ok { self?.loadAssets() }
            }
        }
    }

    func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        assets = list
    }
}
