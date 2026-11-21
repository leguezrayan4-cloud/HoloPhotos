import Foundation

struct DriveFile: Identifiable {
    let id: String
    let name: String
    let key: String?
    let created: Date?
}

// Appels à l'API Google Drive v3. Tout reste dans le dossier « HoloPhotos » du Drive.
@MainActor
final class DriveClient {
    private let auth: DriveAuth
    private var folderID: String?

    init(auth: DriveAuth) {
        self.auth = auth
    }

    // MARK: - Dossier

    func ensureFolder() async throws -> String {
        if let folderID { return folderID }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "name = '\(DriveConfig.folderName)' and mimeType = 'application/vnd.google-apps.folder' and 'root' in parents and trashed = false"
            ),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        let (data, _) = try await send(URLRequest(url: components.url!))
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            folderID = id
            return id
        }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": DriveConfig.folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        let (created, _) = try await send(request)
        guard
            let json = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
            let id = json["id"] as? String
        else { throw DriveError.invalidResponse }
        folderID = id
        return id
    }

    // MARK: - Liste

    // Tous les fichiers déjà sauvegardés (avec leur clé de déduplication)
    func listBackedUp() async throws -> [DriveFile] {
        let folder = try await ensureFolder()
        var result: [DriveFile] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var items = [
                URLQueryItem(name: "q", value: "'\(folder)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,appProperties)"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "spaces", value: "drive")
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            let (data, _) = try await send(URLRequest(url: components.url!))
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DriveError.invalidResponse
            }
            for file in (json["files"] as? [[String: Any]]) ?? [] {
                guard let id = file["id"] as? String, let name = file["name"] as? String else { continue }
                let props = file["appProperties"] as? [String: String]
                let created = props?["c"].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
                result.append(DriveFile(id: id, name: name, key: props?["k"], created: created))
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil

        return result
    }

    // MARK: - Envoi (reprise possible : le fichier est lu depuis le disque, pas en mémoire)

    func upload(fileURL: URL, name: String, mimeType: String, key: String, created: Date) async throws {
        let folder = try await ensureFolder()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0

        let metadata: [String: Any] = [
            "name": name,
            "parents": [folder],
            "createdTime": Self.rfc3339(created),
            "appProperties": [
                "k": key,
                "c": String(Int(created.timeIntervalSince1970))
            ]
        ]

        // 1. Ouverture de la session d'envoi
        var start = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id")!)
        start.httpMethod = "POST"
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (_, startResponse) = try await send(start)

        guard
            let location = startResponse.value(forHTTPHeaderField: "Location"),
            let uploadURL = URL(string: location)
        else { throw DriveError.invalidResponse }

        // 2. Envoi du fichier
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        put.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.upload(for: put, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw DriveError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Téléchargement

    func download(fileID: String, to destination: URL) async throws {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DriveError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    // MARK: - Outils

    private func send(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = original
        let token = try await auth.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw DriveError.notSignedIn }
            throw DriveError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
