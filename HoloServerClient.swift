import Foundation

// Appelle le serveur HoloPhotos installé sur ton PC (server.py).
// La clé OpenRouter reste sur le PC : l'app n'envoie que le message et le secret partagé.
enum HoloServerError: LocalizedError {
    case notConfigured
    case unauthorized
    case unreachable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Renseigne l'adresse et le secret de ton serveur dans Réglages > Intelligence artificielle."
        case .unauthorized:
            return "Le secret ne correspond pas à celui de ton serveur."
        case .unreachable:
            return "Ton serveur ne répond pas. Vérifie qu'il est allumé et que le script tourne."
        case .server(let detail):
            return "Le serveur a renvoyé une erreur : \(detail)"
        }
    }
}

// Correspondance entre les modèles proposés dans l'app et les identifiants OpenRouter.
// Vérifie ces identifiants sur openrouter.ai/models : ils peuvent changer.
enum HoloModels {
    static let openRouterSlugs: [String: String] = [
        "claude:claude-opus-5-5": "anthropic/claude-opus-4.5",
        "claude:claude-sonnet-5-5": "anthropic/claude-sonnet-4.5",
        "claude:claude-haiku-5-5": "anthropic/claude-haiku-4.5",
        "chatgpt:gpt-4o": "openai/gpt-4o",
        "chatgpt:gpt-4o-mini": "openai/gpt-4o-mini",
        "gemini:gemini-2.0-flash": "google/gemini-2.0-flash-001",
        "gemini:gemini-1.5-pro": "google/gemini-pro-1.5",
    ]

    static func slug(for choice: String) -> String? {
        openRouterSlugs[choice]
    }
}

struct HoloServerClient {
    let baseURL: String
    let secret: String

    func chat(model: String, messages: [ChatMessage], system: String) async throws -> String {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedSecret.isEmpty else { throw HoloServerError.notConfigured }

        var address = trimmedURL
        if !address.hasPrefix("http") { address = "http://" + address }
        guard let url = URL(string: address + "/v1/chat") else { throw HoloServerError.notConfigured }

        var payloadMessages: [[String: String]] = []
        if !system.isEmpty {
            payloadMessages.append(["role": "system", "content": system])
        }
        for message in messages where !message.content.isEmpty {
            payloadMessages.append(["role": message.role, "content": message.content])
        }
        let body: [String: Any] = ["model": model, "messages": payloadMessages]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedSecret, forHTTPHeaderField: "X-Holo-Secret")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HoloServerError.unreachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw HoloServerError.unauthorized }
        guard status == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw HoloServerError.server(detail ?? "code \(status)")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw HoloServerError.server("réponse illisible")
        }
        return content
    }
}
