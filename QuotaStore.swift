import Foundation

final class QuotaStore: ObservableObject {
    static let monthlyLimit = 300

    @Published private(set) var used: Int = 0

    private let usedKey = "quotaUsed"
    private let monthKey = "quotaMonth"

    init() {
        refreshMonth()
    }

    private var currentMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    // Remet le compteur à zéro au changement de mois
    func refreshMonth() {
        let saved = UserDefaults.standard.string(forKey: monthKey)
        if saved != currentMonth {
            UserDefaults.standard.set(currentMonth, forKey: monthKey)
            UserDefaults.standard.set(0, forKey: usedKey)
        }
        used = UserDefaults.standard.integer(forKey: usedKey)
    }

    var remaining: Int {
        max(Self.monthlyLimit - used, 0)
    }

    var fractionUsed: Double {
        min(Double(used) / Double(Self.monthlyLimit), 1)
    }

    func registerMessage() {
        refreshMonth()
        used += 1
        UserDefaults.standard.set(used, forKey: usedKey)
    }
}
