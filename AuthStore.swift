import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

enum DeleteOutcome {
    case done
    case needsPassword
    case failed
}

// Erreur d'un flux d'authentification, avec un message prêt à afficher
enum AuthFlowError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

// Compte utilisateur (Firebase Auth : e-mail + mot de passe, Google, Apple).
// Le compte est optionnel : l'app reste utilisable sans être connecté.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    // Affiché après une première connexion Google ou Apple, pour demander le pseudo
    @Published var needsName = false

    // false tant que GoogleService-Info.plist n'est pas ajouté au projet
    let isConfigured: Bool
    private var handle: AuthStateDidChangeListenerHandle?

    // Nonce utilisé pour la connexion Apple
    private var currentNonce: String?

    // Connexion Google/Apple refusée parce qu'un compte e-mail existe déjà : on la garde pour la lier
    private var pendingCredential: AuthCredential?
    private var pendingEmail: String?

    init() {
        // FirebaseApp.configure() plante sans le fichier plist : on le vérifie avant
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        isConfigured = FirebaseApp.app() != nil
        guard isConfigured else { return }

        user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, newUser in
            Task { @MainActor in
                self?.user = newUser
            }
        }
    }

    // MARK: - État

    var isSignedIn: Bool { user != nil }

    var email: String { user?.email ?? "" }

    var displayName: String {
        let name = user?.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !name.isEmpty { return name }
        return email.split(separator: "@").first.map(String.init) ?? "Compte"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    // Le compte a un mot de passe (e-mail) : seul cas où « changer le mot de passe » a un sens
    var hasPasswordProvider: Bool {
        user?.providerData.contains { $0.providerID == "password" } ?? false
    }

    var hasGoogleProvider: Bool {
        user?.providerData.contains { $0.providerID == "google.com" } ?? false
    }

    var hasAppleProvider: Bool {
        user?.providerData.contains { $0.providerID == "apple.com" } ?? false
    }

    var isEmailVerified: Bool { user?.isEmailVerified ?? false }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - E-mail et mot de passe

    func signIn(email: String, password: String) async -> Bool {
        await run {
            let result = try await Auth.auth().signIn(
                withEmail: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            try await self.linkPendingCredential(to: result.user)
        }
    }

    func signUp(name: String, email: String, password: String) async -> Bool {
        await run {
            let result = try await Auth.auth().createUser(
                withEmail: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = trimmed
                try await change.commitChanges()
            }
            // Pas bloquant : le compte est créé même si l'e-mail de vérification échoue
            try? await result.user.sendEmailVerification()
            self.user = Auth.auth().currentUser
            self.objectWillChange.send()
        }
    }

    func resetPassword(email: String) async -> Bool {
        let target = email.trimmingCharacters(in: .whitespaces)
        let ok = await run {
            try await Auth.auth().sendPasswordReset(withEmail: target)
        }
        if ok {
            infoMessage = "Si un compte existe pour \(target), un e-mail de réinitialisation vient d'être envoyé."
        }
        return ok
    }

    // Ajoute un mot de passe à un compte créé avec Google ou Apple
    func addPassword(_ password: String) async -> Bool {
        guard let current = Auth.auth().currentUser, let mail = current.email else {
            errorMessage = "Aucune adresse e-mail n'est associée à ce compte."
            return false
        }
        return await run {
            let credential = EmailAuthProvider.credential(withEmail: mail, password: password)
            try await current.link(with: credential)
            self.user = Auth.auth().currentUser
            self.objectWillChange.send()
            self.infoMessage = "Mot de passe ajouté. Tu peux maintenant te connecter avec ton e-mail."
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            pendingCredential = nil
            pendingEmail = nil
            clearMessages()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: - Google

    func signInWithGoogle() async -> Bool {
        guard isConfigured else {
            errorMessage = "Les comptes ne sont pas encore configurés dans cette version de l'app."
            return false
        }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            let (credential, mail) = try await googleCredential()
            try await connect(with: credential, email: mail)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    // Demande un identifiant Google et renvoie le credential Firebase + l'e-mail Google
    private func googleCredential() async throws -> (AuthCredential, String?) {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            throw AuthFlowError.message("Configuration Google manquante (CLIENT_ID introuvable dans GoogleService-Info.plist).")
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw AuthFlowError.message("Impossible d'ouvrir la fenêtre de connexion.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthFlowError.message("Token Google introuvable.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return (credential, result.user.profile?.email)
    }

    // Ré-authentification Google (suppression de compte)
    private func reauthenticateWithGoogle() async throws {
        guard let current = Auth.auth().currentUser else {
            throw AuthFlowError.message("Ta session a expiré. Reconnecte-toi.")
        }
        let (credential, _) = try await googleCredential()
        try await current.reauthenticate(with: credential)
    }

    // MARK: - Apple

    /// Génère un nonce aléatoire sécurisé et le stocke pour vérification.
    func prepareAppleSignIn() -> String {
        let nonce = randomNonce()
        currentNonce = nonce
        return sha256(nonce)
    }

    /// À appeler depuis le completion handler d'ASAuthorizationController.
    func signInWithApple(credential appleCredential: ASAuthorizationAppleIDCredential) async -> Bool {
        guard isConfigured else {
            errorMessage = "Les comptes ne sont pas encore configurés dans cette version de l'app."
            return false
        }
        guard let nonce = currentNonce else {
            errorMessage = "Connexion Apple non initialisée."
            return false
        }
        guard let appleIDToken = appleCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            errorMessage = "Token Apple introuvable."
            return false
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        // Apple ne renvoie l'e-mail que la première fois : sans lui, pas de contrôle de doublon
        let mail = appleCredential.email
        do {
            isBusy = true
            errorMessage = nil
            infoMessage = nil
            defer { isBusy = false }
            try await connect(with: credential, email: mail)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - Liaison des comptes

    // Connecte avec un credential Google/Apple, en évitant de créer un second compte pour le même e-mail
    private func connect(with credential: AuthCredential, email: String?) async throws {
        if let mail = email, !mail.isEmpty {
            let methods = try await Auth.auth().fetchSignInMethods(forEmail: mail)
            if methods.contains("password") && !methods.contains(credential.provider) {
                pendingCredential = credential
                pendingEmail = mail
                GIDSignIn.sharedInstance.signOut()
                throw AuthFlowError.message(
                    "Un compte existe déjà avec \(mail). Connecte-toi avec ton mot de passe : \(providerLabel(credential.provider)) sera ajouté à ton compte automatiquement."
                )
            }
        }
        let result = try await Auth.auth().signIn(with: credential)
        if result.additionalUserInfo?.isNewUser == true {
            needsName = true
        }
    }

    // Après une connexion par e-mail, lie le fournisseur mis de côté (Google ou Apple)
    private func linkPendingCredential(to signedInUser: User) async throws {
        guard let credential = pendingCredential,
              let mail = pendingEmail,
              signedInUser.email?.lowercased() == mail.lowercased() else { return }
        pendingCredential = nil
        pendingEmail = nil
        try await signedInUser.link(with: credential)
        self.user = Auth.auth().currentUser
        infoMessage = "Ton compte est maintenant lié à \(providerLabel(credential.provider))."
    }

    private func providerLabel(_ providerID: String) -> String {
        providerID == "apple.com" ? "Apple" : "Google"
    }

    // MARK: - Profil

    // Enregistre le pseudo demandé après une première connexion
    func saveName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Choisis un pseudo pour continuer."
            return false
        }
        let ok = await updateNameReturningResult(trimmed)
        if ok { needsName = false }
        return ok
    }

    func updateName(_ name: String) async {
        _ = await updateNameReturningResult(name.trimmingCharacters(in: .whitespaces))
    }

    private func updateNameReturningResult(_ trimmed: String) async -> Bool {
        guard let current = Auth.auth().currentUser else { return false }
        return await run {
            let change = current.createProfileChangeRequest()
            change.displayName = trimmed
            try await change.commitChanges()
            self.user = Auth.auth().currentUser
            self.objectWillChange.send()
        }
    }

    func sendVerification() async {
        guard let current = Auth.auth().currentUser else { return }
        let ok = await run {
            try await current.sendEmailVerification()
        }
        if ok { infoMessage = "E-mail de vérification envoyé à \(current.email ?? "ton adresse")." }
    }

    // Met à jour l'état (par exemple après avoir cliqué sur le lien de vérification)
    func reload() async {
        guard let current = Auth.auth().currentUser else { return }
        try? await current.reload()
        self.user = Auth.auth().currentUser
        objectWillChange.send()
    }

    // Supprime le compte. Firebase exige une connexion récente :
    // - compte e-mail : on demande le mot de passe (.needsPassword) puis on le réutilise ;
    // - compte Google : on refait la connexion Google avant de supprimer ;
    // - compte Apple : suppression directe, à défaut on demande de se reconnecter.
    func deleteAccount(password: String?) async -> DeleteOutcome {
        guard let current = Auth.auth().currentUser else { return .failed }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if hasPasswordProvider {
                if let password, let mail = current.email {
                    let credential = EmailAuthProvider.credential(withEmail: mail, password: password)
                    try await current.reauthenticate(with: credential)
                }
            } else if hasGoogleProvider {
                try await reauthenticateWithGoogle()
            }
            try await current.delete()
            return .done
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            if code == .requiresRecentLogin && hasPasswordProvider && password == nil {
                return .needsPassword
            }
            errorMessage = Self.message(for: error)
            return .failed
        }
    }

    // MARK: - Outils

    private func run(_ work: () async throws -> Void) async -> Bool {
        guard isConfigured else {
            errorMessage = "Les comptes ne sont pas encore configurés dans cette version de l'app."
            return false
        }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    // Messages d'erreur Firebase traduits
    static func message(for error: Error) -> String {
        if let flow = error as? AuthFlowError {
            return flow.errorDescription ?? "Une erreur est survenue."
        }
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return "Une erreur est survenue. Réessaie dans un instant."
        }
        switch code {
        case .invalidEmail:
            return "L'adresse e-mail n'est pas valide."
        case .emailAlreadyInUse:
            return "Un compte existe déjà avec cette adresse. Connecte-toi plutôt."
        case .accountExistsWithDifferentCredential:
            return "Un compte existe déjà avec cette adresse, avec une autre méthode de connexion."
        case .weakPassword:
            return "Mot de passe trop faible : utilise au moins 6 caractères."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "E-mail ou mot de passe incorrect."
        case .userDisabled:
            return "Ce compte a été désactivé."
        case .tooManyRequests:
            return "Trop de tentatives. Réessaie dans quelques minutes."
        case .networkError:
            return "Pas de connexion à Internet."
        case .requiresRecentLogin:
            return "Pour des raisons de sécurité, reconnecte-toi puis réessaie."
        case .operationNotAllowed:
            return "Ce mode de connexion n'est pas activé dans Firebase."
        case .missingEmail:
            return "Renseigne ton adresse e-mail."
        case .keychainError:
            return "iOS refuse l'accès au trousseau. Cela arrive avec certaines installations hors App Store."
        default:
            return "Une erreur est survenue (\(nsError.code)). Réessaie dans un instant."
        }
    }
}
