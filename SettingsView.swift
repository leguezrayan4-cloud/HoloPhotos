import SwiftUI

// Clés de réglages réinitialisables (on garde l'adresse du PC, le coffre et le compte)
enum AppSettings {
    static let resettableKeys = [
        "appearance", "hapticsEnabled",
        "lockApp", "autoRefresh", "trashRetentionDays",
        "columns", "sortOrder",
        "aiMode", "aiStyle", "showThinking", "quotaShowRemaining",
        "backupAuto", "backupWiFiOnly", "backupVideos", "backupQuality"
    ]

    static func resetAll() {
        for key in resettableKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        Label("Général", systemImage: "gearshape")
                    }

                    NavigationLink {
                        PhotosSettingsView()
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Sauvegarde Google Drive", systemImage: "icloud.and.arrow.up")
                    }

                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label("Intelligence artificielle", systemImage: "sparkles")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("À propos", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if auth.isSignedIn {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack(spacing: 12) {
                        AccountAvatar(initials: auth.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.displayName).font(.headline)
                            Text(auth.email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Button {
                    showAuth = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Se connecter ou créer un compte")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Optionnel")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Général

struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("hapticsEnabled") private var haptics = true
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("lockApp") private var lockApp = false
    @AppStorage("trashRetentionDays") private var retention = 30
    @AppStorage("onboardingDone") private var onboardingDone = true

    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                Picker("Thème", selection: $appearance) {
                    Text("Automatique").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
            } header: {
                Text("Apparence")
            } footer: {
                Text("Automatique suit le réglage de ton iPhone.")
            }

            Section {
                Toggle("Retours haptiques", isOn: $haptics)
            } footer: {
                Text("Petites vibrations lors des actions : favori, suppression, sélection…")
            }

            Section {
                Toggle("Verrouiller HoloPhotos", isOn: $lockApp)
            } header: {
                Text("Sécurité")
            } footer: {
                Text("L'app demande Face ID ou le code du téléphone à chaque ouverture et après être restée en arrière-plan.")
            }

            Section {
                Toggle("Mise à jour automatique", isOn: $autoRefresh)
            } footer: {
                Text("La galerie se met à jour dès qu'une photo ou une vidéo est ajoutée, modifiée ou supprimée.")
            }

            Section {
                Picker("Suppression définitive", selection: $retention) {
                    Text("Après 7 jours").tag(7)
                    Text("Après 14 jours").tag(14)
                    Text("Après 30 jours").tag(30)
                    Text("Après 60 jours").tag(60)
                    Text("Après 90 jours").tag(90)
                    Text("Jamais").tag(0)
                }
            } header: {
                Text("Supprimés récemment")
            } footer: {
                Text("Délai avant que les photos et vidéos supprimées soient effacées pour de bon. L'effacement définitif est confirmé par iOS à l'ouverture de l'app.")
            }

            Section {
                Button("Revoir l'introduction") {
                    onboardingDone = false
                }
                Button("Réinitialiser les réglages", role: .destructive) {
                    confirmReset = true
                }
            } header: {
                Text("Avancé")
            }
        }
        .navigationTitle("Général")
        .confirmationDialog("Réinitialiser les réglages ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Réinitialiser", role: .destructive) {
                AppSettings.resetAll()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les réglages reviennent à leurs valeurs par défaut. Ton compte, ton album privé et l'adresse de ton PC sont conservés.")
        }
    }
}

// MARK: - Photos

struct PhotosSettingsView: View {
    @AppStorage("columns") private var columns = 4
    @AppStorage("sortOrder") private var sortOrder = "newest"

    var body: some View {
        List {
            Section {
                Picker("Photos par ligne", selection: $columns) {
                    ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                }
            } footer: {
                Text("Tu peux aussi pincer l'écran dans la galerie pour changer ce nombre.")
            }

            Section {
                Picker("Ordre", selection: $sortOrder) {
                    Text("Plus récentes d'abord").tag("newest")
                    Text("Plus anciennes d'abord").tag("oldest")
                    Text("Modifiées récemment").tag("modified")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Tri de la galerie")
            }
        }
        .navigationTitle("Photos")
    }
}

// MARK: - IA

struct AISettingsView: View {
    @AppStorage("aiMode") private var aiMode = "suggestion"
    @AppStorage("aiStyle") private var aiStyle = "concise"
    @AppStorage("quotaShowRemaining") private var showRemaining = false
    @AppStorage("showThinking") private var showThinking = true
    private var host: String { ServerConfig.ollamaHost }
    private var model: String { ServerConfig.ollamaModel }

    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        List {
            Section {
                LabeledContent("Adresse", value: host)
                LabeledContent("Modèle", value: model)
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Tester la connexion")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing)
                if let testResult {
                    Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(testResult.ok ? .green : .red)
                        .font(.footnote)
                }
            } header: {
                Text("Serveur Ollama (ton PC)")
            } footer: {
                Text("Ollama doit tourner sur ton PC et accepter les connexions du réseau. Laisse l'adresse vide pour désactiver ce mode.")
            }

            Section {
                Picker("Style des réponses", selection: $aiStyle) {
                    Text("Concis").tag("concise")
                    Text("Détaillé").tag("detailed")
                }
                Toggle("Afficher la réflexion de l'IA", isOn: $showThinking)
            } header: {
                Text("Réponses")
            } footer: {
                Text("La réflexion montre les étapes du modèle quand il les fournit. Si le modèle ne les gère pas, cette option est ignorée.")
            }

            Section {
                Picker("Mode", selection: $aiMode) {
                    Text("Suggestion").tag("suggestion")
                    Text("Automatique").tag("automatic")
                }
            } footer: {
                Text("Suggestion : l'IA propose, tu valides. Automatique : l'IA range seule, uniquement quand l'app est ouverte.")
            }

            Section {
                Toggle("Afficher le restant plutôt que l'utilisé", isOn: $showRemaining)
            } header: {
                Text("Quota")
            } footer: {
                Text("Le cercle se remplit avec les messages utilisés. Ce réglage change seulement le pourcentage affiché.")
            }
        }
        .navigationTitle("Intelligence artificielle")
    }

    // Interroge /api/tags d'Ollama : vérifie l'adresse et la présence du modèle
    private func testConnection() async {
        var base = host.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else {
            testResult = (false, "Renseigne d'abord l'adresse de ton PC.")
            return
        }
        if !base.hasPrefix("http") { base = "http://" + base }
        guard let url = URL(string: base + "/api/tags") else {
            testResult = (false, "L'adresse est invalide.")
            return
        }

        testing = true
        testResult = nil
        defer { testing = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                testResult = (false, "Ton PC a répondu avec une erreur.")
                return
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let names = (json?["models"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let wanted = model.trimmingCharacters(in: .whitespaces)
            let found = names.contains { $0 == wanted || $0 == wanted + ":latest" || $0.hasPrefix(wanted + ":") }
            if found {
                testResult = (true, "Connecté. Le modèle « \(wanted) » est disponible.")
            } else {
                testResult = (false, "Connecté, mais le modèle « \(wanted) » est introuvable sur ton PC.")
            }
        } catch {
            testResult = (false, "Impossible de joindre ton PC. Vérifie l'adresse et le Wi-Fi.")
        }
    }
}

// MARK: - À propos

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            LabeledContent("Version", value: version)
            LabeledContent("Build", value: build)
        }
        .navigationTitle("À propos")
    }
}
