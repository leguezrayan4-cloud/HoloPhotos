import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

enum DriveError: LocalizedError {
    case notConfigured
    case notSignedIn
    case cancelled
    case auth(String)
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Drive n'est pas configuré dans cette version de l'app."
        case .notSignedIn:
            return "Reconnecte-toi à Google pour continuer."
        case .cancelled:
            return "Connexion annulée."
        case .auth(let message):
            return message
        case .http(let code, let message):
            if code == 403 && message.contains("storageQuotaExceeded") {
                return "Ton Google Drive est plein."
            }
            if code == 403 && message.contains("accessNotConfigured") {
                return "L'API Google Drive n'est pas activée dans Google Cloud Console."
            }
            return "Google Drive a répondu avec une erreur (\(code))."
        case .invalidResponse:
            return "Réponse inattendue de Google Drive."
        }
    }
}

// Petit coffre dans le trousseau iOS pour garder la connexion entre deux lancements
enum Keychain {
    private static let service = "com.holophotos.drive"

    static func save(_ value: String, for account: String) -> Bool {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Connexion à Google (OAuth 2.0 avec PKCE) : donne accès au Drive de l'utilisateur,
// limité aux fichiers créés par HoloPhotos.
@MainActor
final class DriveAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isSignedIn = false
    @Published private(set) var email: String?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private let refreshKey = "googleRefreshToken"
    private let emailKey = "googleEmail"

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    // Si le trousseau est refusé (installation hors App Store), on garde le jeton en mémoire
    private var memoryRefreshToken: String?
    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        isSignedIn = refreshToken != nil
        email = UserDefaults.standard.string(forKey: emailKey)
    }

    private var refreshToken: String? {
        Keychain.read(refreshKey) ?? memoryRefreshToken
    }

    // MARK: - Connexion

    func signIn() async {
        guard DriveConfig.isConfigured else {
            errorMessage = DriveError.notConfigured.errorDescription
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let verifier = Self.randomString()
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: DriveConfig.clientID),
                URLQueryItem(name: "redirect_uri", value: DriveConfig.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: DriveConfig.scope),
                URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ]
            guard let url = components.url else { throw DriveError.invalidResponse }

            let callback = try await authenticate(url: url)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw DriveError.auth(error == "access_denied" ? "Accès refusé." : "Google a refusé la connexion (\(error)).")
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                throw DriveError.cancelled
            }

            let json = try await tokenRequest([
                "client_id": DriveConfig.clientID,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": DriveConfig.redirectURI,
                "grant_type": "authorization_code"
            ])
            store(json)
            isSignedIn = true
            await loadEmail()
        } catch DriveError.cancelled {
            // Annulation volontaire : pas de message d'erreur
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        if let token = refreshToken {
            // Meilleur effort : on révoque l'accès côté Google
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("token=\(Self.encode(token))".utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        clearLocal()
    }

    private func clearLocal() {
        Keychain.delete(refreshKey)
        memoryRefreshToken = nil
        accessToken = nil
        accessExpiry = .distantPast
        UserDefaults.standard.removeObject(forKey: emailKey)
        email = nil
        isSignedIn = false
    }

    // MARK: - Jeton d'accès

    func validAccessToken() async throws -> String {
        if let accessToken, accessExpiry > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refresh = refreshToken else { throw DriveError.notSignedIn }
        do {
            let json = try await tokenRequest([
                "client_id": DriveConfig.clientID,
                "refresh_token": refresh,
                "grant_type": "refresh_token"
            ])
            store(json)
        } catch DriveError.notSignedIn {
            clearLocal()
            throw DriveError.notSignedIn
        }
        guard let accessToken else { throw DriveError.notSignedIn }
        return accessToken
    }

    private func store(_ json: [String: Any]) {
        if let token = json["access_token"] as? String {
            accessToken = token
            let lifetime = (json["expires_in"] as? Double) ?? 3600
            accessExpiry = Date().addingTimeInterval(lifetime)
        }
        if let refresh = json["refresh_token"] as? String {
            if !Keychain.save(refresh, for: refreshKey) {
                memoryRefreshToken = refresh
            }
        }
    }

    private func loadEmail() async {
        guard let token = try? await validAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let mail = json["email"] as? String
        else { return }
        email = mail
        UserDefaults.standard.set(mail, forKey: emailKey)
    }

    // MARK: - Requêtes

    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            params.map { "\($0.key)=\(Self.encode($0.value))" }.joined(separator: "&").utf8
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if (json["error"] as? String) == "invalid_grant" { throw DriveError.notSignedIn }
            throw DriveError.auth((json["error_description"] as? String) ?? "Connexion à Google impossible (\(status)).")
        }
        return json
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: DriveConfig.callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: DriveError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? DriveError.cancelled)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: DriveError.auth("Impossible d'ouvrir la fenêtre de connexion Google."))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
        }
    }

    // MARK: - Outils PKCE

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
