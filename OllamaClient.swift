import Foundation

enum OllamaEvent {
    case connected
    case thinking(String)
    case content(String)
}

enum OllamaError: LocalizedError {
    case badHost
    case http(Int)
    case server(String)
    case thinkingUnsupported

    var errorDescription: String? {
        switch self {
        case .badHost:
            return "L'adresse de ton PC est invalide. Vérifie-la dans « Serveur Ollama »."
        case .http(let code):
            if code == 404 {
                return "Modèle introuvable sur ton PC. Vérifie son nom dans « Serveur Ollama »."
            }
            return "Ton PC a répondu avec une erreur (\(code))."
        case .server(let message):
            return message
        case .thinkingUnsupported:
            return "Ce modèle ne gère pas la réflexion."
        }
    }
}

struct OllamaClient {
    let host: String
    let model: String

    // Réponse en streaming : les événements arrivent au fur et à mesure
    @MainActor
    func chat(
        messages: [ChatMessage],
        images: [String] = [],
        system: String?,
        think: Bool,
        onEvent: (OllamaEvent) -> Void
    ) async throws {
        var base = host.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { throw OllamaError.badHost }
        if !base.hasPrefix("http") { base = "http://" + base }
        guard let url = URL(string: base + "/api/chat") else { throw OllamaError.badHost }

        var payload: [[String: Any]] = []
        if let system {
            payload.append(["role": "system", "content": system])
        }
        for (index, message) in messages.enumerated() {
            var entry: [String: Any] = ["role": message.role, "content": message.content]
            // Les photos ne sont jointes qu'au dernier message utilisateur, et seulement envoyées à Ollama
            if index == messages.count - 1, message.role == "user", !images.isEmpty {
                entry["images"] = images
            }
            payload.append(entry)
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": payload
        ]
        if think { body["think"] = true }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 400 && think { throw OllamaError.thinkingUnsupported }
            throw OllamaError.http(http.statusCode)
        }
        onEvent(.connected)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard
                let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let error = json["error"] as? String {
                throw OllamaError.server(error)
            }
            if let message = json["message"] as? [String: Any] {
                if let thinking = message["thinking"] as? String, !thinking.isEmpty {
                    onEvent(.thinking(thinking))
                }
                if let content = message["content"] as? String, !content.isEmpty {
                    onEvent(.content(content))
                }
            }
            if (json["done"] as? Bool) == true { break }
        }
    }
}
