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
                NavigationLink {
                    GridSettingsView()
                } label: {
                    Text("Taille des vignettes")
                }
            } footer: {
                Text("La galerie se met à jour dès qu'une photo ou une vidéo est ajoutée, modifiée ou supprimée.")
            }
        }
        .navigationTitle("Général")
    }
}

struct GridSettingsView: View {
    @AppStorage("gridSize") private var gridSize = 100

    var body: some View {
        List {
            Picker("Taille", selection: $gridSize) {
                Text("Petite").tag(80)
                Text("Moyenne").tag(100)
                Text("Grande").tag(130)
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Vignettes")
    }
}

struct AISettingsView: View {
    @AppStorage("aiMode") private var aiMode = "suggestion"
    @AppStorage("ollamaHost") private var ollamaHost = ""

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
                TextField("Adresse de ton PC, ex. 192.168.1.20:11434", text: $ollamaHost)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Serveur local (Ollama)")
            } footer: {
                Text("Laisse vide pour n'utiliser que les étiquettes d'Apple.")
            }
        }
        .navigationTitle("Intelligence artificielle")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("Version", value: "4")
        }
        .navigationTitle("À propos")
    }
}
