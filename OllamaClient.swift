import Foundation

struct OllamaClient {
    let host: String
    let model: String

    func chat(messages: [ChatMessage]) async throws -> String {
        var base = host.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { throw URLError(.badURL) }
        if !base.hasPrefix("http") { base = "http://" + base }
        guard let url = URL(string: base + "/api/chat") else { throw URLError(.badURL) }

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }
}
