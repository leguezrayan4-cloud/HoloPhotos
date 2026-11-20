import SwiftUI

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    var content: String
}

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
}

final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = [] {
        didSet { save() }
    }
    @Published var currentID: UUID?
    private let key = "conversations"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
        }
        currentID = conversations.first?.id
    }

    var current: Conversation? {
        conversations.first { $0.id == currentID }
    }

    func newConversation() {
        let conv = Conversation(title: "Nouvelle conversation")
        conversations.insert(conv, at: 0)
        currentID = conv.id
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { conversations[i].title = trimmed }
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentID == id { currentID = conversations.first?.id }
    }

    func append(_ message: ChatMessage, to id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].messages.append(message)
        if conversations[i].title == "Nouvelle conversation", message.role == "user" {
            conversations[i].title = String(message.content.prefix(30))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct ModelOption: Identifiable {
    let id: String
    let name: String
}

struct Provider: Identifiable {
    let id: String
    let name: String
    let models: [ModelOption]
}

let providers: [Provider] = [
    Provider(id: "ollama", name: "Ollama (PC local)", models: [
        ModelOption(id: "ollama:auto", name: "Automatique"),
        ModelOption(id: "ollama:llama3.2", name: "Llama 3.2"),
        ModelOption(id: "ollama:llava", name: "LLaVA (vision)")
    ]),
    Provider(id: "claude", name: "Claude", models: [
        ModelOption(id: "claude:claude-opus-5-5", name: "Claude Opus 5.5"),
        ModelOption(id: "claude:claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        ModelOption(id: "claude:claude-haiku-5-5", name: "Claude Haiku 5.5")
    ]),
    Provider(id: "chatgpt", name: "ChatGPT", models: [
        ModelOption(id: "chatgpt:gpt-4o", name: "GPT-4o"),
        ModelOption(id: "chatgpt:gpt-4o-mini", name: "GPT-4o mini")
    ]),
    Provider(id: "gemini", name: "Gemini", models: [
        ModelOption(id: "gemini:gemini-2.0-flash", name: "Gemini 2.0 Flash"),
        ModelOption(id: "gemini:gemini-1.5-pro", name: "Gemini 1.5 Pro")
    ]),
    Provider(id: "mistral", name: "Mistral", models: [
        ModelOption(id: "mistral:mistral-large", name: "Mistral Large"),
        ModelOption(id: "mistral:pixtral", name: "Pixtral (vision)")
    ])
]

struct AIView: View {
    @StateObject private var chats = ChatStore()
    @StateObject private var quota = QuotaStore()
    @AppStorage("modelChoice") private var modelChoice = "auto"
    @AppStorage("ollamaHost") private var ollamaHost = ""
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("quotaShowRemaining") private var showRemaining = false

    @State private var draft = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var showHistory = false
    @State private var showModels = false
    @State private var showOllama = false
    @State private var showQuota = false
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelBar
                Divider()
                messages
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                inputBar
            }
            .navigationTitle(chats.current?.title ?? "IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        quotaIndicator
                        Menu {
                            Button { chats.newConversation() } label: {
                                Label("Nouvelle conversation", systemImage: "square.and.pencil")
                            }
                            Button {
                                renameText = chats.current?.title ?? ""
                                showRename = true
                            } label: {
                                Label("Renommer", systemImage: "pencil")
                            }
                            Button { showOllama = true } label: {
                                Label("Serveur Ollama", systemImage: "desktopcomputer")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Renommer", isPresented: $showRename) {
                TextField("Nom", text: $renameText)
                Button("Enregistrer") {
                    if let id = chats.currentID {
                        chats.rename(id, to: renameText)
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .alert("Quota IA", isPresented: $showQuota) {
                Button("OK") {}
            } message: {
                Text("Utilisés : \(quota.used) sur \(QuotaStore.monthlyLimit).\nRestants : \(quota.remaining). Remis à zéro chaque mois.")
            }
            .sheet(isPresented: $showHistory) {
                HistorySheet(chats: chats)
            }
            .sheet(isPresented: $showModels) {
                ModelPicker(selection: $modelChoice)
            }
            .sheet(isPresented: $showOllama) {
                OllamaSettingsView()
            }
        }
        .onAppear { quota.refreshMonth() }
    }

    private var modelBar: some View {
        Button { showModels = true } label: {
            HStack {
                Text("Modèle : \(modelLabel)")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
            }
            .padding()
            .foregroundStyle(.primary)
        }
    }

    private var quotaIndicator: some View {
        Button { showQuota = true } label: {
            HStack(spacing: 4) {
                QuotaRing(fraction: quota.fractionUsed)
                Text(quotaLabel)
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private var quotaLabel: String {
        let used = Int((quota.fractionUsed * 100).rounded())
        let shown = showRemaining ? 100 - used : used
        return "\(shown)%"
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chats.current?.messages.isEmpty ?? true {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 40))
                                .foregroundStyle(.purple)
                            Text("Pose une question sur ta galerie, demande une organisation, ou des actions sur tes photos.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }

                    ForEach(chats.current?.messages ?? []) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if sending {
                        ProgressView()
                            .padding(.leading)
                    }
                }
                .padding()
            }
            .onChange(of: chats.current?.messages.count) { _, _ in
                if let last = chats.current?.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 40)
            }
            Text(message.content)
                .padding(12)
                .background(message.role == "user" ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if message.role != "user" {
                Spacer(minLength: 40)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Écris un message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding()
    }

    // Automatique : Ollama si l'adresse du PC est renseignée, sinon rien
    private var resolvedChoice: String? {
        if modelChoice == "auto" {
            return ollamaHost.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "ollama:auto"
        }
        return modelChoice
    }

    private var modelLabel: String {
        if modelChoice == "auto" { return "Automatique" }
        for provider in providers {
            for model in provider.models where model.id == modelChoice {
                return model.name
            }
        }
        return "Choisir un modèle"
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        errorText = nil

        if chats.currentID == nil {
            chats.newConversation()
        }
        guard let convID = chats.currentID else { return }

        guard let choice = resolvedChoice else {
            errorText = "Aucun modèle disponible. Renseigne l'adresse de ton PC dans le menu, ou choisis un fournisseur."
            return
        }
        guard choice.hasPrefix("ollama:") else {
            errorText = "Ce fournisseur (clé API) arrive bientôt. Pour l'instant utilise Automatique ou Ollama sur ton PC."
            return
        }
        guard quota.remaining > 0 else {
            errorText = "Quota mensuel atteint. Il se remet à zéro le mois prochain."
            return
        }

        draft = ""
        chats.append(ChatMessage(role: "user", content: text), to: convID)
        quota.registerMessage()
        let history = chats.current?.messages ?? []
        sending = true

        let client = OllamaClient(host: ollamaHost, model: ollamaModel)
        Task { @MainActor in
            do {
                let reply = try await client.chat(messages: history)
                chats.append(ChatMessage(role: "assistant", content: reply), to: convID)
            } catch {
                errorText = "Ton PC ne répond pas. Vérifie qu'il est allumé et qu'Ollama tourne."
            }
            sending = false
        }
    }
}

struct QuotaRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
    }
}

struct HistorySheet: View {
    @ObservedObject var chats: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var renameID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(chats.conversations) { conv in
                    Button {
                        chats.currentID = conv.id
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .foregroundStyle(.primary)
                            Text("\(conv.messages.count) message(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            chats.delete(conv.id)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button {
                            renameID = conv.id
                            renameText = conv.title
                        } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Nouvelle") {
                        chats.newConversation()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
            .alert("Renommer", isPresented: Binding(
                get: { renameID != nil },
                set: { if !$0 { renameID = nil } }
            )) {
                TextField("Nom", text: $renameText)
                Button("Enregistrer") {
                    if let id = renameID {
                        chats.rename(id, to: renameText)
                    }
                    renameID = nil
                }
                Button("Annuler", role: .cancel) {
                    renameID = nil
                }
            }
        }
    }
}

struct ModelPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = "auto"
                        dismiss()
                    } label: {
                        HStack {
                            Text("Automatique")
                            Spacer()
                            if selection == "auto" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Choisit le modèle selon ton quota restant et la demande.")
                }

                Section("Fournisseurs") {
                    ForEach(providers) { provider in
                        NavigationLink {
                            ProviderModels(provider: provider, selection: $selection)
                        } label: {
                            Text(provider.name)
                        }
                    }
                }
            }
            .navigationTitle("Modèle")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

struct ProviderModels: View {
    let provider: Provider
    @Binding var selection: String

    var body: some View {
        List {
            if provider.models.isEmpty {
                Text("Bientôt disponible")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(provider.models) { model in
                    Button {
                        selection = model.id
                    } label: {
                        HStack {
                            Text(model.name)
                            Spacer()
                            if selection == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(provider.name)
    }
}

struct OllamaSettingsView: View {
    @AppStorage("ollamaHost") private var host = ""
    @AppStorage("ollamaModel") private var model = "llama3.2"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.20:11434", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nom du modèle", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Ton PC")
                } footer: {
                    Text("Ollama doit tourner sur ton PC et accepter les connexions du réseau. Laisse l'adresse vide pour désactiver ce mode.")
                }
            }
            .navigationTitle("Serveur Ollama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
