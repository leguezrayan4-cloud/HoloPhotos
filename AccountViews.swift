import AuthenticationServices
import SwiftUI

// MARK: - Connexion / inscription

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case signUp = "Inscription"
        case signIn = "Connexion"
        var id: String { rawValue }
    }

    private enum Field: Hashable {
        case name, email, password, confirm
    }

    @State private var mode: Mode = .signUp
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var showForgot = false
    @State private var forgotEmail = ""
    @FocusState private var focus: Field?

    // Coordinator Apple Sign-In (doit rester en vie pendant le flow)
    @State private var appleCoordinator: AppleSignInCoordinator?

    private var isSignUp: Bool { mode == .signUp }

    private var validationHint: String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, !(trimmed.contains("@") && trimmed.contains(".")) {
            return "L'adresse e-mail ne semble pas valide."
        }
        if isSignUp, !password.isEmpty, password.count < 6 {
            return "Le mot de passe doit contenir au moins 6 caractères."
        }
        if isSignUp, !confirm.isEmpty, confirm != password {
            return "Les mots de passe ne correspondent pas."
        }
        return nil
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), trimmed.contains("."), !password.isEmpty else { return false }
        if isSignUp {
            return password.count >= 6 && confirm == password
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.isConfigured {
                    form
                } else {
                    notConfigured
                }
            }
            .navigationTitle(isSignUp ? "Créer un compte" : "Se connecter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Mot de passe oublié", isPresented: $showForgot) {
                TextField("Adresse e-mail", text: $forgotEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Envoyer") {
                    Task { _ = await auth.resetPassword(email: forgotEmail) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Entre ton adresse : tu recevras un lien pour choisir un nouveau mot de passe.")
            }
        }
        .onAppear { auth.clearMessages() }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .onChange(of: mode) { _, _ in auth.clearMessages() }
            }

            Section {
                if isSignUp {
                    TextField("Prénom ou pseudo", text: $name)
                        .textContentType(.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                }
                TextField("Adresse e-mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Mot de passe", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .focused($focus, equals: .password)
                    .submitLabel(isSignUp ? .next : .go)
                    .onSubmit {
                        if isSignUp { focus = .confirm } else { submit() }
                    }
                if isSignUp {
                    SecureField("Confirmer le mot de passe", text: $confirm)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                }
            } footer: {
                if let hint = validationHint {
                    Text(hint).foregroundStyle(.orange)
                } else if isSignUp {
                    Text("Ton compte sert à t'identifier dans l'app. Tes photos restent sur ton téléphone.")
                }
            }

            if let error = auth.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let info = auth.infoMessage {
                Section {
                    Label(info, systemImage: "envelope.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if auth.isBusy {
                            ProgressView()
                        } else {
                            Text(isSignUp ? "Créer mon compte" : "Me connecter")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || auth.isBusy)

                if !isSignUp {
                    Button("Mot de passe oublié ?") {
                        forgotEmail = email
                        showForgot = true
                    }
                    .font(.footnote)
                }
            }

            Section {
                // ── Séparateur « ou »
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("ou").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)

                // ── Bouton Google
                Button {
                    Task {
                        let ok = await auth.signInWithGoogle()
                        if ok { Haptics.success(); dismiss() }
                    }
                } label: {
                    Label {
                        Text("Continuer avec Google")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    } icon: {
                        Image("google-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(SocialButtonStyle(foreground: .primary, background: Color(.systemBackground), border: Color.secondary.opacity(0.4)))
                .disabled(auth.isBusy)

                // ── Bouton Apple
                Button {
                    let coordinator = AppleSignInCoordinator(auth: auth) {
                        Haptics.success()
                        dismiss()
                    }
                    appleCoordinator = coordinator
                    coordinator.start()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                        Text("Continuer avec Apple")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(SocialButtonStyle(foreground: .primary, background: Color(.systemBackground), border: Color.secondary.opacity(0.4)))
                .disabled(auth.isBusy)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var notConfigured: some View {
        ContentUnavailableView {
            Label("Comptes indisponibles", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Firebase n'est pas encore configuré dans cette version. Ajoute le fichier GoogleService-Info.plist au projet, puis recompile l'app.")
        }
    }

    private func submit() {
        guard canSubmit, !auth.isBusy else { return }
        focus = nil
        Task {
            let ok: Bool
            if isSignUp {
                ok = await auth.signUp(name: name, email: email, password: password)
            } else {
                ok = await auth.signIn(email: email, password: password)
            }
            if ok {
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - Apple Sign-In Coordinator

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let auth: AuthStore
    private let onSuccess: () -> Void

    init(auth: AuthStore, onSuccess: @escaping () -> Void) {
        self.auth = auth
        self.onSuccess = onSuccess
    }

    func start() {
        let hashedNonce = auth.prepareAppleSignIn()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        Task { @MainActor in
            let ok = await auth.signInWithApple(credential: credential)
            if ok { onSuccess() }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        let nsError = error as NSError
        guard nsError.code != ASAuthorizationError.canceled.rawValue else { return }
        Task { @MainActor in
            auth.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Style bouton social (Google, etc.)

struct SocialButtonStyle: ButtonStyle {
    var foreground: Color
    var background: Color
    var border: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(background)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Ligne « Compte » dans les Réglages

struct AccountAvatar: View {
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.purple.gradient))
    }
}

// MARK: - Gestion du compte

struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var askPassword = false
    @State private var passwordDraft = ""
    @State private var showResetSent = false
    @State private var showAddPassword = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AccountAvatar(initials: auth.initials, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.displayName).font(.headline)
                        Text(auth.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    nameDraft = auth.user?.displayName ?? ""
                    showRename = true
                } label: {
                    Label("Modifier le nom", systemImage: "pencil")
                }

                if auth.hasPasswordProvider {
                    HStack {
                        Label(
                            auth.isEmailVerified ? "E-mail vérifié" : "E-mail non vérifié",
                            systemImage: auth.isEmailVerified ? "checkmark.seal.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(auth.isEmailVerified ? .green : .orange)
                        Spacer()
                        if !auth.isEmailVerified {
                            Button("Renvoyer") {
                                Task { await auth.sendVerification() }
                            }
                            .font(.footnote)
                            .buttonStyle(.bordered)
                        }
                    }

                    Button {
                        Task {
                            if await auth.resetPassword(email: auth.email) {
                                showResetSent = true
                            }
                        }
                    } label: {
                        Label("Changer le mot de passe", systemImage: "key")
                    }
                } else {
                    Label(
                        auth.hasGoogleProvider ? "Connecté avec Google" : "Connecté avec Apple",
                        systemImage: "person.crop.circle"
                    )
                    .foregroundStyle(.secondary)

                    Button {
                        newPassword = ""
                        confirmPassword = ""
                        showAddPassword = true
                    } label: {
                        Label("Ajouter un mot de passe", systemImage: "key.fill")
                    }
                }
            } header: {
                Text("Profil")
            } footer: {
                Text("Pour changer ton mot de passe, on t'envoie un lien par e-mail.")
            }

            if let error = auth.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let info = auth.infoMessage {
                Section {
                    Label(info, systemImage: "envelope.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Supprimer mon compte", systemImage: "trash")
                }
            } footer: {
                Text("Supprime définitivement ton compte. Tes photos et vidéos ne sont pas touchées.")
            }
        }
        .navigationTitle("Compte")
        .navigationBarTitleDisplayMode(.inline)
        .task { await auth.reload() }
        .onAppear { auth.clearMessages() }
        // Quand le compte disparaît (déconnexion ou suppression), on revient aux Réglages
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn { dismiss() }
        }
        .overlay {
            if auth.isBusy { ProgressView() }
        }
        .alert("Modifier le nom", isPresented: $showRename) {
            TextField("Prénom ou pseudo", text: $nameDraft)
            Button("Enregistrer") {
                Task { await auth.updateName(nameDraft) }
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("E-mail envoyé", isPresented: $showResetSent) {
            Button("OK") {}
        } message: {
            Text("Vérifie ta boîte mail pour choisir un nouveau mot de passe.")
        }
        .confirmationDialog("Se déconnecter ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                auth.signOut()
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer ton compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                Task { await delete(password: nil) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est irréversible.")
        }
        .alert("Ajouter un mot de passe", isPresented: $showAddPassword) {
            SecureField("Mot de passe (6 caractères min.)", text: $newPassword)
            SecureField("Confirme le mot de passe", text: $confirmPassword)
            Button("Enregistrer") {
                let password = newPassword
                let confirm = confirmPassword
                newPassword = ""
                confirmPassword = ""
                guard password.count >= 6 else {
                    auth.errorMessage = "Le mot de passe doit contenir au moins 6 caractères."
                    return
                }
                guard password == confirm else {
                    auth.errorMessage = "Les mots de passe ne correspondent pas."
                    return
                }
                Task { _ = await auth.addPassword(password) }
            }
            Button("Annuler", role: .cancel) {
                newPassword = ""
                confirmPassword = ""
            }
        } message: {
            Text("Tu pourras ensuite te connecter avec ton adresse e-mail.")
        }
        .alert("Confirme ton mot de passe", isPresented: $askPassword) {
            SecureField("Mot de passe", text: $passwordDraft)
            Button("Supprimer", role: .destructive) {
                let password = passwordDraft
                passwordDraft = ""
                Task { await delete(password: password) }
            }
            Button("Annuler", role: .cancel) { passwordDraft = "" }
        } message: {
            Text("Pour supprimer ton compte, saisis à nouveau ton mot de passe.")
        }
    }

    private func delete(password: String?) async {
        switch await auth.deleteAccount(password: password) {
        case .done:
            Haptics.success()
        case .needsPassword:
            askPassword = true
        case .failed:
            break
        }
    }
}

// Pseudo demandé après une première connexion Google ou Apple
struct NameSetupView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ton pseudo", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Comment tu t'appelles ?")
                } footer: {
                    Text("Ce nom s'affichera dans ton compte. Tu pourras le changer plus tard.")
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Bienvenue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continuer") {
                        Task { _ = await auth.saveName(name) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || auth.isBusy)
                }
            }
            .onAppear {
                if name.isEmpty { name = auth.user?.displayName ?? "" }
            }
            .interactiveDismissDisabled()
        }
    }
}
