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

    var body: some View {
        List {
            Section {
                Toggle("Mise à jour automatique", isOn: $autoRefresh)
            } footer: {
                Text("La galerie se met à jour dès qu'une photo ou une vidéo est ajoutée, modifiée ou supprimée.")
            }
        }
        .navigationTitle("Général")
    }
}

struct AISettingsView: View {
    @AppStorage("aiMode") private var aiMode = "suggestion"
    @AppStorage("quotaShowRemaining") private var showRemaining = false

    var body: some View {
        List {
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
            LabeledContent("Version", value: "5")
        }
        .navigationTitle("À propos")
    }
}
