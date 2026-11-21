// Configuration fixe de l'app : elle ne se modifie pas dans les réglages.
enum ServerConfig {
    // Ollama sur ton PC (réseau local)
    static let ollamaHost = "192.168.1.40:11434"
    static let ollamaModel = "llama3.2-vision"

    // Serveur HoloPhotos sur ton PC (accessible partout via Tailscale Funnel)
    static let holoURL = "https://spf75-202402031810.tailead836.ts.net"

    // À REMPLACER par le secret défini sur ton PC (HOLO_SECRET), directement dans ce fichier sur GitHub.
    static let holoSecret = "1087509265726384097509821739083408957689265921652703123574789624"
}
