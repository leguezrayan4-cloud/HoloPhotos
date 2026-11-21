import Foundation

// Configuration de la sauvegarde Google Drive.
// Colle ici l'ID client OAuth de type « iOS » créé dans Google Cloud Console
// (il ressemble à 123456789-abcdef.apps.googleusercontent.com).
enum DriveConfig {
    static let clientID = ""

    // drive.file : l'app ne voit que les fichiers qu'elle a elle-même créés
    static let scope = "https://www.googleapis.com/auth/drive.file email"

    static let folderName = "HoloPhotos"

    static var isConfigured: Bool { !clientID.isEmpty }

    // com.googleusercontent.apps.123456789-abcdef
    static var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var redirectURI: String { callbackScheme + ":/oauth2redirect" }
}
