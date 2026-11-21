import PhotosUI
import SwiftUI

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    var content: String
    var thinking: String?
    var thinkingSeconds: Int?
}

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var pinned: Bool?
    var updatedAt: Date?

    var isPinned: Bool { pinned ?? false }
}

final class ChatStore: ObservableObject {
    static let defaultTitle = "Nouvelle conversation"

    @Published var conversations: [Conversation] = [] {
        didSet { scheduleSave() }
    }
    @Published var currentID: UUID?

    private let legacyKey = "conversations"
    private var saveWork: DispatchWorkItem?

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
        } else if let data = UserDefaults.standard.data(forKey: legacyKey),
                  let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
        }
        currentID = conversations.first?.id
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flush()
        }
    }

    var current: Conversation? {
        conversations.first { $0.id == currentID }
    }

    func messages(of id: UUID) -> [ChatMessage] {
        conversations.first { $0.id == id }?.messages ?? []
    }

    // Réutilise une conversation vide au lieu d'en empiler
    func newConversation() {
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            currentID = empty.id
            return
        }
        let conv = Conversation(title: Self.defaultTitle, updatedAt: Date())
        conversations.insert(conv, at: 0)
        currentID = conv.id
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { conversations[i].title = trimmed }
    }

    func togglePin(_ id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].pinned = !conversations[i].isPinned
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentID == id { currentID = conversations.first?.id }
    }

    func deleteAll() {
        conversations.removeAll()
        currentID = nil
    }

    func append(_ message: ChatMessage, to id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].messages.append(message)
        conversations[i].updatedAt = Date()
        if conversations[i].title == Self.defaultTitle, message.role == "user" {
            let oneLine = message.content.replacingOccurrences(of: "\n", with: " ")
            conversations[i].title = String(oneLine.prefix(40))
        }
    }

    func update(_ messageID: UUID, in convID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard
            let i = conversations.firstIndex(where: { $0.id == convID }),
            let j = conversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        change(&conversations[i].messages[j])
    }

    func remove(_ messageID: UUID, in convID: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == convID }) else { return }
        conversations[i].messages.removeAll { $0.id == messageID }
    }

    // Sauvegarde différée : évite d'écrire à chaque mot pendant le streaming
    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = conversations
        let url = Self.fileURL
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: Self.fileURL, options: .atomic)
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

enum GenPhase {
    case sending
    case thinking
    case writing
}

struct AIView: View {
    @StateObject private var chats = ChatStore()
    @StateObject private var quota = QuotaStore()
    @StateObject private var speech = SpeechRecognizer()
    @AppStorage("modelChoice") private var modelChoice = "auto"
    @AppStorage("ollamaHost") private var ollamaHost = ""
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("quotaShowRemaining") private var showRemaining = false
    @AppStorage("showThinking") private var showThinking = true
    @AppStorage("aiStyle") private var aiStyle = "concise"
    @FocusState private var inputFocused: Bool

    @State private var draft = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImages: [String] = []
    @State private var pendingPreviews: [UIImage] = []
    @State private var voiceBase = ""
    @State private var errorText: String?
    @State private var showHistory = false
    @State private var showModels = false
    @State private var showOllama = false
    @State private var showQuota = false
    @State private var showRename = false
    @State private var showDeleteChat = false
    @State private var renameText = ""

    @State private var generation: Task<Void, Never>?
    @State private var streamingID: UUID?
    @State private var phase: GenPhase = .sending
    @State private var thinkingStart: Date?
    @State private var rawBuffer = ""
    @State private var expandedThinking: Set<UUID> = []

    private var systemPrompt: String {
        let style = aiStyle == "detailed" ? "de façon détaillée et pédagogique" : "de façon claire et concise"
        return "Tu es l'assistant IA intégré à HoloPhotos, une application de galerie photo. Réponds en français, \(style). Tu n'as pas accès aux photos de l'utilisateur, sauf si elles sont décrites dans la conversation."
    }

    private let suggestions = [
        "Comment bien organiser ma galerie en albums ?",
        "Donne-moi des idées d'albums pour mes vacances",
        "Comment retrouver et supprimer mes doublons ?",
        "Aide-moi à écrire une légende pour une photo"
    ]

    private var messagesList: [ChatMessage] {
        chats.current?.messages ?? []
    }

