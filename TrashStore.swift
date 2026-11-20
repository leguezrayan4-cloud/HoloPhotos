import Foundation

// Corbeille interne à l'app : les éléments « supprimés » sont masqués dans Photos
// et listés ici avec leur date. Ils sont effacés pour de bon après le délai choisi.
enum TrashStore {
    private static let key = "trashEntries"

    private static var entries: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var ids: Set<String> { Set(entries.keys) }

    static func add(_ ids: [String]) {
        var all = entries
        let now = Date().timeIntervalSince1970
        for id in ids { all[id] = now }
        entries = all
    }

    static func remove(_ ids: [String]) {
        var all = entries
        for id in ids { all.removeValue(forKey: id) }
        entries = all
    }

    // 0 = jamais
    static var retentionDays: Int {
        UserDefaults.standard.object(forKey: "trashRetentionDays") as? Int ?? 30
    }

    static func daysLeft(for id: String) -> Int? {
        let days = retentionDays
        guard days > 0, let start = entries[id] else { return nil }
        let remaining = start + Double(days) * 86_400 - Date().timeIntervalSince1970
        return max(Int((remaining / 86_400).rounded(.up)), 0)
    }

    static func expiredIDs() -> [String] {
        let days = retentionDays
        guard days > 0 else { return [] }
        let limit = Date().timeIntervalSince1970 - Double(days) * 86_400
        return entries.filter { $0.value <= limit }.map { $0.key }
    }

    static var deleteMessage: String {
        let days = retentionDays
        if days > 0 {
            return "Il ira dans « Supprimés récemment » pendant \(days) jours."
        }
        return "Il ira dans « Supprimés récemment » jusqu'à ce que tu le supprimes toi-même."
    }

    static var footer: String {
        let days = retentionDays
        if days > 0 {
            return "Les éléments sont supprimés définitivement après \(days) jours. Tu peux changer ce délai dans Réglages."
        }
        return "Les éléments restent ici jusqu'à ce que tu les supprimes toi-même."
    }
}
