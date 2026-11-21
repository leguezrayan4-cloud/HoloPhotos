import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        Label("Général", systemImage: "gearshape")
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
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("lockApp") private var lockApp = false
    @AppStorage("trashRetentionDays") private var retention = 30

    var body: some View {
        List {
            Section {
                Toggle("Verrouiller HoloPhotos", isOn: $lockApp)
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
        }
        .navigationTitle("Général")
    }
}

struct AISettingsView: View {
    @AppStorage("aiMode") private var aiMode = "suggestion"
    @AppStorage("quotaShowRemaining") private var showRemaining = false
    @AppStorage("showThinking") private var showThinking = true

    var body: some View {
        List {
            Section {
                Toggle("Afficher la réflexion de l'IA", isOn: $showThinking)
            } footer: {
                Text("Montre les étapes de réflexion quand le modèle les fournit. Si le modèle ne les gère pas, cette option est ignorée.")
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
}

struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("Version", value: "6")
        }
        .navigationTitle("À propos")
    }
}
