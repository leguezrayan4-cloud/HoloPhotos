import Combine
import CryptoKit
import Network
import Photos
import SwiftUI

enum BackupState: Equatable {
    case idle
    case scanning
    case uploading(done: Int, total: Int)
    case restoring(done: Int, total: Int)
    case finished(String)
    case failed(String)
}

private enum BackupError: LocalizedError {
    case noNetwork
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "Pas de Wi-Fi : la sauvegarde est en pause. Elle reprendra au prochain essai."
        case .exportFailed:
            return "Impossible de lire cette photo."
        }
    }
}

// Sauvegarde les photos et vidéos de la galerie dans le Google Drive de l'utilisateur
// (dossier « HoloPhotos ») et peut les restaurer sur un autre iPhone.
@MainActor
final class BackupManager: ObservableObject {
    let auth = DriveAuth()
    private let client: DriveClient

    @Published private(set) var state: BackupState = .idle
    @Published private(set) var lastBackup: Date?
    @Published private(set) var failedCount = 0

    private let monitor = NWPathMonitor()
    private var path: NWPath?
    private var task: Task<Void, Never>?
    private var lastAutoRun = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init() {
        client = DriveClient(auth: auth)
        lastBackup = UserDefaults.standard.object(forKey: "backupLastDate") as? Date

        // Les écrans observent le gestionnaire : on relaie les changements de connexion
        auth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        monitor.pathUpdateHandler = { [weak self] newPath in
            Task { @MainActor in self?.path = newPath }
        }
        monitor.start(queue: DispatchQueue(label: "holophotos.network"))
    }

    // MARK: - Réglages

    private var wifiOnly: Bool {
        UserDefaults.standard.object(forKey: "backupWiFiOnly") as? Bool ?? true
    }

    private var includeVideos: Bool {
        UserDefaults.standard.object(forKey: "backupVideos") as? Bool ?? true
    }

    private var optimized: Bool {
        UserDefaults.standard.string(forKey: "backupQuality") == "optimized"
    }

    private var autoEnabled: Bool {
        UserDefaults.standard.bool(forKey: "backupAuto")
    }

    private var networkAllowed: Bool {
        guard let path else { return true }
        guard path.status == .satisfied else { return false }
        return wifiOnly ? !path.isExpensive : true
    }

    var isRunning: Bool {
        switch state {
        case .scanning, .uploading, .restoring: return true
        default: return false
        }
    }

    // MARK: - Lancement

    func backupNow() {
        guard !isRunning else { return }
        start { await self.runBackup() }
    }

    func restoreMissing() {
        guard !isRunning else { return }
        start { await self.runRestore() }
    }

    func cancel() {
        task?.cancel()
    }

    // Appelée quand l'app revient au premier plan
    func autoRunIfNeeded() {
        guard autoEnabled, auth.isSignedIn, !isRunning, networkAllowed else { return }
        guard Date().timeIntervalSince(lastAutoRun) > 3600 else { return }
        lastAutoRun = Date()
        start { await self.runBackup() }
    }

    private func start(_ work: @escaping @MainActor () async -> Void) {
        task = Task { @MainActor in
            // Garde l'app active quelques minutes si l'utilisateur la quitte
            var background = UIBackgroundTaskIdentifier.invalid
            background = UIApplication.shared.beginBackgroundTask {
                self.task?.cancel()
                UIApplication.shared.endBackgroundTask(background)
            }
            UIApplication.shared.isIdleTimerDisabled = true
            await work()
            UIApplication.shared.isIdleTimerDisabled = false
            if background != .invalid {
                UIApplication.shared.endBackgroundTask(background)
            }
        }
    }

    // MARK: - Sauvegarde

