import FirebaseAuth
import FirebaseCore
import SwiftUI

enum DeleteOutcome {
    case done
    case needsPassword
    case failed
}

// Compte utilisateur (Firebase Auth, e-mail + mot de passe).
// Le compte est optionnel : l'app reste utilisable sans être connecté.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    // false tant que GoogleService-Info.plist n'est pas ajouté au projet
    let isConfigured: Bool
    private var handle: AuthStateDidChangeListenerHandle?

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

    var isEmailVerified: Bool { user?.isEmailVerified ?? false }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async -> Bool {
        await run {
            _ = try await Auth.auth().signIn(
                withEmail: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
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

    func signOut() {
        do {
            try Auth.auth().signOut()
            clearMessages()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func updateName(_ name: String) async {
        guard let user else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        _ = await run {
            let change = user.createProfileChangeRequest()
            change.displayName = trimmed
            try await change.commitChanges()
            self.objectWillChange.send()
        }
    }

    func sendVerification() async {
        guard let user else { return }
        let ok = await run {
            try await user.sendEmailVerification()
        }
        if ok { infoMessage = "E-mail de vérification envoyé à \(user.email ?? "ton adresse")." }
    }

    // Met à jour l'état (par exemple après avoir cliqué sur le lien de vérification)
    func reload() async {
        guard let user else { return }
        try? await user.reload()
        self.user = Auth.auth().currentUser
        objectWillChange.send()
    }

    // Supprime le compte. iOS/Firebase exige une connexion récente : dans ce cas
    // on renvoie .needsPassword, puis on rappelle avec le mot de passe.
    func deleteAccount(password: String?) async -> DeleteOutcome {
        guard let user, let email = user.email else { return .failed }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if let password {
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                try await user.reauthenticate(with: credential)
            }
            try await user.delete()
            return .done
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            if code == .requiresRecentLogin && password == nil {
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

    // Messages d'erreur Firebase traduits
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return "Une erreur est survenue. Réessaie dans un instant."
        }
        switch code {
        case .invalidEmail:
            return "L'adresse e-mail n'est pas valide."
        case .emailAlreadyInUse:
            return "Un compte existe déjà avec cette adresse. Connecte-toi plutôt."
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
            return "La connexion par e-mail n'est pas activée dans Firebase."
        case .missingEmail:
            return "Renseigne ton adresse e-mail."
        case .keychainError:
            return "iOS refuse l'accès au trousseau. Cela arrive avec certaines installations hors App Store."
        default:
            return "Une erreur est survenue (\(nsError.code)). Réessaie dans un instant."
        }
    }
}