    private var isGenerating: Bool {
        streamingID != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelBar
                Divider()
                messagesView
                if let errorText {
                    errorBanner(errorText)
                }
                inputBar
            }
            .navigationTitle(chats.current?.title ?? "IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
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
            .confirmationDialog("Supprimer cette conversation ?", isPresented: $showDeleteChat, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    stopGeneration()
                    if let id = chats.currentID {
                        chats.delete(id)
                    }
                }
            }
            .overlay {
                historyDrawer
            }
            .sheet(isPresented: $showModels) {
                ModelPicker(selection: $modelChoice)
            }
            .sheet(isPresented: $showOllama) {
                OllamaSettingsView()
            }
        }
        .onAppear { quota.refreshMonth() }
        .onChange(of: chats.currentID) { _, _ in
            stopGeneration()
            errorText = nil
        }
        .onChange(of: speech.transcript) { _, text in
            guard !text.isEmpty else { return }
            draft = voiceBase.isEmpty ? text : voiceBase + " " + text
        }
        .onChange(of: speech.errorMessage) { _, message in
            if let message { errorText = message }
        }
    }

    // MARK: - Barre du haut

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showHistory = true } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Conversations")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { newChat() } label: {
                Image(systemName: "square.and.pencil")
            }
            Menu {
                Button {
                    renameText = chats.current?.title ?? ""
                    showRename = true
                } label: {
                    Label("Renommer", systemImage: "pencil")
                }
                .disabled(chats.current == nil)

                Button {
                    if let id = chats.currentID { chats.togglePin(id) }
                } label: {
                    if chats.current?.isPinned == true {
                        Label("Désépingler", systemImage: "pin.slash")
                    } else {
                        Label("Épingler", systemImage: "pin")
                    }
                }
                .disabled(chats.current == nil)

                Button(role: .destructive) { showDeleteChat = true } label: {
                    Label("Supprimer la conversation", systemImage: "trash")
                }
                .disabled(chats.current == nil)

                Divider()

                Toggle(isOn: $showThinking) {
                    Label("Afficher la réflexion", systemImage: "brain")
                }

                Button { showOllama = true } label: {
                    Label("Serveur Ollama", systemImage: "desktopcomputer")
                }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Plus d’options")
            }
        }
    }

    private var modelBar: some View {
        Button { showModels = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text(modelLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Messages

    private var scrollSignature: String {
        let last = messagesList.last
        return "\(messagesList.count)-\(last?.content.count ?? 0)-\(last?.thinking?.count ?? 0)-\(phase)"
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messagesList.isEmpty {
                        emptyState
                    }

                    ForEach(messagesList) { message in
                        messageRow(message)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { inputFocused = false }
            .onChange(of: scrollSignature) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: chats.currentID) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.purple)
            Text("Comment puis-je t'aider ?")
                .font(.title3.weight(.semibold))
            Text("Pose une question sur ta galerie ou demande des idées d'organisation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.role == "user" {
            userBubble(message)
        } else {
            assistantRow(message)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .textSelection(.enabled)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .contextMenu {
            Button { UIPasteboard.general.string = message.content } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
        }
    }

    private func assistantRow(_ message: ChatMessage) -> some View {
        let streaming = message.id == streamingID
        return VStack(alignment: .leading, spacing: 10) {
            if streaming {
                liveActivity(message)
            } else if let thinking = message.thinking, !thinking.isEmpty {
                thinkingRow(message, live: false)
            }

            if !message.content.isEmpty {
                Text(rendered(message.content))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !streaming, !message.content.isEmpty {
                actionRow(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button { UIPasteboard.general.string = message.content } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
        }
    }

    private func actionRow(_ message: ChatMessage) -> some View {
        HStack(spacing: 18) {
            Button { UIPasteboard.general.string = message.content } label: {
                Image(systemName: "doc.on.doc").accessibilityLabel("Copier")
            }
            if message.id == messagesList.last?.id {
                Button { regenerate() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isGenerating)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func rendered(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Activité de l'IA

    private func liveActivity(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            stepRow(phase == .sending ? "Le modèle démarre…" : "Demande reçue par ton PC",
                    done: phase != .sending)

            if phase == .thinking || !(message.thinking ?? "").isEmpty {
                thinkingRow(message, live: true)
            }

            if phase == .writing {
                stepRow("Rédaction de la réponse…", done: false)
            }
        }
    }

    private func stepRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func thinkingRow(_ message: ChatMessage, live: Bool) -> some View {
        let expanded = expandedThinking.contains(message.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if expanded {
                    expandedThinking.remove(message.id)
                } else {
                    expandedThinking.insert(message.id)
                }
            } label: {
                HStack(spacing: 8) {
                    if live && phase == .thinking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "brain")
                    }
                    thinkingTitle(message, live: live)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded, let text = message.thinking, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func thinkingTitle(_ message: ChatMessage, live: Bool) -> some View {
        if live, phase == .thinking, let start = thinkingStart {
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text("Réflexion… \(Int(context.date.timeIntervalSince(start))) s")
            }
        } else if let seconds = message.thinkingSeconds {
            Text("Réflexion · \(seconds) s")
        } else {
            Text("Réflexion")
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            if messagesList.last?.role == "user", !isGenerating {
                Button("Réessayer") { retry() }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 6)
    }

    // MARK: - Barre de saisie (avec le quota)

    private var quotaLabel: String {
        let used = Int((quota.fractionUsed * 100).rounded())
        let shown = showRemaining ? 100 - used : used
        return "\(shown)%"
    }

    private var quotaChip: some View {
        Button { showQuota = true } label: {
            VStack(spacing: 2) {
                QuotaRing(fraction: quota.fractionUsed)
                Text(quotaLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var historyDrawer: some View {
        if showHistory {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { closeHistory() }
                    .transition(.opacity)

                HistorySheet(chats: chats, onClose: { closeHistory() })
                    .frame(maxWidth: 340, maxHeight: .infinity)
                    .background(Color(.systemBackground).ignoresSafeArea(edges: .vertical))
                    .shadow(radius: 12)
                    .transition(.move(edge: .leading))
            }
        }
    }

    private func closeHistory() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showHistory = false
        }
    }

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingPreviews.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                removePending(index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .accessibilityLabel("Retirer la photo")
                            .offset(x: 6, y: -6)
                        }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 64)
    }

    private func removePending(_ index: Int) {
        guard pendingPreviews.indices.contains(index) else { return }
        pendingPreviews.remove(at: index)
        if pendingImages.indices.contains(index) {
            pendingImages.remove(at: index)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !pendingPreviews.isEmpty {
                previewStrip
            }
        HStack(alignment: .bottom, spacing: 8) {
            quotaChip

            HStack(alignment: .bottom, spacing: 6) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Image(systemName: pendingImages.isEmpty ? "plus.circle" : "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(pendingImages.isEmpty ? Color.secondary : Color.accentColor)
                }
                .accessibilityLabel("Joindre des photos")
                .onChange(of: pickerItems) { _, items in
                    // Ignore le changement provoqué par la remise à zéro de la sélection
                    guard !items.isEmpty else { return }
                    Task {
                        var loaded: [String] = []
                        var previews: [UIImage] = []
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                loaded.append(data.base64EncodedString())
                                if let image = UIImage(data: data) {
                                    previews.append(image)
                                }
                            }
                        }
                        pendingImages = loaded
                        pendingPreviews = previews
                        pickerItems = []
                    }
                }

                TextField(speech.isRecording ? "Je t'écoute…" : "Écris un message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                Button { toggleVoice() } label: {
                    Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(speech.isRecording ? Color.red : Color.secondary)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .padding(.bottom, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if isGenerating {
                Button { stopGeneration() } label: {
                    Image(systemName: "stop.circle.fill").accessibilityLabel("Arrêter la réponse")
                        .font(.system(size: 34))
                }
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").accessibilityLabel("Envoyer")
                        .font(.system(size: 34))
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        }
    }

    // MARK: - Choix du modèle

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

    // MARK: - Envoi et génération

    private func toggleVoice() {
        if speech.isRecording {
            speech.stop()
        } else {
            inputFocused = false
            voiceBase = draft
            speech.start()
        }
    }

    private func newChat() {
        stopGeneration()
        chats.newConversation()
        errorText = nil
    }

    // Vérifie qu'on peut générer, sinon affiche pourquoi
    private func preflight() -> String? {
        guard let choice = resolvedChoice else {
            errorText = "Aucun modèle disponible. Renseigne l'adresse de ton PC dans le menu, ou choisis un fournisseur."
            return nil
        }
        guard choice.hasPrefix("ollama:") else {
            errorText = "Ce fournisseur (clé API) arrive bientôt. Pour l'instant utilise Automatique ou Ollama sur ton PC."
            return nil
        }
        guard quota.remaining > 0 else {
            errorText = "Quota mensuel atteint. Il se remet à zéro le mois prochain."
            return nil
        }
        let name = String(choice.dropFirst("ollama:".count))
        return (name == "auto" || name.isEmpty) ? ollamaModel : name
    }

    private func send(_ override: String? = nil) {
        let text = (override ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        errorText = nil

        guard let model = preflight() else { return }

        if speech.isRecording { speech.stop() }
        if chats.currentID == nil {
            chats.newConversation()
        }
        guard let convID = chats.currentID else { return }

        draft = ""
        voiceBase = ""
        let images = pendingImages
        pendingImages = []
        pendingPreviews = []
        chats.append(ChatMessage(role: "user", content: text), to: convID)
        Haptics.light()
        startGeneration(convID: convID, model: model, images: images)
    }

    private func retry() {
        errorText = nil
        guard !isGenerating, let convID = chats.currentID, let model = preflight() else { return }
        startGeneration(convID: convID, model: model)
    }

    private func regenerate() {
        guard !isGenerating, let convID = chats.currentID, let last = messagesList.last, last.role == "assistant" else { return }
        errorText = nil
        guard let model = preflight() else { return }
        chats.remove(last.id, in: convID)
        startGeneration(convID: convID, model: model)
    }

    private func startGeneration(convID: UUID, model: String, images: [String] = []) {
        let history = chats.messages(of: convID).filter { !$0.content.isEmpty }
        let placeholder = ChatMessage(role: "assistant", content: "")
        chats.append(placeholder, to: convID)
        let msgID = placeholder.id

        streamingID = msgID
        phase = .sending
        thinkingStart = nil
        rawBuffer = ""

        let client = OllamaClient(host: ollamaHost, model: model)
        let wantThink = showThinking
        let prompt = systemPrompt

        generation = Task { @MainActor in
            do {
                do {
                    try await client.chat(messages: history, images: images, system: prompt, think: wantThink) { event in
                        handle(event, convID: convID, msgID: msgID)
                    }
                } catch OllamaError.thinkingUnsupported {
                    rawBuffer = ""
                    try await client.chat(messages: history, images: images, system: prompt, think: false) { event in
                        handle(event, convID: convID, msgID: msgID)
                    }
                }
                endGeneration(convID: convID, msgID: msgID, error: nil)
            } catch {
                endGeneration(convID: convID, msgID: msgID, error: error)
            }
        }
    }

    private func stopGeneration() {
        generation?.cancel()
    }

    private func beginThinking(msgID: UUID) {
        phase = .thinking
        thinkingStart = Date()
        expandedThinking.insert(msgID)
    }

    private func finishThinkingTimer(convID: UUID, msgID: UUID) {
        guard let start = thinkingStart else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        thinkingStart = nil
        chats.update(msgID, in: convID) { $0.thinkingSeconds = seconds }
    }

    private func handle(_ event: OllamaEvent, convID: UUID, msgID: UUID) {
        switch event {
        case .connected:
            break

        case .thinking(let text):
            if phase == .sending { beginThinking(msgID: msgID) }
            chats.update(msgID, in: convID) { $0.thinking = ($0.thinking ?? "") + text }

        case .content(let text):
            rawBuffer += text
            let parts = Self.splitThink(rawBuffer)

            if parts.thinking != nil, phase == .sending {
                beginThinking(msgID: msgID)
            }
            if parts.thinkOpen {
                phase = .thinking
            } else if !parts.answer.isEmpty, phase != .writing {
                finishThinkingTimer(convID: convID, msgID: msgID)
                phase = .writing
            }

            chats.update(msgID, in: convID) { message in
                if let thinking = parts.thinking { message.thinking = thinking }
                message.content = parts.answer
            }
        }
    }

    private func endGeneration(convID: UUID, msgID: UUID, error: Error?) {
        finishThinkingTimer(convID: convID, msgID: msgID)
        streamingID = nil
        generation = nil
        expandedThinking.remove(msgID)
        if error == nil {
            quota.registerMessage()
        }

        let message = chats.messages(of: convID).first { $0.id == msgID }
        let isEmpty = (message?.content.isEmpty ?? true) && (message?.thinking ?? "").isEmpty
        if isEmpty {
            chats.remove(msgID, in: convID)
        }

        guard let error else {
            if isEmpty { errorText = "Le modèle n'a rien répondu." }
            return
        }
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        errorText = Self.describe(error)
    }

    private static func describe(_ error: Error) -> String {
        if let known = error as? OllamaError {
            return known.errorDescription ?? "Erreur inconnue."
        }
        return "Ton PC ne répond pas. Vérifie qu'il est allumé, sur le même Wi-Fi, et qu'Ollama tourne."
    }

    // Certains modèles écrivent leur réflexion entre <think> et </think> dans la réponse
    private static func splitThink(_ raw: String) -> (thinking: String?, answer: String, thinkOpen: Bool) {
        guard let open = raw.range(of: "<think>") else {
            return (nil, String(raw.drop(while: { $0.isWhitespace })), false)
        }
        let before = String(raw[..<open.lowerBound])
        let after = raw[open.upperBound...]
        if let close = after.range(of: "</think>") {
            let thinking = String(after[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = before + String(after[close.upperBound...])
            return (thinking, String(answer.drop(while: { $0.isWhitespace })), false)
        }
        return (String(after), String(before.drop(while: { $0.isWhitespace })), true)
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
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private func closePanel() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
    @State private var search = ""
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var confirmDeleteAll = false
    @State private var pendingDelete: UUID?

    private var filtered: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return chats.conversations }
        return chats.conversations.filter { conv in
            conv.title.lowercased().contains(query)
                || conv.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    private var pinned: [Conversation] {
        filtered.filter { $0.isPinned }
    }

    private var others: [Conversation] {
        filtered.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationStack {
            List {
                if !pinned.isEmpty {
                    Section("Épinglées") {
                        ForEach(pinned) { conv in row(conv) }
                    }
                }
                if !others.isEmpty {
                    Section(pinned.isEmpty ? "" : "Récentes") {
                        ForEach(others) { conv in row(conv) }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(
                            search.isEmpty ? "Aucune conversation" : "Aucun résultat",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label("Tout supprimer", systemImage: "trash")
                        }
                        .disabled(chats.conversations.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("Plus d’options")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        chats.newConversation()
                        closePanel()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    Button("OK") { closePanel() }
                }
            }
            .confirmationDialog(
                "Supprimer cette conversation ?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let id = pendingDelete { chats.delete(id) }
                    pendingDelete = nil
                }
                Button("Annuler", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Cette action est définitive.")
            }
            .confirmationDialog("Supprimer toutes les conversations ?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Tout supprimer", role: .destructive) {
                    chats.deleteAll()
                }
            } message: {
                Text("Cette action est définitive.")
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

    private func row(_ conv: Conversation) -> some View {
        HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if conv.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(conv.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(preview(conv))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if conv.id == chats.currentID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            Menu {
                Button {
                    startRename(conv)
                } label: {
                    Label("Renommer", systemImage: "pencil")
                }
                Button {
                    chats.togglePin(conv.id)
                } label: {
                    Label(conv.isPinned ? "Désépingler" : "Épingler", systemImage: conv.isPinned ? "pin.slash" : "pin")
                }
                Divider()
                Button(role: .destructive) {
                    pendingDelete = conv.id
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options de la conversation")
            }
        .contentShape(Rectangle())
        .onTapGesture {
            chats.currentID = conv.id
            closePanel()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = conv.id
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            Button {
                startRename(conv)
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                chats.togglePin(conv.id)
            } label: {
                Label(conv.isPinned ? "Désépingler" : "Épingler", systemImage: conv.isPinned ? "pin.slash" : "pin")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button { startRename(conv) } label: {
                Label("Renommer", systemImage: "pencil")
            }
            Button { chats.togglePin(conv.id) } label: {
                Label(conv.isPinned ? "Désépingler" : "Épingler", systemImage: conv.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { pendingDelete = conv.id } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func startRename(_ conv: Conversation) {
        renameID = conv.id
        renameText = conv.title
    }

    private func preview(_ conv: Conversation) -> String {
        guard let last = conv.messages.last(where: { !$0.content.isEmpty }) else {
            return "Conversation vide"
        }
        return last.content.replacingOccurrences(of: "\n", with: " ")
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