    private func runBackup() async {
        guard auth.isSignedIn else {
            state = .failed(DriveError.notSignedIn.localizedDescription)
            return
        }
        guard networkAllowed else {
            state = .failed(BackupError.noNetwork.localizedDescription)
            return
        }
        guard await requestPhotoAccess() else {
            state = .failed("HoloPhotos n'a pas accès à ta galerie.")
            return
        }

        failedCount = 0
        state = .scanning
        do {
            let remoteKeys = Set(try await client.listBackedUp().compactMap { $0.key })

            // Le parcours de la galerie se fait en arrière-plan pour ne pas figer l'écran
            let excluded = excludedIDs()
            let videos = includeVideos
            let todo = await Task.detached(priority: .utility) {
                Self.pendingUploads(includeVideos: videos, excluded: excluded, remoteKeys: remoteKeys)
            }.value
            guard !todo.isEmpty else {
                finish("Tout est déjà sauvegardé.")
                return
            }

            var sent = 0
            for (index, item) in todo.enumerated() {
                try Task.checkCancellation()
                guard networkAllowed else { throw BackupError.noNetwork }
                state = .uploading(done: index, total: todo.count)
                do {
                    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject else {
                        continue
                    }
                    try await upload(asset, key: item.key)
                    sent += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch DriveError.notSignedIn {
                    throw DriveError.notSignedIn
                } catch let error as DriveError {
                    // Drive plein ou API non activée : inutile de continuer
                    if case .http(let code, _) = error, code == 403 { throw error }
                    failedCount += 1
                } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                    throw BackupError.noNetwork
                } catch {
                    failedCount += 1
                }
            }

            UserDefaults.standard.set(Date(), forKey: "backupLastDate")
            lastBackup = Date()
            let tail = failedCount > 0 ? " \(failedCount) élément(s) n'ont pas pu être envoyés." : ""
            finish("\(sent) élément(s) sauvegardé(s).\(tail)")
        } catch is CancellationError {
            state = .failed("Sauvegarde arrêtée.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func upload(_ asset: PHAsset, key: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let exported = try await export(asset, into: directory)
        try await client.upload(
            fileURL: exported.url,
            name: exported.name,
            mimeType: exported.mimeType,
            key: key,
            created: asset.creationDate ?? Date()
        )
    }

    // MARK: - Restauration

    private func runRestore() async {
        guard auth.isSignedIn else {
            state = .failed(DriveError.notSignedIn.localizedDescription)
            return
        }
        guard await requestPhotoAccess() else {
            state = .failed("HoloPhotos n'a pas accès à ta galerie.")
            return
        }

        failedCount = 0
        state = .scanning
        do {
            let remote = try await client.listBackedUp()

            // Éléments déjà présents sur cet iPhone (y compris masqués)
            let localKeys = await Task.detached(priority: .utility) {
                Self.allLocalKeys()
            }.value

            let todo = remote.filter { file in
                guard let key = file.key else { return false }
                return !localKeys.contains(key)
            }
            guard !todo.isEmpty else {
                finish("Aucune photo à restaurer : tout est déjà sur cet iPhone.")
                return
            }

            var restored = 0
            for (index, file) in todo.enumerated() {
                try Task.checkCancellation()
                state = .restoring(done: index, total: todo.count)
                do {
                    try await restore(file)
                    restored += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch DriveError.notSignedIn {
                    throw DriveError.notSignedIn
                } catch {
                    failedCount += 1
                }
            }
            let tail = failedCount > 0 ? " \(failedCount) élément(s) ont échoué." : ""
            finish("\(restored) élément(s) restauré(s).\(tail)")
        } catch is CancellationError {
            state = .failed("Restauration arrêtée.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func restore(_ file: DriveFile) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent(file.name)
        try await client.download(fileID: file.id, to: destination)

        let isVideo = ["mov", "mp4", "m4v"].contains(destination.pathExtension.lowercased())
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = file.name
            request.addResource(with: isVideo ? .video : .photo, fileURL: destination, options: options)
            if let created = file.created { request.creationDate = created }
        }
    }

    // MARK: - Photos

    private func requestPhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return granted == .authorized || granted == .limited
    }

    // Éléments à ne jamais envoyer : corbeille interne et coffre privé
    private func excludedIDs() -> Set<String> {
        var excluded = TrashStore.ids
        if let album = Vault.album() {
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                excluded.insert(asset.localIdentifier)
            }
        }
        return excluded
    }

    // Photos et vidéos pas encore sauvegardées, de la plus ancienne à la plus récente
    nonisolated private static func pendingUploads(
        includeVideos: Bool,
        excluded: Set<String>,
        remoteKeys: Set<String>
    ) -> [(id: String, key: String)] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if includeVideos {
            options.predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
            )
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }

        var result: [(id: String, key: String)] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard !excluded.contains(asset.localIdentifier),
                  let key = Self.key(for: asset),
                  !remoteKeys.contains(key) else { return }
            result.append((asset.localIdentifier, key))
        }
        return result
    }

    nonisolated private static func allLocalKeys() -> Set<String> {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        var keys = Set<String>()
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if let key = Self.key(for: asset) { keys.insert(key) }
        }
        return keys
    }

    // Clé de déduplication : nom sans extension + date de création.
    // Identique sur tous les appareils et avant/après restauration.
    nonisolated private static func key(for asset: PHAsset) -> String? {
        guard
            let date = asset.creationDate,
            let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename
        else { return nil }
        let base = (filename as NSString).deletingPathExtension
        let raw = "\(base)|\(Int(date.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    private struct Exported {
        let url: URL
        let name: String
        let mimeType: String
    }

    private func export(_ asset: PHAsset, into directory: URL) async throws -> Exported {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let original = resources.first else { throw BackupError.exportFailed }
        let baseName = (original.originalFilename as NSString).deletingPathExtension

        // Photo en version optimisée : JPEG réduit, bien plus léger
        if asset.mediaType == .image, optimized {
            let data = try await optimizedJPEG(asset)
            let url = directory.appendingPathComponent(baseName + ".jpg")
            try data.write(to: url)
            return Exported(url: url, name: baseName + ".jpg", mimeType: "image/jpeg")
        }

        let wanted: PHAssetResource?
        if asset.mediaType == .video {
            wanted = resources.first { $0.type == .fullSizeVideo } ?? resources.first { $0.type == .video }
        } else {
            wanted = resources.first { $0.type == .fullSizePhoto } ?? resources.first { $0.type == .photo }
        }
        guard let resource = wanted else { throw BackupError.exportFailed }

        let ext = (resource.originalFilename as NSString).pathExtension
        let name = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        let url = directory.appendingPathComponent(name)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)

        return Exported(url: url, name: name, mimeType: Self.mimeType(forExtension: ext))
    }

    private func optimizedJPEG(_ asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 2048, height: 2048),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                if let data = image?.jpegData(compressionQuality: 0.85) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: BackupError.exportFailed)
                }
            }
        }
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "heic", "heif": return "image/heic"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "dng": return "image/x-adobe-dng"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }

    private func finish(_ message: String) {
        state = .finished(message)
    }

    func dismissMessage() {
        if !isRunning { state = .idle }
    }
}
